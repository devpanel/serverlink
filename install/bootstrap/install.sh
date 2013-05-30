#!/bin/bash

CE_TARGET_DIR=${CE_TARGET_DIR:-"/opt/webenabled"}

usage() {
  local prog=$(basename "$0")

  echo "Usage: $prog <-u vps_uuid> <-k vps_key>"
  exit 1
}

error() {
  local msg="$1"
  local ret=$2

  echo "Error: $msg" 1>&2
  [ -n "$ret" ] && exit $ret
  exit 1
}

escape_sed() {
  local str="$1"

  str=${str//$'\n'/\\n}
  str=${str//\;/\\\;}
  str=${str//\$/\\\$}
  str=${str//\^/\\\^}
  str=${str//\*/\\\*}
  str=${str//\//\\\/}
  str=${str//\\+//\\\\+}

  echo "$str"
}

[ $# -lt 2 ] && usage

getopt_flags='u:k:A:'

unset ce_vps_uuid ce_vps_key api_url
while getopts $getopt_flags OPT; do
  case "$OPT" in
    u)
      ce_vps_uuid="$OPTARG"
      ;;
    k)
      ce_vps_key="$OPTARG"
      ;;
    A)
      api_url="$OPTARG"
      ;;
    *)
      exit 1
  esac
done
[ -n $OPTIND -a $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 ))

if [ -z "$ce_vps_uuid" ]; then
  error "the vps uuid was not provided. Please pass it with the option -u"
elif [ -z "$ce_vps_key" ]; then
  error "the vps key was not provided. Please pass it with the option -k"
elif [ -z "$api_url" ]; then
  error "the api_url was not provided. Please pass it with the option -A"
fi
api_url=$(escape_sed "$api_url")

if ! getent passwd we-taskd &>/dev/null; then
  useradd -m -c "$comment" -d "/home/we-taskd" we-taskd
  if [ $? -eq 0 ]; then
    mkdir -p "/home/we-taskd/taskd"
    chmod 2750 /home/we-taskd /home/we-taskd/taskd
  fi
fi

mkdir -p "$CE_TARGET_DIR/"backend-scripts/{lib,libexec}

[ -e "$CE_TARGET_DIR/current" ] && rm -f "$CE_TARGET_DIR/current"
ln -s backend-scripts "$CE_TARGET_DIR/current"

cp -a files/compat  "$CE_TARGET_DIR"
cp -a files/libexec  "$CE_TARGET_DIR/current"
cp -a files/lib  "$CE_TARGET_DIR/current"
cp -a files/taskd/taskd  "$CE_TARGET_DIR/current/libexec"

mkdir "$CE_TARGET_DIR/config"
mv "files/compat/taskd/config/taskd.conf" "$CE_TARGET_DIR/config"

./files/update-taskd-config -u "$ce_vps_uuid" -k "$ce_vps_key" \
  ${api_url:+ -A "$api_url"} -c "$CE_TARGET_DIR/config/taskd.conf"

chown -R 0:0 "$CE_TARGET_DIR"

export DEBIAN_FRONTEND='noninteractive'
apt-get -y install libnet-ssleay-perl libjson-xs-perl

"$CE_TARGET_DIR/current/libexec/taskd"

status=$?
if [ $status -ne 0 ]; then
  error "unable to start taskd. Returned $status"
fi 

echo "Successfully deployed taskd"
exit 0
