#!/bin/bash

DEFAULT_ACCOUNT=w_

ACCOUNT="${1:?Usage ${0##*/} user [quota_in_KB|default] [hard_quota_in_KB]}"
QUOTA="${2:-default}"
HQUOTA="$3"

declare -a FS SBLK HBLK SIND HIND GBLK GIND

while read ARG1 ARG2 ARG3 ARG4 ARG5 ARG6 ARG7 ARG8 ARG9; do
	if [ -z "$ARG2" -o -n "${ARG2//[[:digit:]]}" ]; then
		echo "ERROR cannot get user quota for '$DEFAULT_ACCOUNT'"
		exit 1
	fi

	FS[${#FS[*]}]="$ARG1"
	SBLK[${#SBLK[*]}]="$ARG3"
	HBLK[${#HBLK[*]}]="$ARG4"
	# check for blocks grace
	if [ -n "$ARG8" ] ; then
		GBLK[${#GBLK[*]}]="$ARG5"
		SIND[${#SIND[*]}]="$ARG7"
		HIND[${#HIND[*]}]="$ARG8"
		if [ -n "$ARG9" ]; then
			GIND[${#GBLK[*]}]="$ARG9"
		else
			GIND[${#GBLK[*]}]='unset'
		fi
	else
		GBLK[${#GBLK[*]}]='unset'
		SIND[${#SIND[*]}]="$ARG6"
		HIND[${#HIND[*]}]="$ARG7"
		if [ -n "$ARG8" ]; then
			GIND[${#GIND[*]}]="$ARG8"
		else
			GIND[${#GIND[*]}]='unset'
		fi
	fi
done <<< $(/usr/bin/quota -uvil "$DEFAULT_ACCOUNT" 2>/dev/null | sed 1,2d)

# check input for sanity

if [ "$ACCOUNT" != "$(id -un $ACCOUNT 2>/dev/null)" ]; then
	echo 'ERROR account does not seem to be exist'
	exit 1
fi

if [ "$QUOTA" != 'default' -a -n "${QUOTA//[[:digit]]}" -a -n "${HQUOTA//[[:digit:]]}" ]; then
	echo 'ERROR invalid quota specified'
	exit 1
fi

# ok, let's work

RESULT=
COUNT=0
if [ "$QUOTA" == 'default' ]; then
	/usr/sbin/setquota -u -p "$DEFAULT_ACCOUNT" "$ACCOUNT" -a
	RESULT=$?
	COUNT=1
else
	for ((i=0;i<${#FS[*]};i=$i+1)); do
		/usr/sbin/setquota -u "$ACCOUNT" "$QUOTA" "${HQUOTA:-${HBLK[$i]}}" "${SIND[$i]}" "${HIND[$i]}" "${FS[$i]}"
		STATUS=$?
		if [ "$STATUS" != '0' ]; then
			[ -z "$RESULT" ] && RESULT=1 || [ $RESULT -lt 1 ] && RESULT=1
		fi

		if [ "${GBLK[$i]}" != 'unset' -o "${GIND[$i]}" != 'unset' ]; then
			/usr/sbin/setquota -T -u "$ACCOUNT" "${GBLK[$i]}" "${GIND[$i]}" "${FS[$i]}"
			STATUS=$?
			if [ "$STATUS" != '0' ]; then
				[ -z "$RESULT" ] && RESULT=2 || [ $RESULT -lt 2 ] && RESULT=2
			fi
		fi
		COUNT=$(($COUNT + 1))
		RESULT="$STATUS"
	done
	
fi

if [ -z "RESULT" -o "$COUNT" == '0' ]; then
	echo 'ERROR error setting quota limits'
	exit 1
fi

if [ "$RESULT" == '0' ]; then
	echo -n "OK $ACCOUNT = $QUOTA${HQUOTA:+/$HQUOTA}"
	[ "$COUNT" != '1' ] && echo "($COUNT filesystems)" || echo
	exit 0
fi

echo "ERROR failed to set quota (error: $RESULT, fs# $COUNT)"
exit $RESULT

