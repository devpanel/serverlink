#!/bin/bash
#usage(){
#echo "Usage: $0 version pathofphp"
#exit 1
#}

dir="/opt/webenabled/bin/packages/php/"
version="$1" 
phpath="$2"
##if don't have path and version call uasge 

#check if the instance is linked and if the php version directorie exist. 
if ( [[ ! -d "/opt/webenabled/bin/packages/php/"  ]] ) 	then 
	echo "link the instance with devpanel first" 
	exit 1 
	fi
if ( [[ ! -d $2   ]] ) 	then
	echo "$phpath  wrong path" 
	exit 1
	fi
##check if make is instaled

#command -v make >/dev/null 2>&1  ||{ echo "You need make to compile php " 
# exit 1 }
#preparete dirs etc
cd $phpath
#mkdir -p $dir$version/etc
#cp php.ini-production $dir$version/etc/php.ini
#touch $dir$version/bin/fcgiwrapper.sh
#echo "#! /bin/bash \nPHP_FCGI_MAX_REQUESTS=10000 \nexport PHP_FCGI_MAX_REQUESTS \nexec /opt/webenabled/bin/packages/php/$version/bin/php-cgi" > $dir$version/bin/fcgiwrapper.sh

chmod a+x $dir$version/bin/fcgiwrapper.sh
mkdir $dir$version
##configuration for php
./configure --prefix=/opt/webenabled/bin/packages/php/$version --with-config-file-path=/opt/webenabled/bin/packages/php/$version/etc --with-config-file-scan-dir=/opt/webenabled/bin/packages/php/$version/php.d --with-libdir=lib64 --with-mysq=/usr/lib64 --with-mysqli --enable-fastcgi --enable-force-cgi-redirect --enable-mbstring --disable-debug --disable-rpath --with-bz2 --with-curl --with-gettext --with-iconv --with-openssl --with-gd --with-mcrypt --with-pcre-regex --with-zlib 
# > /dev/null
#isntall with make
make -j4 > /dev/null
make install  
 # > /dev/null

mkdir -p $dir$version/etc
cp php.ini-production $dir$version/etc/php.ini
touch $dir$version/bin/fcgiwrapper.sh
echo "#! /bin/bash \nPHP_FCGI_MAX_REQUESTS=10000 \nexport PHP_FCGI_MAX_REQUESTS \nexec /opt/webenabled/bin/packages/php/$version/bin/php-cgi" > $dir$version/bin/fcgiwrapper.sh

chmod a+x $dir$version/bin/fcgiwrapper.sh

