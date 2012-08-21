#!/bin/bash
#<?php $args = array(getenv('SCRIPT_FILENAME')); pcntl_exec('/bin/bash', $args); ?>

PMA_BASE="$SCRIPT_NAME"
PMA_ROOT=/opt/webenabled/compat/w_/public_html/phpmyadmin/current

protocol=http
[ o"$HTTPS" = o"on" ] && protocol=https

SCRIPT_NAME="$PMA_BASE$PATH_INFO"
SCRIPT_URL="$SCRIPT_NAME"
SCRIPT_URI="$protocol://$SERVER_NAME$SCRIPT_URL"
SCRIPT_FILENAME="$PMA_ROOT/${SCRIPT_NAME##*/}"
REQUEST_URI="$SCRIPT_URL"
# dirty hack against --force-cgi-redirect
export REDIRECT_STATUS=200

# if PATH_INFO is empty, redirect
if [ -z "$PATH_INFO" ]; then
	echo "Refresh: 0; url=$SCRIPT_URI/index.php"
	echo 'Content-type: text/html'
	echo
	cat << EOF 
<html>
<head>
<title>phpMyAdmin re-direction</title>
<meta http-equiv="Refresh" content="0; url=$SCRIPT_URI/index.php" />
</head>
<body>
<h1>Redirecting ...</h1>
<p>The proper page to access phpMyAdmin is located at <a href="$SCRIPT_URI/index.php">$SCRIPT_URI/index.php</a>.</p>
</body>
EOF
exit 0
fi

unset PATH_INFO PATH_TRANSLATED
export SCRIPT_NAME SCRIPT_URL SCRIPT_URI SCRIPT_FILENAME
cd "$PMA_ROOT"
exec /opt/webenabled/config/os/pathnames/bin/php-cgi "$SCRIPT_FILENAME"
