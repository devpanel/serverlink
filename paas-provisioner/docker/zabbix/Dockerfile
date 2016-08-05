FROM ubuntu:14.04.4
EXPOSE 80

# setup Zabbix
RUN apt-get update && apt-get install -y mysql-server
RUN service mysql restart && \
  mysql -e "CREATE DATABASE zabbix; CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'zabbix'; GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost'; FLUSH PRIVILEGES;" && \
  apt-get install -y php5-mysql zabbix-server-mysql && \
  sed -i 's/# DBPassword=/DBPassword=zabbix/' /etc/zabbix/zabbix_server.conf && \
  cd /usr/share/zabbix-server-mysql && \
  gunzip schema.sql.gz && mysql zabbix < schema.sql && \
  gunzip images.sql.gz && mysql zabbix < images.sql && \
  gunzip data.sql.gz && mysql zabbix < data.sql && \
  apt-get install -y zabbix-frontend-php
RUN sed -i 's/START=no/START=yes/' /etc/default/zabbix-server
ADD ./000-default.conf /etc/apache2/sites-available/000-default.conf
ADD ./zabbix.conf.php /etc/zabbix/zabbix.conf.php
RUN echo 'ServerName zabbix.localdomain' >> /etc/apache2/apache2.conf

# start services
CMD service mysql restart && service zabbix-server restart && service apache2 restart && sleep infinity
