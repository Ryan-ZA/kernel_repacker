#!/bin/bash
##############################################################################
# usage : ./editor.sh [kernel] [initramfs.cpio]                                                                                      #
# example : ./editor.sh  /home/zero/Desktop/test/zImage  /home/zero/Desktop/test/ramdisk.cpio     #
##############################################################################
# you should point where your cross-compiler is                                                                                 #
COMPILER=~/x-tools/arm-z4-linux-gnueabi/bin/arm-z4-linux-gnueabi
##############################################################################

zImage=$1
new_ramdisk=$2
kernel="./out/kernel.image"
test_unzipped_cpio="./out/cpio.image"
head_image="./out/head.image"
tail_image="./out/tail.image"
ramdisk_image="./out/ramdisk.image"
workdir=`pwd`

printhl() {
	printf "${C_H1}${1}${C_CLEAR} \n"
}

printerr() {
	printf "${C_ERR}${1}${C_CLEAR} \n"
}

exit_usage() {
	printhl "\nUsage:"
	echo    "  repack.sh <zImage> <initramfs.cpio>"
	printhl "\nWhere:"
	echo    "zImage          = the zImage file (kernel) you wish to repack"
	echo -e "initramfs.cpio  = the cpio (initramfs) you wish to pack into the zImage\n"
	exit 1
}

if [ "$1" == "" -o "$2" == ""]; then
	exit_usage()
fi



#=======================================================
# find start of gziped kernel object in the zImage file:
#=======================================================

pos=`grep -F -a -b -m 1 --only-matching $'\x1F\x8B\x08' $zImage | cut -f 1 -d :`
printhl("Extracting kernel from $zImage (start = $pos)")
mkdir out 2>/dev/null
dd if=$zImage bs=$pos skip=1 | gunzip > $kernel

#=======================================================
# Determine if the cpio inside the zImage is gzipped
#=======================================================
unzipped_cpio=$kernel
gzip_start_arr=`grep -a -b --only-matching $'\x1F\x8B\x08' $kernel`
for possible_gzip_start in $gzip_start_arr; do
	dd if=$kernel bs=$possible_gzip_start skip=1 | gunzip > $test_unzipped_cpio
	if [ $? -ne 1 ]; then
		printhl("gzipped archive detected")
		unzipped_cpio=$test_unzipped_cpio
		break
	fi
done

#===========================================================================
# ASCII cpio header starts with '070701'
# Once we have the header, we can find the length using 'pax'
#===========================================================================
start=`grep -F -a -b -m 1 --only-matching '070701' $unzipped_cpio | head -1 | cut -f 1 -d :`
end=`dd if=$unzipped_cpio bs=$start skip=1 | pax -v | tail -1 | cut -f 3 -d , | awk '{ print $1 }'`
if [ "$start" = "" -o "$end" = "" -o ]; then
	printerr("Could not detect a CPIO Archive!")
	exit
fi

count=$((end - start))

if [ $count -lt 0 ]; then
  printerr("Could not correctly determine the starting and ending positions of the CPIO!")
  exit
fi

# Check the Image's size
filesize=`ls -l $Image_here | awk '{print $5}'`

# Split the Image #1 ->  head.img
printhl("Making head.img ( from 0 ~ $start )")
dd if=$kernel bs=$start count=1 of=$head_image

# Split the Image #2 ->  tail.img
printhl("Making a tail.img ( from $end ~ $filesize )")
dd if=$kernel bs=$end skip=1 of=$tail_image

# Check the new ramdisk's size
ramdsize=`ls -l $new_ramdisk | awk '{print $5}'`
printhl("The size of the new ramdisk is $ramdsize and the old ramdisk is $count"

if [ $ramdsize -gt $count ]; then
	printhl("The new ramdisk is bigger than the old -- taking steps to reduce the size")
	if [ "gzip" != "`file $new_ramdisk`" ]; then
		printhl("ramdisk is not gzipped, gzipping it...")
		gzip -9 $new_ramdisk > out/ramdisk.gz
	else
		cp $new_ramdisk out/ramdisk.gz
	fi
	ramdsize=`ls -l out/ramdisk.gz | awk '{print $5}'`
	if [ $ramdsize -gt $count ]; then
		printerr("New ramdisk is bigger than old ramdisk - using lzma to compress it further..."
		gunzip -c out/ramdisk.gz | lzma -f -9 > $ramdisk_image
		ramdsize=`ls -l out/ramdisk.cpio | awk '{print $5}'`
		if [ $ramdsize -gt $count ]; then
			printerr("New ramdisk is still too big. Repack failed. $ramdsize > $count"
			exit
		fi
	else
		cp out/ramdisk.gz $ramdisk_image
	fi
else
	cp $new_ramdisk $ramdisk_image
fi

cat $head_image $ramdisk_image > out/franken.img
franksize=`ls -l out/franken.img | awk '{print $5}'`

printhl("Merging [head+ramdisk] + padding + tail")
if [ $franksize -lt $end ]; then
	tempnum=$((end - franksize))
	dd if=/dev/zero bs=$tempnum count=1 of=out/padding
	cat out/padding $tail_image > out/newtail.img
	cat out/franken.img out/newtail.img > out/new_Image
else
	printerr "Combined zImage is too large - original end is $end and new end is $franksize"
	exit
fi


#============================================
# rebuild zImage
#============================================
printhl("Now we are rebuilding the zImage")

cd resources/2.6.29
cp ../../out/new_Image arch/arm/boot/Image

#1. Image -> piggy.gz
printhl("Image ---> piggy.gz")
gzip -f -9 < arch/arm/boot/compressed/../Image > arch/arm/boot/compressed/piggy.gz

#2. piggy.gz -> piggy.o
printhl("piggy.gz ---> piggy.o")
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.piggy.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/piggy.S

#3. head.o
printhl("Compiling head")
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.head.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/head.o arch/arm/boot/compressed/head.S

#4. misc.o
printhl("Compiling misc")
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.misc.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -Wall -Wundef -Wstrict-prototypes -Wno-trigraphs -fno-strict-aliasing -fno-common -Werror-implicit-function-declaration -Os -marm -fno-omit-frame-pointer -mapcs -mno-sched-prolog -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8 -msoft-float -Uarm -fno-stack-protector -I/modules/include -fno-omit-frame-pointer -fno-optimize-sibling-calls -g -Wdeclaration-after-statement -Wno-pointer-sign -fwrapv -fpic -fno-builtin -Dstatic=  -D"KBUILD_STR(s)=\#s" -D"KBUILD_BASENAME=KBUILD_STR(misc)"  -D"KBUILD_MODNAME=KBUILD_STR(misc)"  -c -o arch/arm/boot/compressed/misc.o arch/arm/boot/compressed/misc.c

#5. head.o + misc.o + piggy.o --> vmlinux
printhl("head.o + misc.o + piggy.o ---> vmlinux")
$COMPILER-ld -EL    --defsym zreladdr=0x30008000 --defsym params_phys=0x30000100 -p --no-undefined -X toolchain_resources/libgcc.a -T arch/arm/boot/compressed/vmlinux.lds arch/arm/boot/compressed/head.o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/misc.o -o arch/arm/boot/compressed/vmlinux 

#6. vmlinux -> zImage
printhl("vmlinux ---> zImage")
$COMPILER-objcopy -O binary -R .note -R .note.gnu.build-id -R .comment -S  arch/arm/boot/compressed/vmlinux arch/arm/boot/zImage

# finishing
printhl("Cleaning up...")
mv arch/arm/boot/zImage ../../new_zImage
rm arch/arm/boot/compressed/vmlinux arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/misc.o arch/arm/boot/compressed/head.o arch/arm/boot/compressed/piggy.gz arch/arm/boot/Image
rm -rf ../../out