BINDIR=/usr/bin

all: suexec chcgi

suexec: suexec.h suexec.c
	$(CC) $(CFLAGS) suexec.c -o suexec

chcgi: chcgi.c
	$(CC) $(CFLAGS) chcgi.c -o chcgi

install:
	mkdir -p $(DESTDIR)$(BINDIR)
	install -p -m710 -t $(DESTDIR)$(BINDIR) suexec
	install -p -m710 -t $(DESTDIR)$(BINDIR) chcgi

clean:
	@rm -f chcgi suexec
	@echo OK

.PHONY: all install clean
