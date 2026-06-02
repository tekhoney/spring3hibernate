FROM tomcat:8.5-jdk8-openjdk
RUN rm -rf /usr/local/tomcat/webapps/*

# Yahan 'target/' ke baad S aur H capital hona chahiye, aur 'App' bhi judega
COPY target/Spring3HibernateApp.war /usr/local/tomcat/webapps/spring3hibernate.war

EXPOSE 8080
CMD ["catalina.sh", "run"]
