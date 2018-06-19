BINDIR=/compat/suexec

all: all-binaries

all-binaries:
	rm -f suexec.h
	rm -f {suexec,chcgi}.{ubuntu,debian,centos}.{x86_64,i386}
	ln -s suexec.h.ubuntu suexec.h
	$(CC) $(CFLAGS) -march=x86-64 suexec.c -o suexec.ubuntu.x86_64
	$(CC) $(CFLAGS) -m32          suexec.c -o suexec.ubuntu.i386
	$(CC) $(CFLAGS) -march=x86-64 chcgi.c  -o chcgi.ubuntu.x86_64
	$(CC) $(CFLAGS) -m32          chcgi.c  -o chcgi.ubuntu.i386
	rm -f suexec.h
	ln -s suexec.h.centos suexec.h
	$(CC) $(CFLAGS) -march=x86-64 suexec.c -o suexec.centos.x86_64
	$(CC) $(CFLAGS) -m32          suexec.c -o suexec.centos.i386
	$(CC) $(CFLAGS) -march=x86-64 chcgi.c  -o chcgi.centos.x86_64
	$(CC) $(CFLAGS) -m32          chcgi.c  -o chcgi.centos.i386
	rm -f suexec.h
	ln -s suexec.h.debian suexec.h
	$(CC) $(CFLAGS) -march=x86-64 suexec.c -o suexec.debian.x86_64
	$(CC) $(CFLAGS) -m32          suexec.c -o suexec.debian.i386
	$(CC) $(CFLAGS) -march=x86-64 chcgi.c  -o chcgi.debian.x86_64
	$(CC) $(CFLAGS) -m32          chcgi.c  -o chcgi.debian.i386
	rm -f suexec.h

suexec: suexec.h suexec.c
	$(CC) $(CFLAGS) suexec.c -o suexec

chcgi: chcgi.c
	$(CC) $(CFLAGS) chcgi.c -o chcgi

install:
	mkdir -p $(DESTDIR)$(BINDIR)
	install -p -m710 -t $(DESTDIR)$(BINDIR) suexec
	install -p -m710 -t $(DESTDIR)$(BINDIR) chcgi

install-all:
	install -p -m2710 -t $(DESTDIR)$(BINDIR) suexec.*
	install -p -m710  -t $(DESTDIR)$(BINDIR) chcgi.*

clean:
	@rm -f chcgi suexec
	@echo OK

.PHONY: all install clean
