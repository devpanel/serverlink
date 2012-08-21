#!/bin/bash

ACCOUNT="${1:?Usage ${0##*/} user}"

# check input for sanity

if [ "$ACCOUNT" != "$(id -un $ACCOUNT 2>/dev/null)" ]; then
	echo 'ERROR account does not seem to be exist'
	exit 1
fi

USAGE=0
while read ARG1 ARG2 ARG3 ARG4 ARG5 ARG6 ARG7 ARG8 ARG9; do
	ARG2="${ARG2%\*}"
	if [ -z "$ARG2" -o -n "${ARG2//[[:digit:]]}" ]; then
		echo "ERROR cannot get user quota"
		exit 1
	fi

	echo -n "INFO $ARG1 $ARG2 $ARG3 $ARG4 "
	# check for blocks grace
	if [ -n "$ARG8" ] ; then
		echo "$ARG6 $ARG7 $ARG8"
	else
		echo "$ARG5 $ARG6 $ARG7"
	fi
	USAGE=$(($USAGE + $ARG2))
done <<< $(/usr/bin/quota -uvil "$ACCOUNT" 2>/dev/null | sed 1,2d)
echo "OK $USAGE"
