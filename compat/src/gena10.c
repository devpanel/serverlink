#define CHARSET	\
	"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
#define LENGTH				10
#define STRICT				0
#define CRYPT3				0

/*
 * No user serviceable parts below. Qualified personnel only.
 */

#if LENGTH > 8
#undef CRYPT3
#define CRYPT3 0
#endif

#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>

#define DEVICE				"/dev/urandom"
#define COUNT				(sizeof(CHARSET) - 1)
#if CRYPT3
#define ITOA64 \
	"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
#endif

int main(int argc, char **argv) {
	int fd;
	unsigned char random[10];
	char passwd[LENGTH + 1];
	unsigned long long value;
	int pos;
#if STRICT
	int mask;
#endif
#if CRYPT3
	char salt[3];
#endif

	if ((fd = open(DEVICE, O_RDONLY)) < 0) {
		perror("open");
		return 1;
	}

#if STRICT
retry:
#endif
	switch (read(fd, &random, sizeof(random))) {
	case sizeof(random):
		break;

	case -1:
		perror("read");
		return 1;

	default:
		fprintf(stderr, "read: EOF\n");
		return 1;
	}

#if CRYPT3
	salt[0] = ITOA64[(int)random[0] & 0x3f];
	salt[1] = ITOA64[(int)random[1] & 0x3f];
	salt[2] = 0;
#endif

	memcpy(&value, &random[2], sizeof(value));

#if STRICT
	mask = 0;
#endif
	passwd[pos = LENGTH] = 0;
	while (pos--) {
#if STRICT
		switch ((passwd[pos] = CHARSET[value % COUNT])) {
		case '0' ... '9':
			if (pos != LENGTH - 1) mask |= 1;
			break;

		case 'A' ... 'Z':
			if (pos) mask |= 2;
			break;

		case 'a' ... 'z':
			mask |= 4;
			break;

		default:
			mask |= 8;
		}
#else
		passwd[pos] = CHARSET[value % COUNT];
#endif

		value /= COUNT;
	}

#if STRICT
	if ((mask & 0x7) == 0x7) goto done;
	if ((mask & 0xB) == 0xB) goto done;
	if ((mask & 0xD) == 0xD) goto done;
	if ((mask & 0xE) == 0xE) goto done;
	goto retry;
done:
#endif

#if CRYPT3
	printf("%s %s\n", passwd, crypt(passwd, salt));
#else
	printf("%s\n", passwd);
#endif

	return 0;
}
