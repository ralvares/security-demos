FROM cgr.dev/chainguard/maven as builder 

COPY . /home/build
WORKDIR /home/build
RUN mvn clean && mvn package

FROM debian:9

COPY src/entrypoint /bin/

USER 1001

COPY --from=builder /home/build/target/log4j-rce-1.0-SNAPSHOT-jar-with-dependencies.jar /opt/app-root/src/

ENTRYPOINT /bin/entrypoint
