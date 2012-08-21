#!/bin/sh
dir=`dirname "$0"`/current
for file in home/clients/websites/w_/.bash_history \
            home/clients/websites/w_/.viminfo \
            opt/apache/config/conf/include/virtwww.conf.old \
            home/clients/websites/w_/public_html/cgi/phpmyadmin.orig \
            home/clients/websites/w_/.subversion \
            home/r_we/.bash_history \
            opt/webenabled/config/ssh/local \
            opt/webenabled/config/ssh/local.pub \
            opt/webenabled/config/ssh/global \
            opt/webenabled/config/ssh/global.pub
do
  rm -rf "$dir/$file"
done
rm -f "$dir/opt/apache/config/conf/ssl.crt/"*
rm -f "$dir/opt/apache/config/conf/ssl.key/"*
rm -f "$dir/home/r_we/.ssh/authorized_keys".*
find . -type f|xargs grep -l @initsoft.com|xargs sed -i 's/@initsoft.com/@initsoft.com/g'
