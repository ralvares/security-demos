FROM maven:3-jdk-8-alpine as builder

RUN mkdir -p /usr/src/app && mkdir /app

ADD ./pom.xml /usr/src/app/pom.xml
ADD ./src /usr/src/app/src

RUN cd /usr/src/app && \
	mvn package && \
	cp /usr/src/app/target/*.jar /app/cve-2017-538-example.jar && \
	rm -Rf /usr/src/app

FROM openjdk:8u102-jre

COPY --from=builder /app /app

WORKDIR /app

ENTRYPOINT java -jar /app/cve-2017-538-example.jar 

EXPOSE 8080
