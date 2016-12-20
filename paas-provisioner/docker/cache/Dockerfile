FROM ubuntu:14.04.5
EXPOSE 80

ARG USER=$USER
ARG APP=$APP
ARG SEEDAPP_ARCHIVE=$SEEDAPP_ARCHIVE
ARG DOMAIN=$DOMAIN
ARG TERM=rxvt

# get essentials
RUN apt-get update && apt-get install -y wget git unzip
# get current archive from repo
RUN git clone https://github.com/devpanel/serverlink.git /opt/serverlink
# patch serverlink's limitation for unattended setup
RUN sed -i 's/apt-get install openssh-server/apt-get install -y openssh-server/' /opt/serverlink/install/install.ubuntu.sh
RUN sed -i 's/apt-get install postfix/apt-get install -y postfix/' /opt/serverlink/install/install.ubuntu.sh
RUN sed -i 's/-y/--force-yes -y/' /opt/serverlink/install/install.ubuntu.sh
# install serverlink's environment
RUN DEBIAN_FRONTEND=noninteractive /opt/serverlink/install/install.sh -L ubuntu

# get tools for proper devPanel's scripts work
RUN apt-get install --force-yes -y quota

# get seedapps
RUN mkdir /opt/webenabled/wordpress && cd /opt/webenabled/wordpress && wget https://www.webenabled.com/seedapps/wordpress-v4.1.tgz && tar zxvf wordpress-v4.1.tgz
RUN mkdir /opt/webenabled/drupal && cd /opt/webenabled/drupal && wget https://www.webenabled.com/seedapps/drupal-v7.tgz && tar zxvf drupal-v7.tgz
