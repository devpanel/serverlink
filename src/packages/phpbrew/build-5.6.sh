#!/bin/bash
trap_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo
    echo "Error: compilation failed!!!"
  fi
}

trap trap_exit EXIT

set -e

umask 022

cd ~

phpbrew_root="/opt/webenabled/bin/packages/phpbrew"
if [ ! -d "$phpbrew_root" ]; then
  mkdir -p "$phpbrew_root"
fi

if [ ! -d "$HOME/phpbrew" ]; then
  git clone https://github.com/phpbrew/phpbrew.git
fi

cd ~/phpbrew

if [ ! -f "$HOME/.phpbrew/composer.phar" ]; then
  curl -sS https://getcomposer.org/installer | php
fi

php composer.phar install

phpbrew_init_file="$HOME/.phpbrew/init"
if [ ! -f "$phpbrew_init_file" ]; then
  ./phpbrew init
  echo export PHPBREW_ROOT=/opt/webenabled/bin/packages/phpbrew >~/.phpbrew/init
fi

phpbrew_bashrc="$HOME/.phpbrew/bashrc"
[ -f "$phpbrew_bashrc" ] && source "$phpbrew_bashrc"

phpbrew update
phpbrew update --old

shared_modules=( bcmath bz2 calendar cgi curl fpm ftp gd gettext iconv \
  imap inifile intl hash mysql mcrypt mbstring tokenizer pdo opcache readline \
  openssl wddx xml xmlrpc xsl zip zlib zts
)

build_modules=( bcmath bz2 calendar cgi curl fpm ftp gd gettext iconv \
  imap inifile intl hash mysql mcrypt mbstring tokenizer pdo opcache readline \
  openssl wddx xml xmlrpc xsl zip zlib zts
)

phpbrew install 5.6 +default +cgi +curl +ftp +gd +gettext +iconv  \
  +imap +inifile +intl +hash +mysql +sqlite +opcache +wddx +xml +xmlrpc \
  +zip +zlib +zts \
  -- --enable-gd-natf --with-jpeg-dir=/usr \
  --with-png-dir=/usr

# strip /opt/webenabled/bin/packages/phpbrew/php/php-5.3.29/bin/php 
# strip /opt/webenabled/bin/packages/phpbrew/php/php-5.3.29/bin/php-cgi

phpbrew switch php-5.6.19

phpbrew ext install imagick

phpbrew ext install memcached -- --disable-memcached-sasl
