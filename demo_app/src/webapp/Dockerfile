FROM maven:3.8-openjdk-8 as builder

COPY . /usr/src/poc
WORKDIR /usr/src/poc
RUN mvn clean && mvn package

#FROM gcr.io/distroless/java17-debian11
FROM registry.access.redhat.com/ubi8/openjdk-8:latest

ENV exploit=true

USER 1001

ENV SECRET_VALUE='if you can read this this code is vulnerable'

COPY --from=builder /usr/src/poc/target/webapp-1.0-jar-with-dependencies.jar /deployments/webapp-1.0-jar-with-dependencies.jar

ENTRYPOINT ["java", "-jar", "/deployments/webapp-1.0-jar-with-dependencies.jar"]
