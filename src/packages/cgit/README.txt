Steps to compile and package cgit into a devPanel package:

1) create a linux server where you'll compile

2) install the dependencies needed by cgit:

CentOS:
# yum -y install openssl-devel zlib-devel
# yum -y install gcc gcc-c++

# make get-git
# mkdir temp-install
# make install DESTDIR="$PWD/temp-install" 

Debian:

# apt-get update
# apt-get -y install gcc g++ make libssl-dev zlib1g-dev

Ubuntu:

# apt-get update
# apt-get -y install gcc g++ make libssl-dev zlib1g-dev

3) Download cgit source code from http://git.zx2c4.com/cgit/ and unpack it

4) Run the compile-n-pack script
