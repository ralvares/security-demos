ARCH ?= amd64

build:
	podman build --arch=$(ARCH) --label "app=rce-webapp" -f Dockerfile -t quay.io/vuln/rce-webapp:latest .
	podman build --arch=$(ARCH) --label "app=rce-webapp" -f Dockerfile-alpine -t quay.io/vuln/rce-webapp:alpine .
	podman build --arch=$(ARCH) --label "app=rce-webapp" -f Dockerfile-ubi-micro -t quay.io/vuln/rce-webapp:ubi-micro .

push:
	podman push quay.io/vuln/rce-webapp:latest
	podman push quay.io/vuln/rce-webapp:alpine
	podman push quay.io/vuln/rce-webapp:ubi-micro
