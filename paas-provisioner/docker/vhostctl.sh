#!/bin/bash
## Usage examples: 
## ./vhostctl.sh wordpress start t3st.some.domain
## ./vhostctl.sh wordpress clone t3st.some.domain

# functions
commandline_args=("$@")

# define to use sudo or not
if [ "$UID" -eq 0 ]; then
  sudo=""
else
  sudo="sudo"
fi
# define installation tool
if [ -f /usr/bin/yum ]; then
  installation_tool="yum install -y"
elif [ -f /usr/bin/apt-get ]; then
  installation_tool="apt-get install -y"
else
  echo "OS not supported. Exiting ..."
  exit 1
fi

update_nginx_config()
{
  # check for nginx installation
  if [ ! -f /usr/sbin/nginx ]; then
    ${sudo} ${installation_tool} nginx
  fi
  # get ip address of web container
  app="${commandline_args[0]}"
  operation="${commandline_args[1]}"
  if [ "$operation" == "start" ]; then
    container_name="${app}-container1"
  elif [ "$operation" == "clone" ]; then
    container_name="${app}-container2"
  fi
  container_ip_address=`docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)|grep "${container_name}"|awk -F" - " '{print $2}'`
  # create config
  domain="${commandline_args[2]}"
  cat << EOF > /tmp/${domain}.conf
server {
  listen       80;
  server_name  ${domain};
  location / {
    proxy_set_header Host ${domain};
    proxy_pass http://${container_ip_address};
  }
}
EOF
  ${sudo} mv /tmp/${domain}.conf /etc/nginx/sites-enabled/${domain}.conf
  # restart nginx instead reload to avoid error with not running instance
  ${sudo} service nginx restart
}

patch_definition_files_and_build()
{
  app="${commandline_args[0]}"
  user=`echo "${commandline_args[2]}" | awk -F'[.]' '{print $1}'`
  domain=`echo "${commandline_args[2]}" | awk -F"${user}." '{print $2}'`
  cp docker-compose.yml.orig docker-compose.yml
  if [ "$app" == "wordpress" ]; then
    sed -i "s/t3st/${user}/" docker-compose.yml
    sed -i "s/some.domain/${domain}/" docker-compose.yml
  elif [ "$app" == "drupal" ]; then
    sed -i "s/t3st/${user}/" docker-compose.yml
    sed -i "s/some.domain/${domain}/" docker-compose.yml
    sed -i "s/wordpress-v4/${app}-v7/" docker-compose.yml
    sed -i "s/wordpress/${app}/" docker-compose.yml
  fi
  /usr/local/bin/docker-compose up --build -d
  rm -f docker-compose.yml
  update_nginx_config
}


# check for Docker installation
if [ ! -f /usr/bin/docker ]; then
  ${sudo} ${installation_tool} docker
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
if [ "$1" -a "$2" == "start" -a "$3" ]; then
  cd original
  patch_definition_files_and_build
elif [ "$1" -a "$2" == "clone" -a "$3" ]; then
  cd clone
  patch_definition_files_and_build
else
  echo "Usage: $0 app_name operation domain"
  exit 1
fi

