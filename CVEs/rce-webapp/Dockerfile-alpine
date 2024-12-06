FROM golang:alpine as builder

WORKDIR /app
COPY entrypoint.go .
RUN go build entrypoint.go

FROM alpine:3.16

RUN apk update && apk upgrade
RUN apk --purge del apk-tools

COPY --from=builder /app/entrypoint /bin

ENV exploit=false

USER 1001

entrypoint ["/bin/entrypoint"]
