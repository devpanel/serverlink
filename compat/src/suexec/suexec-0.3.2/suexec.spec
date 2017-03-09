# $OwlX: Owl-extra/packages/httpd-suexec/httpd-suexec/httpd-suexec.spec,v 1.2 2011/01/31 18:47:37 galaxy Exp $

Summary: suEXEC helper for Apache
Name: httpd-suexec
Version: 0.3.2
Release: owlx0
License: TBD
URL: TBD
Group: Apache/Helpers

Source: %name-%version.tar.gz

BuildRoot: /override/%name-%version
Requires: httpd

%description
TBD

%prep
%if %{?owlx}0
	%define	_basedir	/opt/suexec
	%define	_prefix		%_basedir/%version-%release
	%define	_commonconfdir	%_basedir/config
%else
	%define	_prefix		/usr
	%define	_commonconfdir	%_sysconfdir
%endif
%define	_localconfdir %{nil}

%setup -q

%build
%__make "CFLAGS=$RPM_OPT_FLAGS -DHTTPD_USER2='\"apache\"'"

%install
[ '%buildroot' != '/' -a -d '%buildroot' ] && rm -rf -- '%buildroot'
mkdir -p -m755 '%buildroot%_sbindir'
%__make install 'DESTDIR=%buildroot' 'BINDIR=%_sbindir'

# create an empty suexec.map
mkdir -p -m755 '%buildroot%_commonconfdir'
dd if=/dev/zero 'of=%buildroot%_commonconfdir/suexec.map' bs=65535 count=1

%if %{?owlx}0
ln -s '%version-%release' '%buildroot%_basedir/current'
mkdir -p '%buildroot%_sysconfdir'
ln -s '%_basedir%_commonconfdir/suexec.map' '%buildroot%_sysconfdir/suexec.map'
%else
mv '%buildroot%_sbindir/suexec' '%buildroot%_sbin/suexec-%version-%release'
ln -s 'suexec-%version-%release' '%buildroot%_sbindir/suexec'
%endif

# clean up

%clean
[ '%buildroot' != '/' -a -d '%buildroot' ] && rm -rf -- '%buildroot'

%post
%{?owlx_setup_current}
if [ ! -e '%_commonconfdir/suexec.map' ]; then
	dd if=/dev/zero 'of=%_commonconfdir/suexec.map' bs=65535 count=1 || :
	chmod 0600 '%_commonconfdir/suexec.map'
fi
[ ! -e '%_sysconfdir/suexec.map' ] && ln -s '%_commonconfdir/suexec.map' '%_sysconfdir/suexec.map' || :

%files
%defattr(0644,root,root,0755)
%if %{?owlx}0
%dir %_basedir
%ghost %config(missingok, noreplace) %_basedir/current
%dir %_prefix
%dir %_sysconfdir
%dir %_sbindir
%attr(4710,root,_httpd) %_sbindir/suexec
%ghost %config(noreplace) %_sysconfdir/suexec.map
%else
%config(noreplace) %_sbindir/%name
%attr(4710,root,_httpd) %_sbindir/suexec-%version-%release
%endif
%ghost %attr(0600,root,root) %config(noreplace) %_commonconfdir/suexec.map
%attr(0700,root,root) %_sbindir/chcgi

%changelog
* Sun Jan 09 2011 (GalaxyMaster) <galaxy-at-owl.openwall.com> 0.3.2-owlx0
- moved definitions of the helper programs to suexec.h;
- moved sources to the native tree.

* Fri Dec 24 2010 (GalaxyMaster) <galaxy-at-owl.openwall.com> 0.3.0-owlx0
- minor fixes.

* Sun Jun 20 2010 (GalaxyMaster) <galaxy-at-owl.openwall.com> 0.3.0-gm2
- removed the %%verify part in the %%files section to be compatible with
Owl 2.0-stable.

* Mon Dec 21 2009 (GalaxyMaster) <galaxy-at-owl.openwall.com> 0.3.0-gm1
- Fixed the post-install script.

* Sun Oct 11 2009 (GalaxyMaster) <galaxy-at-owl.openwall.com> 0.3.0-gm0
- Initial Owl release.
