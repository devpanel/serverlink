# Introduction

This repository is a collection of scripts to be installed on Linux servers to automate the management of web applications. The servers can be linked and managed through the devPanel dashboard, or can be  standalone just like any other Linux server used for web hosting.

## Installing on a Linux server

The installation is done by executing the install script that installs the
required packages and configures a LAMP stack (Apache, MySQL, PHP). The best
is to run it on a just deployed server without prior modifications. The
supported distributions are: CentOS 7, Ubuntu 16.04 LTS and 18.04 LTS.

Download and run the install script with the following commands:

```
# curl -O https://get.devpanel.com/install.sh
# chmod 755 install.sh
# ./install.sh
```

## Installing with Vagrant

This section is optional. It applies only if you're familiar with Vagrant.
Feel free to safely skip this section if you're not sure what it means.

To add the Vagrant box to your local machine and start a first environment,
run the following commands:

```
$ vagrant box add devpanel/serverlink
$ mkdir my-devpanel-box
$ cd my-devpanel-box
$ vagrant init -m devpanel/serverlink
$ vagrant up
```

At the moment it only works with `Virtualbox` as the provider.

# Layout of the websites and apps

A single server can run multiple websites. Each site runs on a virtual host on Apache, with a dedicated linux user for running the applications and dynamic scripts. This way applications are separated from each other, and have different SFTP/SSH credentials. It's basically a LAMP stack (Apache, PHP, MySQL) with the common modules already enabled.

There are several pre-packaged apps like Drupal, Wordpress, Magento, to make it easy to quickstart the development.

# Getting Started

One of the most common operations is to install applications on a new virtual host.

To see the applications available to install, run the following command:

```
# devpanel list seed apps
```
It'll display an output similar to the one below:
```
App            	Display Name	Version
drupal-v7      	Drupal 7 	7.45
drupal-v8      	Drupal 8 	8.02
wordpress-v4   	Wordpress 4	4.44
grav-v1        	Grav CMS 	1.02

```
To install an application on a new vhost, run:
```
# devpanel install seed app --app drupal-v7 --vhost d7new
```
This will create a new virtual host named `d7new` with a Drupal 7 configured on it. It'll display the basic information about the virtual host just after creating it:
```
Information about vhost d7new

Main URL: http://d7new.abcd.app.devpanel.net/

Domains: 
    d7new.abcd.app.devpanel.net
    www.d7new.abcd.app.devpanel.net

SSL: disabled
App: drupal
SFTP User: w_d7new
SFTP Host: abcd.app.devpanel.net
MySQL Host/Port: 127.0.0.1:4000
MySQL Database:  drupal
FastCGI: disabled
Htpasswd: disabled
Snapshots: disabled

Successfully created vhost d7new

App credentials:
  URL:  http://d7new.abcd.app.devpanel.net/
  username: admin
  password: Abcdefgh123

Successfully installed drupal-v7.

```
Above you see the credentials to login on the application. The application is fully configured, it's just to access the URL and start using it.

# Command Reference

### General instruction on how to get help on command usage

All commands show it's usage and brief help text by using the `--help` argument on command line.

### Getting help on other topics

Searching for help on a specific term:

```
# devpanel help --search term
```
E.g. find commands related to `mysql`:

```
# devpanel help --search mysql
```

Getting for help on specific sections (e.g. vhost, app, server):
```
# devpanel help --section vhost
```

```
# devpanel help --section app
```


## Getting a local shell with the user of the virtual host

```
# devpanel enter --vhost d7new
```

## SSH access to the virtual host

Each virtual host created has a dedicated linux user. The access is authenticated by username and ssh key, or username and password.

### Adding SSH keys

To add a ssh key to access a virtual host (copying and pasting it from standard input), run:

```
# devpanel add ssh key --vhost d7new
```
### Setting a password to the SSH user

```
# devpanel change sftp password --vhost d7new
```

## Getting access to PHPMyAdmin

```
# devpanel get token --tool phpmyadmin --vhost d7new
```

## Reset app password

Reset the password of the admin user of the application.

```
# devpanel reset app password --vhost d7new
```

## Adding a domain to a virtual host

```
# devpanel add domain --vhost d7new --domain whatever.com
```

## Enabling Let's Encrypt SSL certificates for a virtual host

To enable Let's Encrypt SSL certificates on the virtual host, run:

```
# devpanel enable lets-encrypt --vhost d7new
```
It'll generate the Let's Encrypt certificates and setup the virtual host with it. The certificates automatically renew every 90 days.

## Create a backup for the virtual host

```
# devpanel backup vhost --vhost d7new
```

## Extract the contents of a backup file

```
# devpanel extract backup --filename a-backup-file.tgz --target-dir a-new-directory
```

## Listing existing backup files

```
# devpanel list backups --vhost d7new
```

## Checking the logs of a virtual host

```
# devpanel tail vhost logs --vhost d7new
```

## Clear app cache

```
# devpanel clear app cache --vhost d7new
```

## Set a specific PHP version to be used by a vhost

```
# devpanel set php version --version 7 --vhost d7new
```

## Set the default PHP version for the server

```
# devpanel set default php --version 7
```

## Restart MySQL

```
# devpanel restart mysql instance --vhost d7new
```

## Repair MySQL database

```
# devpanel repair mysql database --vhost d7new
```

## Configuring SSL certificates manually

```
# devpanel configure ssl --ca-file /path/to-ca-bundle.crt --cert-file /path/to/certificate.crt \
    --priv-key-file /path/to/key-file.key --vhost d7new
```

## Removing a virtual host

```
# devpanel remove vhost --vhost d7new
```

## Restoring a backup into a new virtual host

```
# devpanel create vhost --vhost d7b --from /opt/webenabled-data/vhost_archives/d7new/d7new-archive-Mar-1-2017.tgz
```

## Updating devPanel Software

```
# devpanel update
```
