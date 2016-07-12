FROM ubuntu:14.04.4
EXPOSE 80

# get essentials
RUN apt-get update && apt-get install -y wget unzip

# install metasploit-framework
RUN echo "deb http://downloads.metasploit.com/data/releases/metasploit-framework/apt trusty main" > /etc/apt/sources.list.d/metasploit-framework.list
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CDFB5FA52007B954
RUN apt-get update
RUN apt-get install -y postgresql metasploit-framework
RUN service postgresql restart && sudo -u postgres bash -c "psql -c \"CREATE ROLE msf WITH LOGIN PASSWORD 'msf';\"" && sudo -u postgres bash -c "createdb -O msf msf"
ADD ./database.yml /root/.msf4/database.yml
ADD ./wmap.rc /tmp/wmap.rc
ADD ./wmap.profile /tmp/wmap.profile

CMD service postgresql restart && sleep infinity
