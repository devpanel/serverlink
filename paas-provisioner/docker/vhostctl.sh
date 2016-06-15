#!/bin/bash


# functions
show_help()
{
  echo "Usage: ./vhostctl.sh [OPTIONS]

Options:

  -A, --application               Application name. Apps supported: Wordpress, Drupal.
  -C, --operation                 Operation command. 'start' or 'clone'.
  -SD, --source-domain            Source domain name. Used for 'clone' operation.
  -DD, --destination-domain       Destination domain name. For 'clone' operation different domain name should be passed.
  -M, --mode                      (in development) Mode. Can be used 'standard' to run inside EC2 or 'ecs' to be used in AWS ECS environment.

Usage examples:
  ./vhostctl.sh -A=wordpress -C=start -DD=t3st.some.domain -M=standard
  ./vhostctl.sh -A=wordpress -C=clone -SD=t3st.some.domain -DD=t4st.some.domain -M=standard
"
}

# parse option arguments
for i in "$@"
do
case $i in
    -A=*|--application=*)
    app="${i#*=}"
    shift # past argument=value
    ;;
    -C=*|--operation=*)
    operation="${i#*=}"
    shift # past argument=value
    ;;
    -SD=*|--source-domain=*)
    source_domain="${i#*=}"
    shift # past argument=value
    ;;
    -DD=*|--destination-domain=*)
    domain="${i#*=}"
    shift # past argument=value
    ;;
    -M=*|--mode=*)
    mode="${i#*=}"
    shift # past argument=value
    ;;
    *)
    show_help
            # unknown option
    ;;
esac
done


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
  if [ "$operation" == "start" ]; then
    container_name="${app}-container1"
  elif [ "$operation" == "clone" ]; then
    container_name="${app}-container2"
  fi
  container_ip_address=`docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)|grep "${container_name}"|awk -F" - " '{print $2}'`
  # create config
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
  source_user=`echo "${source_domain}" | awk -F'[.]' '{print $1}'`
  source_domain_name=`echo "${source_domain}" | awk -F"${source_user}." '{print $2}'`
  user=`echo "${domain}" | awk -F'[.]' '{print $1}'`
  domain_name=`echo "${domain}" | awk -F"${user}." '{print $2}'`
  cp -f docker-compose.yml.orig docker-compose.yml
  if [ "$app" == "wordpress" ]; then
    sed -i "s/SRC_USER_VAR/${source_user}/" docker-compose.yml
    sed -i "s/SRC_DOMAIN_VAR/${source_domain_name}/" docker-compose.yml
    sed -i "s/t3st/${user}/" docker-compose.yml
    sed -i "s/some.domain/${domain_name}/" docker-compose.yml
  elif [ "$app" == "drupal" ]; then
    sed -i "s/SRC_USER_VAR/${source_user}/" docker-compose.yml
    sed -i "s/SRC_DOMAIN_VAR/${source_domain_name}/" docker-compose.yml
    sed -i "s/t3st/${user}/" docker-compose.yml
    sed -i "s/some.domain/${domain_name}/" docker-compose.yml
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
  docker build -t devpanel_cache:v2 ./cache
fi

# main logic
if [ "$app" -a "$operation" == "start" -a "$domain" ]; then
  cd original
  patch_definition_files_and_build
elif [ "$app" -a "$operation" == "clone" -a "$domain" ]; then
  cd clone
  patch_definition_files_and_build
else
  show_help
  exit 1
fi
