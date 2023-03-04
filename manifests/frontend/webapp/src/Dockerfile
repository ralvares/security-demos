FROM alpine:3.16 

COPY entrypoint /bin/
RUN apk update && apk upgrade && chmod +x /bin/entrypoint

COPY --from=quay.io/vuln/report-generator:latest /opt/app-root/src/log4j-rce-1.0-SNAPSHOT-jar-with-dependencies.jar /

EXPOSE 8080
USER 1001
ENTRYPOINT /bin/entrypoint
