#!/bin/bash


# functions
show_help()
{
  echo "Usage: ./vhostctl.sh [OPTIONS]

Options:

  -A, --application               Application name. Apps supported: Wordpress, Drupal, Zabbix, Hippo.
  -C, --operation                 Operation commands:
                                    start - to build and/or start container with the application
                                    status - to show status of container with the application
                                    stop - to stop container with the application
                                    clone - to copy container with new names and replace configuration with new URL
                                    backup - to save current state of existing container
                                    restore - to restore container to previous state
                                    destroy - to remove container with webapp
                                    convert - to convert the application from local to docker
                                    scan - to scan webapp for vulnerabulities
                                    pentest - to do a penetration testing of devPanel UIV2
                                    handle - to handle parameters from front-end for devPanel's script inside docker container
  -DB, --database-type            Type of database. Can be 'mysql' or 'rds'.
  -AWS_ACCESS_KEY_ID              AWS ACCESS KEY ID.
  -AWS_SECRET_ACCESS_KEY          AWS SECRET ACCESS KEY.
  -AWS_DEFAULT_REGION             AWS DEFAULT REGION.
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
  ./vhostctl.sh -A=wordpress -C=start -DB=mysql -DD=t3st.some.domain -L -T=docker
  ./vhostctl.sh -A=wordpress -C=start -DB=rds -AWS_ACCESS_KEY_ID=some+key+id -AWS_SECRET_ACCESS_KEY=some+access+key -AWS_DEFAULT_REGION=us-east-1 -DD=t3st.some.domain -T=docker
  ./vhostctl.sh -C=start -DD=t3st.some.domain
  ./vhostctl.sh -C=status -DD=t3st.some.domain
  ./vhostctl.sh -C=stop -DD=t3st.some.domain
  ./vhostctl.sh -C=clone -SD=t3st.some.domain -DD=t4st.some.domain
  ./vhostctl.sh -C=backup  -DD=t3st.some.domain -B=t3st_backup1
  ./vhostctl.sh -C=restore -DD=t3st.some.domain -R=t3st_backup1
  ./vhostctl.sh -C=destroy -DD=t3st.some.domain
  ./vhostctl.sh -C=destroy -DD=t3st.some.domain -RB
  ./vhostctl.sh -C=convert
  ./vhostctl.sh -C=scan -DD=t3st.some.domain
  ./vhostctl.sh -C=pentest
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
    -DB=*|--database-type=*)
    db_type="${i#*=}"
    shift # past argument=value
    ;;
    -AWS_ACCESS_KEY_ID=*)
    aws_access_key_id="${i#*=}"
    shift # past argument=value
    ;;
    -AWS_SECRET_ACCESS_KEY=*)
    aws_secret_access_key="${i#*=}"
    shift # past argument=value
    ;;
    -AWS_DEFAULT_REGION=*)
    aws_default_region="${i#*=}"
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
    # show_help
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

# definitions
## workaround for AWS
if [ `ip ad sh|grep -c ' eth'` -gt '0' ]; then
  vps_ip=`ip ad sh|grep ' eth'|tail -1|awk '{print $2}'|awk -F'/' '{print $1}'`
else
  vps_ip=`ip ad sh|grep ' ens'|tail -1|awk '{print $2}'|awk -F'/' '{print $1}'`
fi
hostname_fqdn=`hostname -f`


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
    elif [ "${app_clone}" == "true" ]; then
      clone_state="true"
    else
      clone_state="false"
    fi
    docker_get_ids_and_names_of_containers
    ini_contents="\
app.name                  = ${vhost}
app.hosting               = docker
app.db_type               = ${db_type}
app.container_name        = ${CONTAINER_WEB_NAME}
app.clone                 = ${clone_state}
aws.access_key_id         = ${aws_access_key_id}
aws.secret_access_key     = ${aws_secret_access_key}
aws.default_region        = ${aws_default_region}
rds.endpoint_address      = ${rds_endpoint_address}
rds.endpoint_port         = ${rds_endpoint_port}
rds.vpcsecuritygroupid    = ${rds_vpcsecuritygroupid}
"
  else
    ini_contents="\
app.name           = ${vhost}
app.hosting        = local
app.clone          = ${clone_state}
"
  fi
  echo "$ini_contents" | ${sudo} ${sys_dir}/bin/update-ini-file -q -c ${sys_dir}/config/apps/${vhost}.ini
}

read_local_config()
{
  vhost=`echo "${domain}" | awk -F'[.]' '{print $1}'`
  root_domain=`echo "${domain}" | awk -F'[.]' '{print $2}'`

  # check if config exists. if not, set to local. standard script 'restore-vhost' does not create any configs by default
  if [ ! -f ${sys_dir}/config/apps/${vhost}.ini ]; then
    app_hosting="local"
  else
    app_name=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app name`
    app_hosting=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app hosting`
    app_clone=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app clone`
    if [ "$app_hosting" == "docker" ]; then
      app_container_name=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app container_name`
      app_db_type=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini app db_type`
      aws_access_key_id=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini aws access_key_id`
      aws_secret_access_key=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini aws secret_access_key`
      aws_default_region=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini aws default_region`
      rds_endpoint_address=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini rds endpoint_address`
      rds_endpoint_port=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini rds endpoint_port`
      rds_vpcsecuritygroupid=`ini_section_get_key_value ${sys_dir}/config/apps/${vhost}.ini rds vpcsecuritygroupid`
    fi
  fi
}

controller_handler()
# example in db@controller
# 31|list_vhost_logs||libexec/check-logs|-s %vhost%|0.0|0|2012-05-22 07:27:25|2016-02-19 20:38:03
# becomes ('##' used as a whitespace)
# 31|list_vhost_logs||paas-provisioner/docker/vhostctl.sh|-C=handle -O=libexec/check-logs##-s##%vhost% -DD=%vhost%|0.0|0|2012-05-22 07:27:25|2016-02-19 20:38:03
# and vhostctl receives (after sed processed '##')
# handler_options="libexec/check-logs -s some_vhost"
{
  read_local_config
  handler_options=`echo ${handler_options}|sed 's/##/ /g'`
  case "$handler_options" in
    libexec/check-logs*-f*)
      vhost=`echo ${handler_options}|awk -F'/var/log/apache2/virtwww/' '{print $2}'|awk -F'/' '{print $1}'|awk -F'w_' '{print $2}'`
      for dc in $(docker ps|grep -v 'NAMES'|awk '{print $NF}'); do
        if [ "$vhost" == $(echo $dc|awk -F'.' '{print $1}') ]; then 
          app_hosting="docker"
          app_container_name=${dc}
        fi
      done
      if [ "$app_hosting" == "docker" ]; then
        docker exec -i ${app_container_name} ${sys_dir}/${handler_options}
      elif [ "$app_hosting" == "local" ]; then
        ${sys_dir}/${handler_options}
      fi
    ;;

    bin/restore-vhost-subsystem*|bin/list-backups*)
      if [ "$app_hosting" == "docker" ]; then
        docker exec -i ${app_container_name} su - w_${vhost} -c "${sys_dir}/${handler_options}"
      elif [ "$app_hosting" == "local" ]; then
        su - w_${vhost} -c "${sys_dir}/${handler_options}"
      fi
    ;;

    libexec/restore-vhost*http://www.webenabled.com/seedapps/*)
      ${sys_dir}/${handler_options}
    ;;

    libexec/restore-vhost*)
      new_vhost_name=`echo ${handler_options}|awk '{print $2}'`
      old_vhost_name=`echo ${handler_options}|awk -F'/opt/webenabled-data/vhost_archives/' '{print $2}'|awk -F'/' '{print $1}'`
      vhost="${old_vhost_name}.${hostname_fqdn}"

      if [ `docker ps|grep ${vhost}|wc -l` -gt 0 ]; then
        app_hosting="docker"
      fi

      if [ "$app_hosting" == "docker" ]; then
        # create and run a new container
        CONTAINER_WEB_ID=`docker ps|grep ${vhost}|awk '{print $1}'`
        app_container_name="${new_vhost_name}.${hostname_fqdn}"
        docker commit ${CONTAINER_WEB_ID} ${app_container_name}
        docker run -d --name=${app_container_name} ${app_container_name}
        docker exec -i ${app_container_name} ${sys_dir}/${handler_options}

        ini_contents="\
app.name              = ${new_vhost_name}
app.hosting           = docker
app.db_type           = ${app_db_type}
aws.access_key_id     = ${aws_access_key_id}
aws.secret_access_key = ${aws_secret_access_key}
aws.default_region    = ${aws_default_region}
app.container_name    = ${app_container_name}
app.clone             = true
"
        echo "$ini_contents" | ${sudo} ${sys_dir}/bin/update-ini-file -q -c ${sys_dir}/config/apps/${new_vhost_name}.ini

        # create nginx config
        domain="${app_container_name}"
        update_nginx_config

      elif [ "$app_hosting" == "local" ]; then
        ini_contents="\
app.name           = ${new_vhost_name}
app.hosting        = local
app.clone          = true
"
        echo "$ini_contents" | ${sudo} ${sys_dir}/bin/update-ini-file -q -c ${sys_dir}/config/apps/${new_vhost_name}.ini
        ${sys_dir}/${handler_options}
      fi
    ;;

    libexec/config-vhost-names*+*)
      if [ "$app_hosting" == "docker" ]; then
        docker exec -i ${app_container_name} ${sys_dir}/${handler_options}
      elif [ "$app_hosting" == "local" ]; then
        ${sys_dir}/${handler_options}
      fi
      add_domain_to_nginx_config="true"
    ;;

    libexec/config-vhost-names*-*)
      if [ "$app_hosting" == "docker" ]; then
        docker exec -i ${app_container_name} ${sys_dir}/${handler_options}
      elif [ "$app_hosting" == "local" ]; then
        ${sys_dir}/${handler_options}
      fi
      remove_domain_from_nginx_config="true"
    ;;

    *)
      if [ "$app_hosting" == "docker" ]; then
        docker exec -i ${app_container_name} ${sys_dir}/${handler_options}
      elif [ "$app_hosting" == "local" ]; then
        ${sys_dir}/${handler_options}
      fi
    ;;
  esac

  update_nginx_config
  detect_running_apache_and_patch_configs
}

create_nginx_config()
{
cat << EOF > /tmp/"${servername}".conf
server {
  listen       80;
  server_name  ${servername}${serveraliases};
  location / {
    proxy_set_header Host \$host;
    proxy_pass http://localhost:8080;
  }
}
EOF

${sudo} rm -f /etc/nginx/sites-enabled/${servername}.conf
${sudo} mv /tmp/${servername}.conf /etc/nginx/sites-enabled/${servername}.conf
}

update_nginx_config()
{
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
  if [ "${app_hosting}" == "local" ]; then
    container_ip_address="localhost"
    WEB_PORT=8080
  fi

  # create config for domain
  cat << EOF > /tmp/${domain}.conf
server {
  listen       80;
  server_name  ${domain};
  location / {
    proxy_set_header Host \$host;
    proxy_pass http://${container_ip_address}:${WEB_PORT};
  }
}
EOF
  # create config for subdomain
  domain_fp=`echo "${domain}"|awk -F'[.]' '{print $1}'`
  domain_lp=`echo "${domain}"|awk -F"${domain_fp}." '{print $2}'`
  subdomain="${domain_fp}-gen.${domain_lp}"
  cat << EOF > /tmp/${subdomain}.conf
server {
  listen       80;
  server_name  ${subdomain};
  location / {
    proxy_set_header Host \$host;
    proxy_pass http://${container_ip_address}:${WEB_PORT};
  }
}
EOF

  # handle additional domain
  additional_domain=`echo ${handler_options}|awk '{print $NF}'`
  if [ "${add_domain_to_nginx_config}" == "true" ]; then
    cat << EOF > /tmp/${additional_domain}.conf
server {
  listen       80;
  server_name  ${additional_domain};
  location / {
    proxy_set_header Host \$host;
    proxy_pass http://${container_ip_address}:${WEB_PORT};
  }
}
EOF
    ${sudo} mv /tmp/${additional_domain}.conf /etc/nginx/sites-enabled/${additional_domain}.conf
  elif [ "${remove_domain_from_nginx_config}" == "true" ]; then
    ${sudo} rm -f /etc/nginx/sites-enabled/${additional_domain}.conf
  fi

  # apply configs
  ${sudo} rm -f /etc/nginx/sites-enabled/${domain}.conf /etc/nginx/sites-enabled/${subdomain}.conf
  ${sudo} mv /tmp/${domain}.conf /etc/nginx/sites-enabled/${domain}.conf
  ${sudo} mv /tmp/${subdomain}.conf /etc/nginx/sites-enabled/${subdomain}.conf
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
  if [ ! -f /etc/nginx/conf.d/server_names_hash_bucket_size.conf -o ! -f /etc/nginx/conf.d/client_max_body_size.conf ]; then
    ${sudo} echo "server_names_hash_bucket_size  128;" > /etc/nginx/conf.d/server_names_hash_bucket_size.conf
    ${sudo} echo "client_max_body_size 200M;" > /etc/nginx/conf.d/client_max_body_size.conf
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
  elif [ "$operation" == "backup" -o "$operation" == "list_backups" -o "$operation" == "status" -o "$operation" == "stop" -o "$operation" == "scan" -o "$operation" == "convert" ]; then
    CONTAINER_WEB_ID=`docker ps|grep ${domain}|awk '{print $1}'`
  else
    CONTAINER_WEB_ID=`docker ps|grep ${domain}_${app}_web|awk '{print $1}'`
  fi
  if [ ${CONTAINER_WEB_ID} ]; then CONTAINER_WEB_NAME=`docker inspect -f '{{.Name}}' ${CONTAINER_WEB_ID}|awk -F'/' '{print $2}'`; fi
}

docker_msf()
{
  if [ -z "$1" ]; then
    read_local_config
    # get ids of current containers
    docker_get_ids_and_names_of_containers
    # get ip_address of webapp
    dst_ip_address=`docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)|grep "${CONTAINER_WEB_NAME}"|awk -F" - " '{print $2}'`
  else
    dst_ip_address=`host -t a uiv2.devpanel.com|tail -1|awk '{print $NF}'`
  fi
  # check if MSF container exists
  docker_build_or_pull_and_tag msf
  # run MSF container
  docker run -d --name=msf_container devpanel_msf:latest
  # do the scan
  CONTAINER_MSF_ID=`docker ps|grep msf_container|awk '{print $1}'`
  docker cp ${self_dir}/msf/wmap.rc ${CONTAINER_MSF_ID}:/tmp/wmap.rc
  docker exec ${CONTAINER_MSF_ID} /bin/sh -c "sed -i s/127.0.0.1/${dst_ip_address}/ /tmp/wmap.rc"
  docker exec ${CONTAINER_MSF_ID} /bin/sh -c "TERM=rxvt msfconsole -r /tmp/wmap.rc"
}

docker_build_or_pull_and_tag()
{
  if [ `docker images|grep devpanel_${1}|wc -l` -eq 0 ]; then
    if [ $build_image ]; then
      docker build -t devpanel_${1}:latest ${self_dir}/${1}
    else
      # avoid error 500 from docker hub
      while [ ! "${exit_status}" == "0" ]; do
        docker pull devpanel/${1}:latest
        exit_status=`echo $?`
      done
      docker tag devpanel/${1}:latest devpanel_${1}:latest
    fi
  fi
}

detect_running_apache_and_patch_configs()
{
  if [ `ps aux|grep apache2|wc -l` -gt 0 ]; then
    readarray -t apache_configs_array <<< `find -L /etc/apache2/devpanel-virtwww -name '*.conf'`
    for i in ${apache_configs_array[@]}; do
      # patch configs with new port
      if [ `grep ":80" ${i}|wc -l` -gt 0 -a `grep ":8080" ${i}|wc -l` -eq 0 ]; then
        sed -i 's/:80/:8080/' ${i}
      fi
      if [ `grep "  ServerName " ${i}|wc -l` -gt 0 ]; then
        # create config for main and additional domains
        servername=`grep "  ServerName " ${i}|grep -v -- -gen|awk -F "  ServerName " '{print $2}'|tr -d '\r\n'`
        serveraliases=`grep "  ServerAlias " ${i}|awk -F "  ServerAlias" '{print $2}'`
        create_nginx_config
        # create config for -gen domain (mysqladmin and filexplorer)
        servername=`grep "  ServerName " ${i}|grep -- -gen|awk -F "  ServerName " '{print $2}'|tr -d '\r\n'`
        serveraliases=''
        create_nginx_config
      fi
    done
    sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf
    # restart apache
    ${sudo} service apache2 restart
    # update nginx configs with apache's hosts
    restart_or_reload_nginx
  fi
}

pentest()
{
  if [ -z "$domain" ]; then domain=uiv2.devpanel.com; fi
  docker_msf ${domain}
}

convert()
{
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    docker_get_ids_and_names_of_containers
    # code
    # ...
  else
    # create docker container with app
    # ...
    # ${docker_container_name}=`docker ps|grep `
    app_name=`echo $domain|awk -F'.' '{print $1}'`
    app_path=/home/clients/websites/w_${app_name}
    # archive local app
    tar zcf /tmp/${app_name}.tgz ${app_path}
    # copy app to docker container
    docker cp /tmp/${app_name}.tgz ${docker_container_name}:/tmp/
    # extract
    docker exec -it ${docker_container_name} tar /tmp/${app_name}.tgz -C /home/clients/websites/
    # get db creds
    db_username=w_`docker exec -it ${docker_container_name} /bin/sh -c "tail -1 /home/clients/websites/w_${vhost}/.mysql.passwd | awk -F':' '{print $1}'"`
    db_password=`docker exec -it ${docker_container_name} /bin/sh -c "tail -1 /home/clients/websites/w_${vhost}/.mysql.passwd | awk -F':' '{print $2}'"`
    # patch db with new URL
    docker exec -it ${docker_container_name} mysql -u ${db_username} -p${db_password} -S /home/clients/databases/b_${vhost}/mysql/mysql.sock -D wordpress -e "update wp_options set option_value='http://${vhost}.${hostname_fqdn}/' where option_name='siteurl'"
    docker exec -it ${docker_container_name} mysql -u ${db_username} -p${db_password} -S /home/clients/databases/b_${vhost}/mysql/mysql.sock -D wordpress -e "update wp_options set option_value='http://${vhost}.${hostname_fqdn}/' where option_name='home'"
  fi

}

update_scripts()
{
  cd /tmp && \
  wget https://github.com/devpanel/serverlink/archive/master.zip && \
  unzip master.zip && \
  for c in $(docker ps|grep -v 'NAMES'|awk '{print $NF}'); do
    for i in bin  compat  install  lib  libexec  LICENSE.txt  paas-provisioner  README.md  sbin  src; do
      docker cp serverlink-master/$i $c:/opt/webenabled/
    done
  done
}


# check for Docker installation
if [ ! -f /usr/bin/docker ]; then
  # quick install for Ubuntu LTS 14.04 and 16.04 only
  if   [ `lsb_release -c|grep -c xenial` -eq 1 ]; then
    ${sudo} echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > /etc/apt/sources.list.d/docker.list
  elif [ `lsb_release -c|grep -c trusty` -eq 1 ]; then
    ${sudo} echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list
  else
    echo "Unsupported Ubuntu release."
    exit 1
  fi
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
docker_build_or_pull_and_tag cache

# check for nginx installation
if [ ! -f /usr/sbin/nginx ]; then
  ${sudo} ${installation_tool} nginx
fi

# check for AWS CLI installation
if [ ! -f /usr/bin/aws ]; then
  ${sudo} ${installation_tool} awscli
fi

# check for jq installation
if [ ! -f /usr/bin/jq ]; then
  ${sudo} ${installation_tool} jq
fi


# main logic
if [ "$app" == "zabbix" -a "$operation" == "start" -a "$domain" -a "$host_type" == "docker" ]; then
  docker_build_or_pull_and_tag zabbix
  docker run -d -it --name ${domain}_${app}_web devpanel_zabbix:latest
  update_nginx_config

elif [ "$app" == "hippo" -a "$operation" == "start" -a "$domain" -a "$host_type" == "docker" ]; then
  docker_build_or_pull_and_tag hippo
  docker run -d -it --name ${domain}_${app}_web devpanel_hippo:latest
  update_nginx_config

# create app
elif [ "$operation" == "start" -a "$domain" -a "$host_type" ]; then
  if [ "$host_type" == "docker" ]; then
    vhost=`echo "${domain}" | awk -F'[.]' '{print $1}'`
    orig_domain="$domain"
    detect_running_apache_and_patch_configs
    patch_definition_files_and_build
    # RDS
    if [ "$db_type" == "rds" ]; then
      export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
      export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
      export AWS_DEFAULT_REGION="${aws_default_region}"
      docker_get_ids_and_names_of_containers
      DB_USER=w_${vhost}
      DB_PASSWORD=`docker exec ${CONTAINER_WEB_ID} tail -1 /home/clients/websites/w_${vhost}/.mysql.passwd|awk -F':' '{print $2}'`
      # dump db
      while [ ! `docker exec ${CONTAINER_WEB_ID} /bin/sh -c "mysql -S /home/clients/databases/b_${vhost}/mysql/mysql.sock -h localhost -P 4000 --password=${DB_PASSWORD} -u ${DB_USER} ${app} -e 'print;'|grep print|wc -l"` -eq 1 ]; do sleep 1; done
      docker exec ${CONTAINER_WEB_ID} /bin/sh -c "mysqldump -S /home/clients/databases/b_${vhost}/mysql/mysql.sock -h localhost -P 4000 --password=${DB_PASSWORD} -u ${DB_USER} ${app} > /tmp/${app}.sql"
      # # create rds instance
      aws rds create-db-instance --db-instance-identifier ${vhost} --allocated-storage 5 --db-instance-class db.t1.micro --engine mysql --master-username ${DB_USER} --master-user-password ${DB_PASSWORD}
      while [ ! `aws rds describe-db-instances --db-instance-identifier ${vhost}|jq '.DBInstances[0].DBInstanceStatus'|tr -d '"'` == "available" ]; do
        echo "Waiting for RDS instance to be ready. Current status is: "
        aws rds describe-db-instances --db-instance-identifier ${vhost}|jq '.DBInstances[0].DBInstanceStatus'|tr -d '"'
        sleep 5
      done
      # get rds endpoint
      rds_endpoint_address=`aws rds describe-db-instances --db-instance-identifier ${vhost}|jq '.DBInstances[0].Endpoint.Address'|tr -d '"'`
      rds_endpoint_port=`aws rds describe-db-instances --db-instance-identifier ${vhost}|jq '.DBInstances[0].Endpoint.Port'|tr -d '"'`
      # get VpcSecurityGroupId
      rds_vpcsecuritygroupid=`aws rds describe-db-instances --db-instance-identifier ${vhost}|jq '.DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId'|tr -d '"'`
      # add VpcSecurityGroup rule to allow access from current VPS to RDS
      aws ec2 authorize-security-group-ingress --group-id ${rds_vpcsecuritygroupid} --protocol tcp --port ${rds_endpoint_port} --cidr ${vps_ip}/32
      # write db endpoint into webapp's config
      if [ "${app}" == "wordpress" ]; then
        docker exec ${CONTAINER_WEB_ID} sed -i "s/127.0.0.1:4000/${rds_endpoint_address}:${rds_endpoint_port}/" /home/clients/websites/w_${vhost}/public_html/${vhost}/wp-config.php
      elif [ "${app}" == "drupal" ]; then
        docker exec ${CONTAINER_WEB_ID} sed -i "s/${rds_endpoint_address}/db/" /home/clients/websites/w_${vhost}/public_html/${vhost}/sites/default/settings.php
      fi
      # restore db dump to rds
      docker exec ${CONTAINER_WEB_ID} mysql -h ${rds_endpoint_address} -P ${rds_endpoint_port} -S /tmp/mysql.sock -u ${DB_USER} --password=${DB_PASSWORD} -e "CREATE DATABASE ${app};"
      docker exec ${CONTAINER_WEB_ID} /bin/sh -c "mysql -h ${rds_endpoint_address} -P ${rds_endpoint_port} -S /tmp/mysql.sock -u ${DB_USER} --password=${DB_PASSWORD} ${app} < /tmp/${app}.sql"
      docker exec ${CONTAINER_WEB_ID} rm -f /tmp/${app}.sql /tmp/mysql.sock
      docker exec ${CONTAINER_WEB_ID} killall mysqld
    fi
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

# start app's container
elif [ "$operation" == "start" -a "$domain" ]; then
  read_local_config
  if [ "${app_hosting}" == "docker" ]; then
    if [ `docker inspect -f '{{.State.Status}}' ${app_container_name}` == "exited" ]; then
      docker start ${app_container_name}
      update_nginx_config
    else
      echo "container already started"
      # exit 1
    fi
  else
    echo "Can't start a local app. Should be a docker container."
    exit 1
  fi

elif [ "$operation" == "status" -a "$domain" ]; then
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    docker inspect -f '{{.State.Status}}' ${app_container_name}
  else
    show_help
  fi

elif [ "$operation" == "stop" -a "$domain" ]; then
  read_local_config
  if [ "$app_hosting" == "docker" ]; then
    IMAGE_NAME=`docker inspect -f '{{.Config.Image}}' ${app_container_name}`
    docker commit ${app_container_name} ${IMAGE_NAME}
    docker stop ${app_container_name}
  else
    show_help
  fi

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

    # do symbolic links for old paths
    docker exec ${CONTAINER_WEB_ID} ln -s /home/clients/websites/w_${source_user} /home/clients/websites/w_${user}
    docker exec ${CONTAINER_WEB_ID} ln -s /home/clients/databases/b_${source_user} /home/clients/databases/b_${user}
    docker exec ${CONTAINER_WEB_ID} ln -s /etc/apache2/webenabled-logs/virtwww/w_${source_user} /etc/apache2/webenabled-logs/virtwww/w_${user}
    docker exec ${CONTAINER_WEB_ID} mv /var/log/apache2/virtwww/w_${source_user} /var/log/apache2/virtwww/w_${user}
    docker exec ${CONTAINER_WEB_ID} mv /var/log/apache2/virtwww/w_${user}/${source_user}-access_log /var/log/apache2/virtwww/w_${user}/${user}-access_log
    docker exec ${CONTAINER_WEB_ID} mv /var/log/apache2/virtwww/w_${user}/${source_user}-error_log /var/log/apache2/virtwww/w_${user}/${user}-error_log

    USER=`awk -F'.' '{print $1}' <<< "$source_vhost"`
    DOMAIN=${source_domain_name}
    DST_USER=${user}
    DST_DOMAIN=${domain_name}
    # update container's apache2 config with new URL
    docker exec ${CONTAINER_WEB_ID} sed -i "s/${USER}/${DST_USER}/" /etc/apache2/devpanel-virtwww/w_${USER}.conf
    docker exec ${CONTAINER_WEB_ID} sed -i "s/SuexecUserGroup w_${DST_USER}/SuexecUserGroup w_${USER}/" /etc/apache2/devpanel-virtwww/w_${USER}.conf
    docker exec ${CONTAINER_WEB_ID} sed -i "s/${USER}-access_log/${DST_USER}-access_log/" /etc/apache2/devpanel-virtwww/w_${USER}.conf
    docker exec ${CONTAINER_WEB_ID} sed -i "s/${USER}-error_log/${DST_USER}-error_log/" /etc/apache2/devpanel-virtwww/w_${USER}.conf
    docker exec -d ${CONTAINER_WEB_ID} /bin/sh -c "/tmp/startup.sh"
    docker exec ${CONTAINER_WEB_ID} service apache2 restart

    # replace db data with new URL
    app="wordpress"
    PORT=4000
    LOGIN=`docker exec ${CONTAINER_WEB_ID} grep w_ /home/clients/websites/w_${USER}/.mysql.passwd|tail -1|awk -F ":" '{print $1}'`
    PASSWORD=`docker exec ${CONTAINER_WEB_ID} grep w_ /home/clients/websites/w_${USER}/.mysql.passwd|tail -1|awk -F ":" '{print $2}'`
    while [ `docker exec ${CONTAINER_WEB_ID} /bin/sh -c "netstat -ltpn|grep 4000|wc -l"` -eq 0 ]; do
      echo "DB is not running. Waiting its start."
      sleep 1
      docker exec ${CONTAINER_WEB_ID} mysql ${app} -h localhost -P ${PORT} -u ${LOGIN} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
        "UPDATE wp_options SET option_value = replace(option_value, 'http://${USER}.${DOMAIN}', 'http://${DST_USER}.${DST_DOMAIN}');"
    done
    docker exec ${CONTAINER_WEB_ID} mysql ${app} -h localhost -P ${PORT} -u ${LOGIN} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
      "UPDATE wp_options SET option_value = replace(option_value, 'http://${USER}.${DOMAIN}', 'http://${DST_USER}.${DST_DOMAIN}');"

    # check if it was replaced correctly
    if [ `docker exec ${CONTAINER_WEB_ID} mysql ${app} -h localhost -P ${PORT} -u ${LOGIN} --password=${PASSWORD} --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock -e \
      "select * from wp_options;"|grep -c ${DST_USER}` -eq 2 ]; then
        echo "DB cloned correctly."
    else
        echo "Error: URL was not replaced correctly in MySQL."
        exit 1
    fi

    # update host's nginx config with new IP of cloned web container
    domain="${target_vhost}"
    app_clone="true"
    app_container_name="${target_vhost}"
    create_local_config
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

elif [ "$operation" == "scan" -a "$domain" ]; then
  # remove previously used MSF container with old data to avoid errors
  if [ `docker ps -a|grep msf_container|wc -l` -gt 0 ]; then docker rm -f msf_container; fi
  # check if there is enough memory to run MSF with PostgreSQL
  if [ `free -m|grep Mem|awk '{print $4}'` -gt 400 ]; then
    docker_msf
  else
    echo "Not enough memory to run Metasploit!"
    exit 1
  fi

elif [ "$operation" == "destroy" -a "$domain" ]; then
  read_local_config
  if [[ "$app_hosting" == "docker" ]]; then
    docker rm  -f ${app_container_name}
    if [ "$app" == "zabbix" -o "$app" == "hippo" -o "$app" == "msf" ]; then
      docker rmi -f devpanel_${app}:latest
    elif [[ "$app_clone" == "true" ]]; then
      docker rmi -f ${app_container_name}
    else
      docker rmi -f original_${app_container_name}
    fi
    # RDS
    if [ "$app_db_type" == "rds" ]; then
      aws ec2 revoke-security-group-ingress --group-id ${rds_vpcsecuritygroupid} --protocol tcp --port ${rds_endpoint_port} --cidr ${vps_ip}/32
      aws rds delete-db-instance --db-instance-identifier ${app_name} --skip-final-snapshot
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
  ${sudo} rm -f /etc/nginx/sites-enabled/${vhost}-gen.${root_domain}*.conf
  restart_or_reload_nginx
  ${sudo} rm -f ${sys_dir}/config/apps/${domain}.ini
  ${sudo} rm -f ${sys_dir}/config/apps/${vhost}.ini

elif [ "$operation" == "handle" -a "$handler_options" ]; then
  controller_handler

elif [ "$operation" == "pentest" ]; then
  pentest

elif [ "$operation" == "convert" -a "$domain" ]; then
  convert

elif [ "$domain" -a "$read_config" ]; then
  read_local_config
  echo "$app_hosting"

else
  show_help
  exit 1
fi
