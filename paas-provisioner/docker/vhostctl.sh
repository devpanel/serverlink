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
                                    handle - to handle parameters from front-end for devPanel's script inside docker container
  -SD, --source-domain            Source domain name. Used for 'clone' operation.
  -DD, --destination-domain       Destination domain name. For 'clone' operation different domain name should be passed.
  -B, --backup-name               Backup name.
  -R, --restore-name              Restore previously backed up name.
  -L, --build-image               Build devpanel_cache image locally instead of downloading it from docker hub.
  -RB, --remove-backups           Remove backups for requested webapp.
  -O, --options                   Script's name and parameters to process for webapp.
  -T, --type                      Type of the host. Can be docker or local.
  -RC, --read-config              Read config to determine type of the host.

Usage examples:
  ./vhostctl.sh -A=wordpress -C=start -DD=t3st.some.domain -T=local
  ./vhostctl.sh -A=wordpress -C=start -DD=t3st.some.domain -L -T=docker
  ./vhostctl.sh -C=clone -SD=t3st.some.domain -DD=t4st.some.domain
  ./vhostctl.sh -C=backup  -DD=t3st.some.domain -B=t3st_backup1
  ./vhostctl.sh -C=restore -DD=t3st.some.domain -R=t3st_backup1
  ./vhostctl.sh -C=destroy -DD=t3st.some.domain
  ./vhostctl.sh -C=destroy -DD=t3st.some.domain -RB
  ./vhostctl.sh -C=scan -DD=t3st.some.domain
  ./vhostctl.sh -C=handle -DD=t3st.some.domain -O="check-disk-quota 90"
  ./vhostctl.sh -DD=t3st.some.domain -RC
"
}

self_bin=$(readlink -e "$0")
if [ $? -ne 0 ]; then
  echo "Error: unable to detect self path" 1>&2
  exit 1
fi
self_dir=${self_bin%/*}
sys_dir=$(readlink -e "$self_dir/../..")
lib_file="$sys_dir/lib/functions"

if ! source "$lib_file"; then
  echo "Error: unable to source lib file $lib_file" 1>&2
  exit 1
fi



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
    -O*|--options*)
    handler_options="${i#*=}"
    shift # past argument=value
    ;;
    -T*|--type*)
    host_type="${i#*=}"
    shift # past argument=value
    ;;
    -RC*|--read-config*)
    read_config="${i#*=}"
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


create_local_config()
{
  # create dir if not exist
  if [ ! -d ${sys_dir}/config/apps ];then
    ${sudo} mkdir -p ${sys_dir}/config/apps
  fi
  vhost=`echo "${domain}" | awk -F'[.]' '{print $1}'`
  # if [ "$operation" == "start" ]; then vhost="${orig_domain}"; fi
  if [ "$host_type" == "docker" -o "$app_hosting" == "docker" ]; then
    # set clone state: true of false
    if [ "$operation" == "clone" ]; then
      clone_state="true"
      source_vhost="${target_vhost}"
    else
      clone_state="false"
    fi
    docker_get_ids_and_names_of_containers
    ini_contents="\
app.name           = ${vhost}
app.hosting        = docker
app.container_name = ${CONTAINER_WEB_NAME}
app.clone          = ${clone_state}
"
  else
    ini_contents="\
app.name           = ${vhost}
app.hosting        = local
app.clone          = ${clone_state}
"
  fi
  echo "$ini_contents" | ${sudo} ${sys_dir}/bin/update-ini-file -q -c ${sys_dir}/config/apps/${vhost}.ini
  store_last_vhost_variable
}

read_local_config()
{
  vhost=`echo "${domain}" | awk -F'[.]' '{print $1}'`

  # check if config exists. if not, set to local. standard script 'restore-vhost' does not create any configs by default
  if [ ! -f ${sys_dir}/config/apps/${vhost}.ini ]; then
    app_hosting="local"
  else
    app_name=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app name`
    app_hosting=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app hosting`
    app_clone=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app clone`
    if [ "$app_hosting" == "docker" ]; then
      app_container_name=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app container_name`
    fi
  fi
}

controller_handler()
# 31|list_vhost_logs||libexec/check-logs|-s %vhost%|0.0|0|2012-05-22 07:27:25|2016-02-19 20:38:03
# handler_options="libexec/check-logs -s ${vhost}"
{
  read_local_config
  read_last_vhost_variable
  handler_options=`echo ${handler_options}|sed 's/+/ /g'`
  if [ "$app_hosting" == "docker" ]; then
    docker exec ${app_container_name} ${sys_dir}/${handler_options}
  elif [ "$app_hosting" == "local" ]; then
    ${sys_dir}/${handler_options}
  fi
  # workaround. useful for some scripts without %vhost% support
  store_last_vhost_variable
}

store_last_vhost_variable()
{
  if [ "$vhost" ]; then
    echo "app.vhost = ${vhost}" | ${sudo} ${sys_dir}/bin/update-ini-file -q -c ${sys_dir}/config/apps/last_vhost_used.info
  fi
}

read_last_vhost_variable()
{
  if [ -z "$vhost" ]; then
    vhost=`ini_section_get_key_value ${sys_dir}/config/apps/last_vhost_used.info app vhost`
    # check for existing vhost at local hosting
    if [ ! -d /home/clients/websites/w_${vhost} ]; then
      # set domain to last vhost and read its config
      domain=$vhost
      read_local_config
    fi
  fi
}


update_nginx_config()
{
  # check for nginx installation
  if [ ! -f /usr/sbin/nginx ]; then
    ${sudo} ${installation_tool} nginx
  fi
  # get ip address of web container
  if [ "$operation" == "start" ]; then
    container_name="${domain}_${app}_web"
  elif [ "$operation" == "restore" ]; then
    container_name=$CONTAINER_WEB_NAME
  fi
  hostname_fqdn=`hostname -f`
  if [ "$operation" == "clone" ]; then domain="${target_vhost}.${hostname_fqdn}"; fi
  if [ "$host_type" == "docker" -o "$app_hosting" == "docker" ]; then
    if [ "$app_container_name" ]; then container_name="$app_container_name"; fi
    container_ip_address=`docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)|grep "${container_name}"|awk -F" - " '{print $2}'`
  fi
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
  restart_or_reload_nginx
}

restart_or_reload_nginx()
{
  # The hash bucket size parameter is aligned to the size that is a multiple of the processor’s cache line size.
  # This speeds up key search in a hash on modern processors by reducing the number of memory accesses.
  # If hash bucket size is equal to one processor’s cache line size then the number of memory accesses during the key search
  # will be two in the worst case — first to compute the bucket address, and second during the key search inside the bucket.
  # Therefore, if nginx emits the message requesting to increase either hash max size or hash bucket size
  # then the first parameter should first be increased.
  if [ ! -f /etc/nginx/conf.d/server_names_hash_bucket_size.conf ]; then
    ${sudo} echo "server_names_hash_bucket_size  128;" > /etc/nginx/conf.d/server_names_hash_bucket_size.conf
  fi

  if [[ `service nginx status` == " * nginx is running" ]]; then
    ${sudo} service nginx reload
  else
    ${sudo} service nginx restart
  fi
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
  if   [ "$operation" == "clone" ]; then
    CONTAINER_WEB_ID=`docker ps|grep ${source_vhost}|awk '{print $1}'`
  elif [ "$operation" == "backup" -o "$operation" == "list_backups" ]; then
    CONTAINER_WEB_ID=`docker ps|grep ${domain}|awk '{print $1}'`
  else
    CONTAINER_WEB_ID=`docker ps|grep ${domain}_${app}_web|awk '{print $1}'`
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
  docker exec ${CONTAINER_MSF_ID} /bin/sh -c "sed -i s/127.0.0.1/${dst_ip_address}/ /tmp/wmap.rc"
  docker exec ${CONTAINER_MSF_ID} /bin/sh -c "TERM=rxvt msfconsole -r /tmp/wmap.rc"
}

detect_running_apache_and_patch_configs()
{
  if [ `ps aux|grep apache2|wc -l` -gt 0 ]; then
    # patch configs with new port
    readarray -t apache_configs_array <<< `find -L /etc/apache2 -name *.conf`
    servernames_array=()
    for i in ${apache_configs_array[@]}; do
      if [ `grep ":80" ${i}|wc -l` -gt 0 -a `grep ":8080" ${i}|wc -l` -eq 0 ]; then
        sed -i 's/:80/:8080/' ${i}
      fi
      if [ `grep "  ServerName " ${i}|wc -l` -gt 0 ]; then
        servernames_array+=(`grep "  ServerName " ${i}|awk -F "  ServerName " '{print $2}'`)
      fi
    done
    # restart apache
    ${sudo} service apache2 restart
    # update nginx configs with apache's hosts
    for servername in ${servernames_array[@]}; do
      # create config
      cat << EOF > /tmp/${servername}.conf
server {
  listen       80;
  server_name  ${servername};
  location / {
    proxy_set_header Host ${servername};
    proxy_pass http://localhost:8080;
  }
}
EOF
      ${sudo} rm -f /etc/nginx/sites-enabled/${servername}.conf
      ${sudo} mv /tmp/${servername}.conf /etc/nginx/sites-enabled/${servername}.conf
    done
    restart_or_reload_nginx
  fi
}


# check for Docker installation
if [ ! -f /usr/bin/docker ]; then
  # quick install for Ubuntu only
  ${sudo} echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list
  ${sudo} apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
  ${sudo} apt-get update
  ${sudo} apt-get install -y docker-engine
fi

# check for Docker Compose binary
if [ ! -f /usr/local/bin/docker-compose ]; then
  ${sudo} curl -L https://github.com/docker/compose/releases/download/1.7.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  ${sudo} chmod +x /usr/local/bin/docker-compose
fi

# build locally or pull image from docker hub
if [ `docker images|grep devpanel_cache|grep latest|wc -l` -eq 0 ]; then
  if [ $build_image ]; then
    docker build -t devpanel_cache:latest "$self_dir/cache"
  else
    docker pull freeminder/devpanel_cache:latest && docker tag freeminder/devpanel_cache:latest devpanel_cache:latest
  fi
fi

# main logic
if [ "$app" == "zabbix" -a "$operation" == "start" -a "$domain" -a "$host_type" == "docker" ]; then
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

elif [ "$app" == "hippo" -a "$operation" == "start" -a "$domain" -a "$host_type" == "docker" ]; then
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

elif [ "$operation" == "start" -a "$domain" -a "$host_type" ]; then
  if [ "$host_type" == "docker" ]; then
    orig_domain="$domain"
    detect_running_apache_and_patch_configs
    patch_definition_files_and_build
  elif [ "$host_type" == "local" ]; then
    #
    # will be changed to parse /apps.txt in next update
    #
    if [ "$app" == "wordpress" ]; then
      app_arch="wordpress-v4.tgz"
    elif [ "$app" == "drupal" ]; then
      app_arch="drupal-v7.tgz"
    else
      echo "App not supported."
      exit 1
    fi
    # check for downloaded app
    if [ ! -f ${sys_dir}/${app}/${app_arch} ]; then
      ${sudo} mkdir -p ${sys_dir}/${app} && cd ${sys_dir}/${app} && wget https://www.webenabled.com/seedapps/${app_arch} && tar zxvf ${app_arch}
    fi
    vhost=`echo "${domain}" | awk -F'[.]' '{print $1}'`
    domain_name=`echo "${domain}" | awk -F"${vhost}." '{print $2}'`
    ${sudo} ${sys_dir}/libexec/config-vhost-names-default ${domain_name}
    ${sudo} ${sys_dir}/libexec/restore-vhost -F ${vhost} ${sys_dir}/${app}
    detect_running_apache_and_patch_configs
  else
    show_help
  fi
  create_local_config

elif [ "$operation" == "clone" -a "$source_domain" -a "$domain" ]; then
  source_vhost=${source_domain}
  target_vhost=${domain}
  domain="$source_domain"
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    # parse variables
    source_user=`echo "${source_vhost}" | awk -F'[.]' '{print $1}'`
    source_domain_name=`echo "${source_vhost}" | awk -F"${source_user}." '{print $2}'`
    user=`echo "${target_vhost}" | awk -F'[.]' '{print $1}'`
    domain_name=`echo "${target_vhost}" | awk -F"${user}." '{print $2}'`
    docker_get_ids_and_names_of_containers
    # save current state of containers as images
    docker commit ${CONTAINER_WEB_NAME} ${target_vhost}
    # get ids of images
    IMAGE_WEB_NAME=`docker images|grep ${target_vhost}|awk '{print $1}'`
    docker run -d --name=${target_vhost} ${IMAGE_WEB_NAME}
    while [ `docker ps|grep ${target_vhost}|wc -l` -eq 0 ]; do
      echo "WEB container is not running. Waiting its start."
      sleep 1
    done
    # get destination containers ids
    CONTAINER_WEB_ID=`docker ps|grep ${user}|awk '{print $1}'`

    USER=`awk -F'.' '{print $1}' <<< "$source_vhost"`
    DOMAIN=${source_domain_name}
    DST_USER=${user}
    DST_DOMAIN=${domain_name}
    # update container's apache2 config with new URL
    docker exec ${CONTAINER_WEB_ID} sed -i "s/ServerName ${USER}/ServerName ${DST_USER}/" /etc/apache2/devpanel-virtwww/w_${USER}.conf
    docker exec ${CONTAINER_WEB_ID} sed -i "s/ServerAlias www.${USER}/ServerAlias www.${DST_USER}/" /etc/apache2/devpanel-virtwww/w_${USER}.conf
    docker exec -d ${CONTAINER_WEB_ID} /bin/sh -c "/tmp/startup.sh"
    docker exec ${CONTAINER_WEB_ID} service apache2 restart

    # replace db data with new URL
    app="wordpress"
    PORT=4000
    PASSWORD=`docker exec ${CONTAINER_WEB_ID} grep w_${USER} /home/clients/websites/w_${USER}/.mysql.passwd|awk -F ":" '{print $2}'`
    docker exec ${CONTAINER_WEB_ID} mysql ${app} -h localhost -P ${PORT} -u w_${USER} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
      "UPDATE wp_options SET option_value = replace(option_value, 'http://${USER}.${DOMAIN}', 'http://${DST_USER}.${DST_DOMAIN}');"
    # check if it was replaced correctly
    if [ `docker exec ${CONTAINER_WEB_ID} mysql ${app} -h localhost -P ${PORT} -u w_${USER} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
      "select * from wp_options;"|grep -c ${DST_USER}` -eq 2 ]; then
        echo "DB cloned correctly."
    else
        echo "Error: URL was not replaced correctly in MySQL."
        exit 1
    fi

    # update host's nginx config with new IP of cloned web container
    domain="${target_vhost}"
    create_local_config
    app_clone="true"
    app_container_name="${target_vhost}"
    update_nginx_config ${target_vhost}
  elif [ "$app_hosting" == "local" ]; then
    # clone_vhost_local||libexec/clone-vhost-local|%source_vhost% %target_vhost%|
    ${sys_dir}/libexec/clone-vhost-local "$source_vhost" "$target_vhost"
    create_local_config
    update_nginx_config ${target_vhost}
  else
    show_help
    exit 1
  fi

elif [ "$operation" == "backup" -a "$backup_name" -a "$domain" ]; then
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    # get ids of current containers
    docker_get_ids_and_names_of_containers

    docker exec ${CONTAINER_WEB_ID} ${sys_dir}/libexec/archive-vhost "$vhost" "$backup_name"

    # # save current state of containers as images
    # docker commit ${CONTAINER_WEB_NAME} ${domain}_${backup_name}_bkp_web
  elif [ "$app_hosting" == "local" ]; then
    # archive_vhost||libexec/archive-vhost|%vhost% %filename%|
    ${sys_dir}/libexec/archive-vhost "$vhost" "$backup_name"
  else
    show_help
    exit 1
  fi

elif [ "$operation" == "list_backups" ]; then
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    # get ids of current containers
    docker_get_ids_and_names_of_containers
    docker exec ${CONTAINER_WEB_ID} ${sys_dir}/bin/list-backups
  elif [ "$app_hosting" == "local" ]; then
    # 88|list_backups||bin/list-backups|--|0.0|0|2013-10-07 19:23:31|2013-10-07 22:00:53
    ${sys_dir}/bin/list-backups
  else
    show_help
    exit 1
  fi

elif [ "$operation" == "restore" -a "$restore_name" -a "$domain" ]; then
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    # get ids of current containers
    docker_get_ids_and_names_of_containers
    # remove source containers to avoid name conflicts
    docker rm -f ${CONTAINER_WEB_ID}
    # get ids of images
    IMAGE_WEB_NAME=`docker images|grep ${domain}_${restore_name}_bkp_web|awk '{print $1}'`
    # start backed up containers
    docker run -d --name=${CONTAINER_WEB_NAME} ${IMAGE_WEB_NAME}
    while [ `docker ps|grep ${domain}|wc -l` -eq 0 ]; do
      echo "WEB container is not running. Waiting its start."
      sleep 1
    done
    # update nginx config with new IP of web container
    update_nginx_config ${CONTAINER_WEB_NAME}
  elif [ "$app_hosting" == "local" ]; then
    # restore_vhost||libexec/restore-vhost|%vhost% %filename%|
    ${sys_dir}/libexec/restore-vhost "$vhost" "$restore_name"
  else
    show_help
    exit 1
  fi

elif [ "$operation" == "scan" -a "$domain" -a "$host_type" == "docker" ]; then
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

elif [ "$operation" == "destroy" -a "$domain" ]; then
  read_local_config
  if [[ "$app_hosting" == "docker" ]]; then
    docker rm  -f ${app_container_name}
    if [ "$app" == "zabbix" -o "$app" == "hippo" ]; then
      docker rmi -f devpanel_${app}:v1
    elif [[ "$app_clone" == "true" ]]; then
      docker rmi -f ${app_container_name}
    else
      docker rmi -f original_${app_container_name}
    fi
    # remove backups also if requested
    if [ $remove_backups ]; then
      readarray -t backups_array <<< `docker images|grep ${domain}|awk '{print $1}'`
      for i in ${backups_array[@]}; do
        docker rmi -f ${i}
      done
    fi
  elif [[ "$app_hosting" == "local" ]]; then
    # remove_vhost||libexec/remove-vhost|%vhost% %filename%|
    ${sys_dir}/libexec/remove-vhost ${vhost}
  else
    show_help
    exit 1
  fi
  # remove config from nginx
  ${sudo} rm -f /etc/nginx/sites-enabled/${domain}*.conf
  restart_or_reload_nginx
  ${sudo} rm -f ${sys_dir}/config/apps/${domain}.ini
  ${sudo} rm -f ${sys_dir}/config/apps/${vhost}.ini

elif [ "$operation" == "handle" -a "$handler_options" ]; then
  controller_handler

elif [ "$domain" -a "$read_config" ]; then
  read_local_config
  echo "$app_hosting"

else
  show_help
  exit 1
fi
