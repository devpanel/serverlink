#include <stdio.h>
#include <fcntl.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "suexec.h"

extern const char *__progname;
void usage(const int ret) {
	fprintf(stderr,
"Usage: %s <account> < ? | 0 | <+|-|=|?><0-7> > [filename]\n"
"\n"
"       ?  = get current configuration\n"
"       0  = clean configuration\n"
"       +N = set Nth bit\n"
"       -N = clear Nth bit\n"
"       =N = set Nth bit, clear all others\n"
"       ?N = get Nth bit\n"
"\n"
"[filename] is a file which holds suexec mapping (default: %s)\n\n",
__progname, SUEXEC_MAP_FILE);
	exit(ret);
}

int main(int argc, char **argv)
{
	struct passwd *pw;
	int fd;
	unsigned char flag = 0, value = 0, old = 0;
	enum { query, bit_query, replace, set, clear } mode = query;

	if (argc == 1) usage(0);

	if (argc != 3 && argc != 4) usage(1);

	if (!(pw = getpwnam(argv[1]))) {
		fprintf(stderr, "Error during getting account information for '%s'.\n",
			argv[1]);
		return 1;
	}

	if (argv[2][1] && argv[2][2]) usage(1);

	if (!argv[2][1]) {
		switch (argv[2][0]) {
			case '0':
				mode = replace;
				break;
			case '?':
				mode = query;
				break;
			default:
				usage(1);
		}
	} else {
		switch (argv[2][0]) {
			case '+':
				mode = set;
				break;
			case '-':
				mode = clear;
				break;
			case '=':
				mode = replace;
				break;
			case '?':
				mode = bit_query;
				break;
			default :
				usage(1);
		}
		switch (argv[2][1]) {
			case '0':
			case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6':
			case '7':
				flag = 1 << (argv[2][1] - '0');
				break;
			default :
				usage(1);
		}
	}

	if ((fd = open(argc == 4 ? argv[3] : SUEXEC_MAP_FILE, O_RDWR)) < 0) {
		fprintf(stderr, "Couldn't open '%s': %s\n", SUEXEC_MAP_FILE, strerror(errno));
		return 1;
	}
	if (lseek(fd, pw->pw_uid, SEEK_SET) < 0) {
		fprintf(stderr, "Couldn't seek() '%s': %s\n", SUEXEC_MAP_FILE, strerror(errno));
		return 1;
	}
	if (read(fd, &old, 1) != 1) {
		fprintf(stderr, "Couldn't read() '%s': %s\n", SUEXEC_MAP_FILE, strerror(errno));
		return 1;
	}
	if (mode == replace || mode == set || mode == clear) {
		if (mode == replace) {
			value = flag;
		} else
		if (mode == set) {
			value = (old | flag);
		} else {
			value = (old & ~flag);
		}
		if (old != value) {
			if (lseek(fd, pw->pw_uid, SEEK_SET) < 0) {
				fprintf(stderr, "Couldn't seek() '%s': %s\n", SUEXEC_MAP_FILE, strerror(errno));
				return 1;
			}
			if (write(fd, &value, 1) != 1) {
				fprintf(stderr, "Couldn't write() '%s': %s\n", SUEXEC_MAP_FILE, strerror(errno));
				return 1;
			}
		}
	}

	if (close(fd)) {
		fprintf(stderr, "Couldn't close() '%s': %s\n", SUEXEC_MAP_FILE, strerror(errno));
		return 1;
	}

	if (mode == query || mode == bit_query) {
		printf("uid=%d value=%u%s", pw->pw_uid, old, (mode == query ? "\n" : " "));
		if (mode == bit_query) printf("bit=%u\n", ((old & flag) != 0));
	} else if (mode == replace || mode == set || mode == clear) {
		if (old != value)
			printf("uid=%d value=%d old=%d status=changed\n",
				pw->pw_uid, value, old);
		else
			printf("uid=%d value=%d status=unchanged\n", pw->pw_uid, value);
	} else {
		fprintf(stderr, "internal error: unimplemented mode of operation\n");
		return 1;
	}

	return 0;
}
