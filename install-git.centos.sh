#!/bin/sh -e
error()
{
  echo ERROR${1+: }"$@" >&2
  trap - EXIT
  exit 1
}
trap 'error' EXIT
useradd -M -d /home/r_root -s /bin/bash -u 0 -o r_root || exit 1
ln -sn /opt/webenabled/compat/r_git /home/r_root || true
chown -R root:root /opt/webenabled/compat/r_git
chmod -R go= /opt/webenabled/compat/r_git
mkdir -p /home/r_root/.ssh
echo 'command="/home/r_root/manage-git"' `cat files/opt/webenabled/config/ssh/identity.ce-git-manage-git.pub` >/home/r_root/.ssh/authorized_keys
echo 'command="/home/r_root/manage-repo-system"' `cat files/opt/webenabled/config/ssh/identity.ce-git-manage-repo.pub` >>/home/r_root/.ssh/authorized_keys

mkdir -p /home/clients/repos

groupadd w_cgit || true
useradd -M -d /home/clients/websites/w_cgit -g virtwww -G w_cgit w_cgit
  # without the -M option, Fedora will create HOME

ln -sn /opt/webenabled/compat/w_cgit /home/clients/websites/w_cgit || true
chown -R w_cgit: /opt/webenabled/compat/w_cgit
chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/w_cgit
chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/w_cgit/public_html
chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/w_cgit/public_html/cgi-bin

ln -sn /opt/webenabled/compat/w_cgit /home/clients/websites/w_cgit || true

if ! grep -q '^PermitUserEnvironment yes' /etc/ssh/sshd_config
then
  echo 'PermitUserEnvironment yes' >>/etc/ssh/sshd_config
  /etc/init.d/sshd reload
fi
/opt/webenabled/compat/suexec/chcgi w_cgit +0

ln -ns /opt/webenabled/compat/git-scripts/bin/* /usr/local/bin || true
ln -ns /opt/webenabled/compat/git-scripts/sbin/* /usr/local/sbin || true

mkdir -p /opt/webenabled/config/os/pathnames/var/log/apache_vhosts/w_cgit
chgrp w_cgit /opt/webenabled/config/os/pathnames/var/log/apache_vhosts/w_cgit
chmod g+r /opt/webenabled/config/os/pathnames/var/log/apache_vhosts/w_cgit

cat >/opt/webenabled/config/os/pathnames/etc/apache_vhosts/w_cgit.conf <<EOF
NameVirtualHost *:80
#NameVirtualHost *:443

<VirtualHost *:80>
        ServerName git.`hostname`
        DocumentRoot /home/clients/websites/w_cgit/public_html/

        Alias /cgit.css /home/clients/websites/w_cgit/public_html/cgit.css
        Alias /cgit.png /home/clients/websites/w_cgit/public_html/cgit.png

        ScriptAliasMatch ^. /home/clients/websites/w_cgit/public_html/cgi-bin/cgit-wrapper.cgi
        <Directory /home/clients/websites/w_cgit/public_html/cgi-bin/>
            Options +ExecCGI
        </Directory>

        SuexecUserGroup w_cgit virtwww
        #SuexecUserGroup w_cgit w_cgit

        CustomLog logs/virtwww/w_cgit/access_log combined
        ErrorLog logs/virtwww/w_cgit/error_log
</VirtualHost>
EOF

apachectl configtest || error
apachectl graceful



trap - EXIT
echo 'ALL DONE (git)'
