#!/bin/sh

if [ -z "$1" ]; then
	echo "Usage: $0 fqdn.domain.tld"
	exit 1
fi

FRONTEND_FQDN="$1"

error()
{
	echo "ERROR: $@" >&2
	echo FAIL
	exit 1
}

unquote()
{
        local _S
        _S="${1//[^\"]}"
        if [ ${#_S} -ge 2 ]; then
                _S=$(echo -n "$1" | sed 's,^[[:space:]]*"\(.*\)"[[:space:]]*$,\1,')
        fi
        echo -n "$_S"
}

# check that we are good
# is Apache is here?
httpd -t >/dev/null 2>&1 ||
	error "httpd is not in PATH or Apache is unconfigured"

# can mod_dav be loaded?
httpd -f /dev/null -c 'LoadModule dav_module modules/mod_dav.so' -t >/dev/null 2>&1 ||
	error "Could not load the mod_dav module, was it installed?"

# can mod_dav_svn be loaded?
httpd -f /dev/null -c 'LoadModule dav_module modules/mod_dav.so' -c 'LoadModule dav_svn_module modules/mod_dav_svn.so' -t >/dev/null 2>&1 ||
	error "Could not load the mod_dav_svn module, was it installed?"

# can mod_dav_svn_authz be loaded?
httpd -f /dev/null -c 'LoadModule dav_module modules/mod_dav.so' -c 'LoadModule dav_svn_module modules/mod_dav_svn.so' -c 'LoadModule authz_svn_module modules/mod_authz_svn.so' -t >/dev/null 2>&1 ||
	error "Could not load the mod_authz_svn module, was it installed?"

which curl >/dev/null 2>&1 ||
	error "curl is not in PATH, SVN post-commit hook requires cURL"

# let's configure ourselves (it's a bit unreliable with the log dir)
HTTPD_ROOT=$(httpd -V 2>/dev/null | fgrep HTTPD_ROOT= | cut -f2 -d=)
HTTPD_CONFFILE=$(httpd -V 2>/dev/null | fgrep SERVER_CONFIG_FILE= | cut -f2 -d=)
HTTPD_LOGDIR=$(httpd -V 2>/dev/null | fgrep DEFAULT_ERRORLOG= | cut -f2 -d=)
# ... Apache could embrace the values with double quotes, let's remove them
HTTPD_ROOT=$(unquote $HTTPD_ROOT)
HTTPD_CONFFILE=$(unquote $HTTPD_CONFFILE)
HTTPD_LOGDIR=$(unquote $HTTPD_LOGDIR)
HTTPD_LOGDIR="${HTTPD_LOGDIR%/*}"
# the config file path may be absolute or relative
[ "${HTTPD_CONFFILE:0:1}" != '/' ] && HTTPD_CONFFILE="$HTTPD_ROOT/$HTTPD_CONFFILE"
# the logs dir path may be absolute or relative
HTTPD_LOGDIR_ABS="$HTTPD_LOGDIR"
[ "${HTTPD_LOGDIR:0:1}" != '/' ] && HTTPD_LOGDIR_ABS="$HTTPD_ROOT/$HTTPD_LOGDIR"

# well, now check that all of the above is good
[ -z "$HTTPD_ROOT" -o -z "$HTTPD_CONFFILE" -o -z "$HTTPD_LOGDIR_ABS" \
	-o ! -d "$HTTPD_ROOT" -o ! -d "$HTTPD_LOGDIR_ABS" -o ! -s "$HTTPD_CONFFILE" ] &&
	error "Could not get the configuration information from Apache!"

# ok, everything looks good, let's install our stuff
CONFDIR="${HTTPD_CONFFILE%/*}"

# Bail out on any error
set -e

if [ ! -e "$CONFDIR/manage-svn.conf" ]; then
	cat > "$CONFDIR/manage-svn.conf" << EOF
# The home directory where SVN user accounts will be created (e.g. for
# the s_test account with SVN_HOME=/home the home directory will be
# /home/s_test).
SVN_HOME=/home

# The start of the port range allocated for the SVN instances.
SVN_START_PORT=5000
EOF
	chmod 0600 "$CONFDIR/manage-svn.conf"
	chown -h root:root "$CONFDIR/manage-svn.conf"
fi

# this one is tricky - different distros configure their Apache differently
# let's assume we are working with RH compatible layout where they use
# conf.d on the same level as conf .
if [ -d "${CONFDIR}.d" ]; then
	sed "
s#@@FRONTEND_FQDN@@#$FRONTEND_FQDN#g;
s#@@CLIENTS_MAP@@#$CONFDIR/svn-clients.map#g;
" etc/websvn_frontend.conf > "${CONFDIR}.d/websvn_frontend.conf"
	chmod 0600 "${CONFDIR}.d/websvn_frontend.conf"
	chown root:root "${CONFDIR}.d/websvn_frontend.conf"
	if [ ! -e "$CONFDIR/svn-clients.map" ]; then
		touch "$CONFDIR/svn-clients.map"
		chmod 0600 "$CONFDIR/svn-clients.map"
		chown -h root:root "$CONFDIR/svn-clients.map"
	fi
	if ! httpd -t >/dev/null 2>&1 ; then
		echo "
WARNING: Could not figure out how to inject a virtual host definition
         into Apache, you need to copy the etc/websvn_frontend.conf file
         manually, then edit it to adjust places that have @@
         placeholders, and finally check that Apache can work with it.

"
		rm -f -- "${CONFDIR}.d/websvn_frontend.conf"
	fi
else
	echo "
WARNING: Could not figure out how to inject a virtual host definition
         into Apache, you need to copy the etc/websvn_frontend.conf file
         manually, then edit it to adjust places that have @@
         placeholders, and finally check that Apache can work with it.

"
fi

install -p -o root -g root -m700 etc/httpd-svn.conf "$CONFDIR/httpd-svn.conf"
[ -d "$CONFDIR/repos" ] || mkdir -m700 "$CONFDIR/repos"
install -p -o root -g root -m700 etc/template.conf "$CONFDIR/repos/.template.conf"
install -p -o root -g root -m700 sbin/manage-repo-system /usr/local/sbin/manage-repo-system
install -p -o root -g root -m755 sbin/manage-repo-user /usr/local/sbin/manage-repo-user
install -p -o root -g root -m755 sbin/manage-svn /usr/local/sbin/manage-svn
install -p -o root -g root -m755 sbin/manage-svn-authz /usr/local/sbin/manage-svn-authz
install -p -o root -g root -m755 bin/svn-post-commit /usr/local/bin/svn-post-commit
install -p -o root -g root -m755 etc/httpd-svn.init /etc/init.d/httpd-svn
chkconfig --list httpd-svn >/dev/null 2>&1 || chkconfig --add httpd-svn
chkconfig httpd-svn on

# create a root account for remote control and install keys there
useradd -om -u 0 -g 0 -s /bin/bash -d /root/r_svnmgr r_svnmgr
mkdir -m700 /root/r_svnmgr/.ssh
install -p -o root -g root -m600 etc/authorized_keys /root/r_svnmgr/.ssh/authorized_keys

mkdir -p -m711 /home/clients/websites/w_websvn/public_html
chown -Rh root:root /home/clients/websites/w_websvn/public_html
install -p -o root -g root -m755 public_html/svnindex.css /home/clients/websites/w_websvn/public_html/svnindex.css
install -p -o root -g root -m755 public_html/unconfigured_http_host.html /home/clients/websites/w_websvn/public_html/unconfigured_http_host.html
install -p -o root -g root -m755 public_html/no_http_host_header.html /home/clients/websites/w_websvn/public_html/no_http_host_header.html
install -p -o root -g root -m755 public_html/invalid_http_host.html /home/clients/websites/w_websvn/public_html/invalid_http_host.html
install -p -o root -g root -m755 public_html/svnindex.xsl /home/clients/websites/w_websvn/public_html/svnindex.xsl


echo OK
