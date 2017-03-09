#!/bin/bash

PMA_BASE="$SCRIPT_NAME"
PMA_ROOT=/home/clients/websites/w_/public_html/phpmyadmin/current

SCRIPT_NAME="$PMA_BASE$PATH_INFO"
SCRIPT_URL="$SCRIPT_NAME"
SCRIPT_URI="http://$SERVER_NAME$SCRIPT_URL"
SCRIPT_FILENAME="$PMA_ROOT/${SCRIPT_NAME##*/}"
REQUEST_URI="$SCRIPT_URL"

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
export SCRIPT_NAME SCRIPT_URL SCRIPT_URI SCRIPT_FILENAME REQUEST_URI
cd "$PMA_ROOT"
exec php-cgi "$SCRIPT_FILENAME"
