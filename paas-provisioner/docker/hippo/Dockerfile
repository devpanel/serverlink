FROM ubuntu:14.04.4
EXPOSE 8080

# setup Hippo
RUN apt-get update
RUN apt-get install -y software-properties-common
RUN add-apt-repository -y ppa:andrei-pozolotin/maven3
RUN add-apt-repository -y ppa:webupd8team/java
RUN apt-get update
RUN echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections && \
  echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections && \
  apt-get install -y oracle-java8-installer
RUN apt-get install -y oracle-java8-set-default maven3
RUN mvn --batch-mode archetype:generate \
-DarchetypeGroupId=org.onehippo.cms7 \
-DarchetypeArtifactId=hippo-project-archetype \
-DarchetypeVersion=4.0.0 \
-DarchetypeRepository=http://maven.onehippo.com/maven2 && \
  cd /myhippoproject && mvn clean verify

# start services
CMD cd /myhippoproject && mvn -Pcargo.run -Drepo.path=storage
