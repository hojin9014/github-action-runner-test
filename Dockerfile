FROM tomcat:10.1-jdk17

RUN rm -rf /usr/local/tomcat/webapps/*

COPY target/nice-poc.war /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080
