#include <stdio.h>
#include "DES.h"

const unsigned char *PLAIN = "HelloDES";
const unsigned char *KEY = "8bytekey";

int main() {
	unsigned char buf[8];

	printf("plain: %s\n", PLAIN);
	printf("key  : %s\n", KEY);

	encrypt(PLAIN, buf, KEY);

	printf("ciphertext: ");
	for (int i = 0; i < 8; i++) {
		printf("%02x", (unsigned char)buf[i]);
	}
	putchar(0xa);
}
