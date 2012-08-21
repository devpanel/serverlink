#!/bin/sh

function fatal()
{
	echo "${0##*/}: $*" >&2
	exit 1
}

if [ "`id -u`" = "0" ]; then
	fatal "Do not work on web content as root"
fi

if [ $# -ne 1 ]; then
	fatal "Please provide the directory name"
fi

set -ex

chmod -R u=rwX,go=rX "$1"
find "$1" -type d -print0 | xargs -0r chmod go-r --
#find "$1" -name '*.php*' -type f -print0 | xargs -0r chmod go= --
find "$1" \( -name '*.php*' -o -name '*.inc' -o -name '*.module' -o -name '*.py*' \) \
	-type f -print0 | xargs -0r chmod go= --
find "$1" -name '*.cgi' -type f -print0 | xargs -0r chmod 700 --
