#!/bin/bash
## Usage examples: 
## ./vhostctl.sh wordpress start
## ./vhostctl.sh wordpress clone
## ./vhostctl.sh wordpress

# functions
commandline_args=("$@")

patch_definition_files_and_build()
{
  app="${commandline_args[0]}"
  cp docker-compose.yml.orig docker-compose.yml
  if [ "$app" == "wordpress" ]; then echo ""
    # keep as it is
  elif [ "$app" == "drupal" ]; then
    sed -i "s/wordpress-v4/${app}-v7/" docker-compose.yml
    sed -i "s/wordpress/${app}/" docker-compose.yml
  fi
  /usr/local/bin/docker-compose up --build -d
  rm -f docker-compose.yml
}


# check for Docker installation
if [ ! -f /usr/bin/docker ]; then
  if [ -f /usr/bin/yum ]; then
    if [ "$UID" -eq 0 ]; then
      yum install -y docker
    else
      sudo yum install -y docker
    fi
  elif [ -f /usr/bin/apt-get ]; then
    if [ "$UID" -eq 0 ]; then
      apt-get install -y docker
    else
      sudo apt-get install -y docker
    fi
  else
    echo "OS not supported. Exiting ..."
    exit 1
  fi
fi

# check for Docker Compose binary
if [ ! -f /usr/local/bin/docker-compose ]; then
  curl -L https://github.com/docker/compose/releases/download/1.7.1/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# check for devpanel_cache image
if [ `docker images devpanel_cache|grep -c devpanel_cache` -eq 0 ]; then
  cd cache && docker build -t devpanel_cache:v2 .
fi

# $1 for app name and $2 for operation
if [ "$1" -a "$2" == "clone" ]; then
  cd clone
  patch_definition_files_and_build
elif [ "$1" ]; then
  cd original
  patch_definition_files_and_build
# elif [ ! $# == 2 ]; then
else
  echo "Usage: $0 app_name operation"
  exit 1
fi

