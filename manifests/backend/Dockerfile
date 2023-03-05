FROM maven as builder 

COPY . /usr/src/poc
WORKDIR /usr/src/poc
RUN mvn clean && mvn package

FROM debian:8

COPY src/entrypoint /bin/

USER 1001

COPY --from=builder /usr/src/poc/target/log4j-rce-1.0-SNAPSHOT-jar-with-dependencies.jar /opt/app-root/src/

ENTRYPOINT /bin/entrypoint