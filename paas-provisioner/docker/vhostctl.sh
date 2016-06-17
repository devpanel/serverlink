#!/bin/bash


# functions
show_help()
{
  echo "Usage: ./vhostctl.sh [OPTIONS]

Options:

  -A, --application               Application name. Apps supported: Wordpress, Drupal.
  -C, --operation                 Operation commands:
                                    start - to build and start containers with the application
                                    clone - to copy containers with new names and replace configuration with new URL
                                    fullclone - to setup new containers from scratch and replicate existing data
                                    backup - to save current state of existing containers
                                    restore - to restore containers to previous state
  -SD, --source-domain            Source domain name. Used for 'clone' operation.
  -DD, --destination-domain       Destination domain name. For 'clone' operation different domain name should be passed.
  -B, --backup-name               Backup name.
  -R, --restore-name              Restore previously backed up name.

Usage examples:
  ./vhostctl.sh -A=wordpress -C=start -DD=t3st.some.domain
  ./vhostctl.sh -A=wordpress -C=fullclone -SD=t3st.some.domain -DD=t4st.some.domain
  ./vhostctl.sh -A=wordpress -C=clone -SD=t3st.some.domain -DD=t4st.some.domain
  ./vhostctl.sh -C=backup  -DD=t3st.some.domain -B=t3st_backup1
  ./vhostctl.sh -C=restore -DD=t3st.some.domain -R=t3st_backup1
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
    -B=*|--backup-name=*)
    backup_name="${i#*=}"
    shift # past argument=value
    ;;
    -R=*|--restore-name=*)
    restore_name="${i#*=}"
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
    container_name="${domain}_${app}_web"
  elif [ "$operation" == "clone" ]; then
    container_name="${domain}_${app}_web"
  elif [ "$operation" == "fullclone" ]; then
    container_name="${domain}_${app}_web_clone"
  elif [ "$operation" == "restore" ]; then
    container_name=$CONTAINER_WEB_NAME
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
  sed -i "s/CONTAINER_NAME_VAR/${domain}_${app}/" docker-compose.yml
  sed -i "s/SRC_USER_VAR/${source_user}/" docker-compose.yml
  sed -i "s/SRC_DOMAIN_VAR/${source_domain_name}/" docker-compose.yml
  sed -i "s/t3st/${user}/" docker-compose.yml
  sed -i "s/some.domain/${domain_name}/" docker-compose.yml
  if [ "$app" == "drupal" ]; then
    sed -i "s/wordpress-v4/${app}-v7/" docker-compose.yml
    sed -i "s/wordpress/${app}/" docker-compose.yml
  fi
  /usr/local/bin/docker-compose up --build -d
  rm -f docker-compose.yml
  update_nginx_config
}

docker_get_ids_and_names_of_containers()
{
  CONTAINER_WEB_ID=`docker ps|grep ${domain}_${app}_web|awk '{print $1}'`
  CONTAINER_DB_ID=`docker ps|grep ${domain}_${app}_db|awk '{print $1}'`
  # useful for call from clone operation
  if [ "$operation" == "clone" ]; then
    CONTAINER_WEB_ID=`docker ps|grep ${source_domain}_${app}_web|awk '{print $1}'`
    CONTAINER_DB_ID=`docker ps|grep ${source_domain}_${app}_db|awk '{print $1}'`
  fi
  CONTAINER_WEB_NAME=`docker inspect -f '{{.Name}}' ${CONTAINER_WEB_ID}|awk -F'/' '{print $2}'`
  CONTAINER_DB_NAME=`docker inspect -f '{{.Name}}' ${CONTAINER_DB_ID}|awk -F'/' '{print $2}'`
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
elif [ "$app" -a "$operation" == "clone" -a "$source_domain" -a "$domain" ]; then
  # parse variables
  source_user=`echo "${source_domain}" | awk -F'[.]' '{print $1}'`
  source_domain_name=`echo "${source_domain}" | awk -F"${source_user}." '{print $2}'`
  user=`echo "${domain}" | awk -F'[.]' '{print $1}'`
  domain_name=`echo "${domain}" | awk -F"${user}." '{print $2}'`
  docker_get_ids_and_names_of_containers
  # save current state of containers as images
  docker commit ${CONTAINER_WEB_NAME} ${domain}_web
  docker commit ${CONTAINER_DB_NAME}  ${domain}_db
  # get ids of images
  IMAGE_WEB_NAME=`docker images|grep ${domain}_web|awk '{print $1}'`
  IMAGE_DB_NAME=`docker images|grep ${domain}_db|awk '{print $1}'`
  # let container know that it was cloned
  echo "CLONE=true" > ./clone_info
  ${sudo} cp -f ./clone_info ./original/data_volume/databases/
  # get current path and set it for mount point
  data_volume_mount_path="$(pwd)/original/data_volume"
  # start cloned containers
  docker run -v ${data_volume_mount_path}:/data    -d --name=${domain}_${app}_db  ${IMAGE_DB_NAME}
  docker run -v ${data_volume_mount_path}:/data:ro -d --name=${domain}_${app}_web ${IMAGE_WEB_NAME}
  # get destination containers ids
  CONTAINER_WEB_ID=`docker ps|grep ${user}.${domain_name}_${app}_web|awk '{print $1}'`
  CONTAINER_DB_ID=`docker ps|grep ${user}.${domain_name}_${app}_db|awk '{print $1}'`
  # get variables for db data replacement
  DB_IP=`awk -F':' '{print $1}' ./original/data_volume/databases/db_info`
  PORT=`awk -F':' '{print $2}' ./original/data_volume/databases/db_info`
  PASSWORD=`awk -F':' '{print $4}' ./original/data_volume/databases/db_info`
  USER=`awk -F':' '{print $3}' ./original/data_volume/databases/db_info`
  DOMAIN=${source_domain_name}
  DST_USER=${user}
  DST_DOMAIN=${domain_name}
  # replace db data with new URL
  if [ "$app" == "wordpress" ]; then
    # wait until mysql starts
    while [ `docker exec -it ${CONTAINER_DB_ID} netstat -ltpn|grep -c ${PORT}` -eq 0 ]; do sleep 1; done
    docker exec -it ${CONTAINER_DB_ID} mysql ${app} -h localhost -P ${PORT} -u w_${USER} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
      "UPDATE wp_options SET option_value = replace(option_value, 'http://${USER}.${DOMAIN}', 'http://${DST_USER}.${DST_DOMAIN}');"
    # check if it was replaced correctly
    if [ `docker exec -it ${CONTAINER_DB_ID} mysql ${app} -h localhost -P ${PORT} -u w_${USER} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
      "select * from wp_options;"|grep -c ${DST_USER}` -eq 2 ]; then
        echo "DB cloned correctly."
    else
        echo "Error: URL was not replaced correctly in MySQL."
        exit 1
    fi
  else
    echo "Error: Only Wordpress supported at the moment."
    exit 1
  fi
  # update container's apache2 config with new URL
  docker exec -it ${CONTAINER_WEB_ID} sed -i "s/${USER}.${DOMAIN}/${DST_USER}.${DST_DOMAIN}/" /opt/webenabled/compat/apache_include/virtwww/w_${USER}.conf
  docker exec -it ${CONTAINER_WEB_ID} sed -i "s/${USER}-gen.${DOMAIN}/${DST_USER}-gen.${DST_DOMAIN}/" /opt/webenabled/compat/apache_include/virtwww/w_${USER}.conf
  docker exec -it ${CONTAINER_WEB_ID} /bin/sh -c "echo '${DB_IP} db' >> /etc/hosts"
  if [ `docker exec -it ${CONTAINER_WEB_ID} grep db /etc/hosts|wc -l` -gt 0 -a `docker exec -it ${CONTAINER_WEB_ID} grep -c ${DST_USER} /opt/webenabled/compat/apache_include/virtwww/w_${USER}.conf|wc -l` -gt 0 ]; then
    if [ `docker exec -it ${CONTAINER_WEB_ID} grep ServerName /etc/apache2/apache2.conf|wc -l` -eq 0 ]; then
      docker exec -it ${CONTAINER_WEB_ID} /bin/sh -c "echo 'ServerName localhost' >> /etc/apache2/apache2.conf"
    fi
    docker exec -it ${CONTAINER_WEB_ID} apache2ctl graceful
    echo "WEB cloned correctly."
  else
    echo "Error: Domain in Apache configuration was not replaced correctly."
    exit 1
  fi
  # update host's nginx config with new IP of cloned web container
  update_nginx_config ${domain}_${app}_web
elif [ "$app" -a "$operation" == "fullclone" -a "$source_domain" -a "$domain" ]; then
  cd clone
  patch_definition_files_and_build
elif [ "$operation" == "backup" -a "$backup_name" -a "$domain" ]; then
  # get ids of current containers
  docker_get_ids_and_names_of_containers
  # save current state of containers as images
  docker commit ${CONTAINER_WEB_NAME} ${domain}_${backup_name}_bkp_web
  docker commit ${CONTAINER_DB_NAME}  ${domain}_${backup_name}_bkp_db
elif [ "$operation" == "restore" -a "$restore_name" -a "$domain" ]; then
  # get ids of current containers
  docker_get_ids_and_names_of_containers
  # remove source containers to avoid name conflicts
  docker rm -f ${CONTAINER_WEB_ID}
  docker rm -f ${CONTAINER_DB_ID}
  # get ids of images
  IMAGE_WEB_NAME=`docker images|grep ${domain}_${restore_name}_bkp_web|awk '{print $1}'`
  IMAGE_DB_NAME=`docker images|grep ${domain}_${restore_name}_bkp_db|awk '{print $1}'`
  # start backed up containers
  docker run -d --name=${CONTAINER_DB_NAME}  ${IMAGE_DB_NAME}
  docker run -d --name=${CONTAINER_WEB_NAME} ${IMAGE_WEB_NAME}
  # update nginx config with new IP of web container
  update_nginx_config ${CONTAINER_WEB_NAME}
else
  show_help
  exit 1
fi
