ARCH ?= amd64

build:
	podman build --arch=$(ARCH) --label "app=api-server" -f Dockerfile -t quay.io/vuln/api-server:latest .
	podman build --arch=$(ARCH) --label "app=backend-atlas" -f Dockerfile -t quay.io/vuln/backend-atlas:latest .
	podman build --arch=$(ARCH) --label "app=backend-cache" -f Dockerfile -t quay.io/vuln/backend-cache:latest .
	podman build --arch=$(ARCH) --label "app=report-generator" -f Dockerfile -t quay.io/vuln/report-generator:latest .

push:
	podman push quay.io/vuln/api-server:latest
	podman push quay.io/vuln/backend-atlas:latest
	podman push quay.io/vuln/backend-cache:latest
	podman push quay.io/vuln/report-generator:latest
