#!/bin/bash
cleanup() {
  [ -f install.sh ] && rm -f install.sh
}

trap cleanup EXIT

# install devPanel software
curl -sS -L -O https://get.devpanel.com/install.sh || exit $?
chmod 755 install.sh
./install.sh || exit $?

# cleanup the package cache to reduce the size of the final VM
if hash apt-get &>/dev/null; then
  apt-get clean
elif hash yum &>/dev/null; then
  yum clean all
fi

exit 0
