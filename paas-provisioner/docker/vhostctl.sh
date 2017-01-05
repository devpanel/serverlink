#!/bin/bash

show_help()
{
  echo "Usage: ./vhostctl.sh [OPTIONS]

Options:

  -A, --application               Application name. Apps supported: Wordpress, Drupal, Zabbix, Hippo.
  -C, --operation                 Operation commands:
                                    start - to build and/or start container with the application
                                    status - to show status of container with the application
                                    stop - to stop container with the application
                                    clone - to copy container with new names and replace configuration with new URL,
                                      has option to convert the application from local to docker and vice versa
                                    backup - to save current state of existing container
                                    restore - to restore container to previous state
                                    destroy - to remove container with webapp
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
  ./vhostctl.sh -C=clone -O=convert -SD=t3st.some.domain -DD=t4st.some.domain
  ./vhostctl.sh -C=backup  -DD=t3st.some.domain -B=t3st_backup1
  ./vhostctl.sh -C=restore -DD=t3st.some.domain -R=t3st_backup1
  ./vhostctl.sh -C=destroy -DD=t3st.some.domain
  ./vhostctl.sh -C=destroy -DD=t3st.some.domain -RB
  ./vhostctl.sh -C=scan -DD=t3st.some.domain
  ./vhostctl.sh -C=pentest
  ./vhostctl.sh -C=handle -DD=t3st.some.domain -O="check-disk-quota##90"
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
sys_data_dir=$(readlink -e "$self_dir/../../../webenabled-data")

for lib_file in $sys_dir/lib/functions $self_dir/functions; do
  if ! source "$lib_file"; then
    echo "Error: unable to source lib file $lib_file" 1>&2
    exit 1
  fi
done

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
    case "${i}" in
      -P|-p|-i|-I|-n|-F|-S)
        known_args="${i#*=}"
      ;;
      *)
        echo "Unknown arguments: ${i}"
        show_help
      ;;
    esac
    ;;
esac
done


# definitions
## define to use sudo or not
if [ "$UID" -eq 0 ]; then
  sudo=""
else
  sudo="sudo"
fi
## define installation tool
if [ -f /usr/bin/yum ]; then
  installation_tool="yum install -y"
elif [ -f /usr/bin/apt-get ]; then
  installation_tool="apt-get install -y"
else
  echo "OS not supported. Exiting ..."
  exit 1
fi
## workaround for AWS
if [ `ip ad sh|grep -c ' eth'` -gt '0' ]; then
  vps_ip=`ip ad sh|grep ' eth'|tail -1|awk '{print $2}'|awk -F'/' '{print $1}'`
else
  vps_ip=`ip ad sh|grep ' ens'|tail -1|awk '{print $2}'|awk -F'/' '{print $1}'`
fi
while [ `hostname|grep -c devpanel.net` -eq 0 ]; do
  echo "Waiting for hostname setup..."
  sleep 1
done
hostname_fqdn=`hostname`


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
  if [ $(uname -m) == "i686" ]; then
    ${sudo} apt-get install -y docker.io
  else
    ${sudo} apt-get install -y docker-engine
  fi
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

# check for jo installation
if [ ! -f /usr/bin/jo ]; then
  if [ -f /usr/bin/apt-get ]; then
    ${sudo} apt-add-repository ppa:duggan/jo --yes
    ${sudo} apt-get update -q
    ${sudo} apt-get install -y jo
  else
    wget https://github.com/jpmens/jo/archive/master.zip && unzip master.zip && cd jo-master && \
    autoreconf -i && ./configure --prefix=/usr && make check && make install && \
    cd ../ && rm -fr jo-master master.zip 
  fi
fi

# check for swap
if [ `free -m|grep Mem|awk '{print $4}'` -lt 130 -a `free -m|grep Swap|awk '{print $4}'` -eq 0 ]; then
  if [ `df --output=avail /|tail -1` -gt 1024102 ]; then
    if [ -f /swap ]; then
      swapon /swap
    else
      dd if=/dev/zero of=/swap bs=1024 count=1024102 && mkswap /swap && swapon /swap
    fi
  fi
fi
# check for available memory
available_mem=`free -m|grep Mem|awk '{print $4}'`
available_swap=`free -m|grep Swap|awk '{print $4}'`
available_memory=`echo "${available_mem} + ${available_swap}" | bc`
if [ ${available_memory} -lt 130 ]; then
  echo "Error: Not enough memory!" 1>&2
  exit 1
fi



# main logic
if [ "$app" == "zabbix" -a "$operation" == "start" -a "$domain" -a "$host_type" == "docker" ]; then
  docker_build_or_pull_and_tag zabbix
  docker run -d -it --name ${domain}_${app} devpanel_zabbix:latest
  update_nginx_config

elif [ "$app" == "hippo" -a "$operation" == "start" -a "$domain" -a "$host_type" == "docker" ]; then
  docker_build_or_pull_and_tag hippo
  docker run -d -it --name ${domain}_${app} devpanel_hippo:latest
  update_nginx_config

# create app
elif [ "$operation" == "start" -a "$domain" -a "$host_type" ]; then
  operation_create

# start app's container
elif [ "$operation" == "start" -a "$domain" ]; then
  operation_start

elif [ "$operation" == "status" -a "$domain" ]; then
  operation_status

elif [ "$operation" == "stop" -a "$domain" ]; then
  operation_stop

elif [ "$operation" == "clone" -a "$source_domain" -a "$domain" -a "$handler_options" == "convert" ]; then
  operation_convert

elif [ "$operation" == "clone" -a "$source_domain" -a "$domain" ]; then
  operation_clone

elif [ "$operation" == "backup" -a "$backup_name" -a "$domain" ]; then
  operation_backup

elif [ "$operation" == "list_backups" ]; then
  operation_list_backups

elif [ "$operation" == "restore" -a "$restore_name" -a "$domain" ]; then
  operation_restore

elif [ "$operation" == "scan" -a "$domain" ]; then
  operation_scan

elif [ "$operation" == "destroy" -a "$domain" ]; then
  operation_destroy

elif [ "$operation" == "handle" -a "$handler_options" ]; then
  operation_handle

elif [ "$operation" == "pentest" ]; then
  operation_pentest

elif [ "$domain" -a "$read_config" ]; then
  operation_get_app_info

else
  echo "Error: Unknown arguments." 1>&2
  show_help
  exit 1
fi
