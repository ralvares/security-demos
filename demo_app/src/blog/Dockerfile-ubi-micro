FROM golang:latest as builder

WORKDIR /app
COPY entrypoint.go .
RUN go build entrypoint.go

FROM registry.access.redhat.com/ubi9/ubi-micro

COPY --from=builder /app/entrypoint /bin

ENV exploit=false

entrypoint ["/bin/entrypoint"]
