FROM ubuntu:14.04.4
EXPOSE 80

ARG USER=$USER
ARG APP=$APP
ARG SEEDAPP_ARCHIVE=$SEEDAPP_ARCHIVE
ARG DOMAIN=$DOMAIN

# get essentials
RUN apt-get update && apt-get install -y wget unzip
# get current archive from repo
RUN cd /opt && wget https://github.com/devpanel/serverlink/archive/master.zip && unzip master.zip
# patch serverlink's limitation for unattended setup
RUN sed -i 's/apt-get install openssh-server/apt-get install -y openssh-server/' /opt/serverlink-master/install/install.ubuntu.sh
RUN sed -i 's/apt-get install postfix/apt-get install -y postfix/' /opt/serverlink-master/install/install.ubuntu.sh
# install serverlink's environment
RUN /opt/serverlink-master/install/install.sh -L ubuntu

# get seedapps
RUN mkdir /opt/webenabled/wordpress && cd /opt/webenabled/wordpress && wget https://www.webenabled.com/seedapps/wordpress-v4.tgz && tar zxvf wordpress-v4.tgz
RUN mkdir /opt/webenabled/drupal && cd /opt/webenabled/drupal && wget https://www.webenabled.com/seedapps/drupal-v7.tgz && tar zxvf drupal-v7.tgz
