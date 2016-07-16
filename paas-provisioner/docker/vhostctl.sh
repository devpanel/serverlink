#!/bin/bash


# functions
show_help()
{
  echo "Usage: ./vhostctl.sh [OPTIONS]

Options:

  -A, --application               Application name. Apps supported: Wordpress, Drupal, Zabbix, Hippo.
  -C, --operation                 Operation commands:
                                    start - to build and start containers with the application
                                    clone - to copy containers with new names and replace configuration with new URL
                                    backup - to save current state of existing containers
                                    restore - to restore containers to previous state
                                    destroy - to remove container(s) with webapp
                                    scan - to scan webapp for vulnerabulities
  -SD, --source-domain            Source domain name. Used for 'clone' operation.
  -DD, --destination-domain       Destination domain name. For 'clone' operation different domain name should be passed.
  -B, --backup-name               Backup name.
  -R, --restore-name              Restore previously backed up name.
  -L, --build-image               Build devpanel_cache image locally instead of downloading it from docker hub.
  -RB, --remove-backups           Remove backups for requested webapp.

Usage examples:
  ./vhostctl.sh -A=wordpress -C=start -DD=t3st.some.domain
  ./vhostctl.sh -A=wordpress -C=start -DD=t3st.some.domain -L
  ./vhostctl.sh -A=wordpress -C=clone -SD=t3st.some.domain -DD=t4st.some.domain
  ./vhostctl.sh -A=wordpress -C=backup  -DD=t3st.some.domain -B=t3st_backup1
  ./vhostctl.sh -A=wordpress -C=restore -DD=t3st.some.domain -R=t3st_backup1
  ./vhostctl.sh -A=wordpress -C=destroy -DD=t3st.some.domain
  ./vhostctl.sh -A=wordpress -C=destroy -DD=t3st.some.domain -RB
  ./vhostctl.sh -A=wordpress -C=scan -DD=t3st.some.domain
"
}

self_bin=$(readlink -e "$0")
if [ $? -ne 0 ]; then
  echo "Error: unable to detect self path" 1>&2
  exit 1
fi
self_dir=${self_bin%/*}

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
    -L*|--build-local*)
    build_image="${i#*=}"
    shift # past argument=value
    ;;
    -RB*|--remove-backups*)
    remove_backups="${i#*=}"
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
  elif [ "$operation" == "restore" ]; then
    container_name=$CONTAINER_WEB_NAME
  fi
  container_ip_address=`docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)|grep "${container_name}"|awk -F" - " '{print $2}'`
  if [ "$app" == "hippo" ]; then
    WEB_PORT=8080
  else
    WEB_PORT=80
  fi
  # create config
  cat << EOF > /tmp/${domain}.conf
server {
  listen       80;
  server_name  ${domain};
  location / {
    proxy_set_header Host ${domain};
    proxy_pass http://${container_ip_address}:${WEB_PORT};
  }
}
EOF
  ${sudo} rm -f /etc/nginx/sites-enabled/${domain}.conf
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

  local compose_file="$self_dir/original/docker-compose.yml"
  local template_file="$compose_file.orig"
  local sed_str=""

  cp -f  "$template_file" "$compose_file"

  sed_str="\
    s/SERVICE_NAME_VAR/${domain}_${app}/;
    s/CONTAINER_NAME_VAR/${domain}_${app}/;
    s/NETWORK_NAME_VAR/${domain}_${app}/;
    s/USER_VAR/${user}/;
    s/DOMAIN_VAR/${domain_name}/;
    s/SRC_USER_VAR/${source_user}/;
    s/SRC_DOMAIN_VAR/${source_domain_name}/;
    s/APP_VAR/${app}/;"

  if [ "$app" == "wordpress" ]; then
    sed_str+="s/SEEDAPP_ARCHIVE_VAR/${app}-v4.tgz/;"
  elif [ "$app" == "drupal" ]; then
    sed_str+="s/SEEDAPP_ARCHIVE_VAR/${app}-v7.tgz/;"
  fi

  sed -i "$sed_str" "$compose_file"

  /usr/local/bin/docker-compose -f "$compose_file" up --build -d
  rm -f "$compose_file"
  update_nginx_config
}

docker_get_ids_and_names_of_containers()
{
  CONTAINER_WEB_ID=`docker ps|grep ${domain}_${app}_web|awk '{print $1}'`
  # useful for call from clone operation
  if [ "$operation" == "clone" ]; then
    CONTAINER_WEB_ID=`docker ps|grep ${source_domain}_${app}_web|awk '{print $1}'`
  fi
  CONTAINER_WEB_NAME=`docker inspect -f '{{.Name}}' ${CONTAINER_WEB_ID}|awk -F'/' '{print $2}'`
}

docker_msf()
{
  if [ `docker ps|grep msf_container|wc -l` -eq 0 ]; then
    if [ `docker ps -a|grep msf_container|wc -l` -gt 0 ]; then docker rm -f msf_container; fi
    docker run -d --name=msf_container msf:v1
  fi
  CONTAINER_MSF_ID=`docker ps|grep msf_container|awk '{print $1}'`
  docker cp ${self_dir}/msf/wmap.rc ${CONTAINER_MSF_ID}:/tmp/wmap.rc
  docker exec -it ${CONTAINER_MSF_ID} /bin/sh -c "sed -i s/127.0.0.1/${dst_ip_address}/ /tmp/wmap.rc"
  docker exec -it ${CONTAINER_MSF_ID} /bin/sh -c "TERM=rxvt msfconsole -r /tmp/wmap.rc"
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

# build locally or pull image from docker hub
if [ $build_image ]; then
  docker build -t devpanel_cache:v2 "$self_dir/cache"
else
  docker pull freeminder/devpanel_cache:v2
  docker tag freeminder/devpanel_cache:v2 devpanel_cache:v2
fi

# main logic
if [ "$app" == "zabbix" -a "$operation" == "start" -a "$domain" ]; then
  if [ `docker images|grep devpanel_zabbix|wc -l` -eq 0 ]; then
    if [ $build_image ]; then
      docker build -t devpanel_zabbix:v1 ${self_dir}/zabbix
    else
      docker pull freeminder/devpanel_zabbix:v1
      docker tag freeminder/devpanel_zabbix:v1 devpanel_zabbix:v1
    fi
  fi
  docker run -d -it --name ${domain}_${app}_web devpanel_zabbix:v1
  update_nginx_config
elif [ "$app" == "hippo" -a "$operation" == "start" -a "$domain" ]; then
  if [ `docker images|grep devpanel_hippo|wc -l` -eq 0 ]; then
    if [ $build_image ]; then
      docker build -t devpanel_hippo:v1 ${self_dir}/hippo
    else
      docker pull freeminder/devpanel_hippo:v1
      docker tag freeminder/devpanel_hippo:v1 devpanel_hippo:v1
    fi
  fi
  docker run -d -it --name ${domain}_${app}_web devpanel_hippo:v1
  update_nginx_config
elif [ "$app" -a "$operation" == "start" -a "$domain" ]; then
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
  # get ids of images
  IMAGE_WEB_NAME=`docker images|grep ${domain}_web|awk '{print $1}'`
  docker run -d --name=${domain}_${app}_web ${IMAGE_WEB_NAME}
  while [ `docker ps|grep ${domain}_${app}_web|wc -l` -eq 0 ]; do
    echo "WEB container is not running. Waiting its start."
    sleep 1
  done
  # get destination containers ids
  CONTAINER_WEB_ID=`docker ps|grep ${user}.${domain_name}_${app}_web|awk '{print $1}'`
  # update container's apache2 config with new URL
  USER=`awk -F'.' '{print $1}' <<< "$source_domain"`
  DOMAIN=${source_domain_name}
  DST_USER=${user}
  DST_DOMAIN=${domain_name}
  docker exec -it ${CONTAINER_WEB_ID} sed -i "s/${USER}.${DOMAIN}/${DST_USER}.${DST_DOMAIN}/" /opt/webenabled/compat/apache_include/virtwww/w_${USER}.conf
  docker exec -it ${CONTAINER_WEB_ID} sed -i "s/${USER}-gen.${DOMAIN}/${DST_USER}-gen.${DST_DOMAIN}/" /opt/webenabled/compat/apache_include/virtwww/w_${USER}.conf
  docker exec -it ${CONTAINER_WEB_ID} service apache2 reload
  # update host's nginx config with new IP of cloned web container
  update_nginx_config ${domain}_${app}_web
elif [ "$operation" == "backup" -a "$backup_name" -a "$domain" ]; then
  # get ids of current containers
  docker_get_ids_and_names_of_containers
  # save current state of containers as images
  docker commit ${CONTAINER_WEB_NAME} ${domain}_${backup_name}_bkp_web
elif [ "$operation" == "restore" -a "$restore_name" -a "$domain" ]; then
  # get ids of current containers
  docker_get_ids_and_names_of_containers
  # remove source containers to avoid name conflicts
  docker rm -f ${CONTAINER_WEB_ID}
  # get ids of images
  IMAGE_WEB_NAME=`docker images|grep ${domain}_${restore_name}_bkp_web|awk '{print $1}'`
  # start backed up containers
  docker run -d --name=${CONTAINER_WEB_NAME} ${IMAGE_WEB_NAME}
  while [ `docker ps|grep ${domain}_${app}_web|wc -l` -eq 0 ]; do
    echo "WEB container is not running. Waiting its start."
    sleep 1
  done
  # update nginx config with new IP of web container
  update_nginx_config ${CONTAINER_WEB_NAME}
elif [ "$operation" == "scan" -a "$app" -a "$domain" ]; then
  # get ids of current containers
  docker_get_ids_and_names_of_containers
  # get ip_address of webapp
  dst_ip_address=`docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)|grep "${CONTAINER_WEB_NAME}"|awk -F" - " '{print $2}'`
  # check if msf container exists
  if [ `docker images|grep msf|wc -l` -eq 0 ]; then
    if [ $build_image ]; then
      docker build -t msf:v1 ${self_dir}/msf
    else
      docker pull freeminder/msf:v1
      docker tag freeminder/msf:v1 msf:v1
    fi
  fi
  # do the scan
  docker_msf
elif [ "$operation" == "destroy" -a "$app" -a "$domain" ]; then
  docker rm  -f ${domain}_${app}_web
  if [ "$app" == "zabbix" -o "$app" == "hippo" ]; then
    docker rmi -f devpanel_${app}:v1
  else
    docker rmi -f original_${domain}_${app}_web
  fi
  # remove backups also if requested
  if [ $remove_backups ]; then
    readarray -t backups_array <<< `docker images|grep ${domain}|awk '{print $1}'`
    for i in "${backups_array[@]}"; do
      docker rmi -f ${i}
    done
  fi
  # remove config from nginx
  ${sudo} rm -f /etc/nginx/sites-enabled/${domain}.conf
  ${sudo} service nginx reload
else
  show_help
  exit 1
fi
