FROM alpine:3.16 

COPY entrypoint /bin/
RUN apk update && apk upgrade && chmod +x /bin/entrypoint

EXPOSE 8080
USER 1001
ENTRYPOINT /bin/entrypoint
