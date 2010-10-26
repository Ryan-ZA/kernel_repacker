#include <stdio.h>
int findzeros(FILE *fp) {
	int c;
	int count = 0;
	int offset = 0;
	do {
		c = fgetc (fp);
		if (c != 0) {
			count = 0;
		} else {
			count++;
			if (count > 16) {
				return offset;
			}
		}
		offset++;
    } while (c != EOF);
	
	return -1;
}
int findnonzero(FILE *fp) {
	int c;
	int offset = 0;
	do {
		c = fgetc (fp);
		if (c != 0) {
			return offset;
		} else {
			offset++;
		}
    } while (c != EOF);
	
	return -1;
}
int main(int argc,char* args[]) {
	register FILE *fp = stdin;
	int zerostart = findzeros(fp);
	int zeroend = findnonzero(fp);
	printf("%d\t%d\n", zerostart, zerostart+zeroend);
}
