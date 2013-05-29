#!/bin/bash

BOUNDARY="${1:?Usage: ${0##*/} percent_of_allowed_usage}"

if [ -n "${BOUNDARY//[[:digit:]]}" ]; then
	echo "ERROR invalid input, expected a number"
	exit 1
fi

MIN_UID=$(id -u w_)
MIN_UID="${MIN_UID:-500}"

/usr/sbin/repquota -aciu | sed '1,5d; /^[[:space:]]*$/d' | awk '{ print $1" "$3" "$4" "$5 }' | \
while read ACCOUNT USAGE SOFT_LIMIT HARD_LIMIT ; do
	[ "${ACCOUNT:0:1}" == '#' ] && continue
	[ $USAGE -ge $((($SOFT_LIMIT / 100) * $BOUNDARY)) -a $(id -u $ACCOUNT) -ge $MIN_UID ] && echo "$ACCOUNT:$USAGE $SOFT_LIMIT $HARD_LIMIT"
done
exit 0
