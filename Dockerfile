FROM tomcat:8.5-jdk8-openjdk
RUN rm -rf /usr/local/tomcat/webapps/*
COPY target/spring3hibernate.war /usr/local/tomcat/webapps/spring3hibernate.war
EXPOSE 8080
CMD ["catalina.sh", "run"]
