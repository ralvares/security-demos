ARCH ?= amd64

build:
	podman build --arch=$(ARCH) --label "app=struts cve-201705638" -f Dockerfile -t quay.io/vuln/struts-cve-2017-5638:latest .
	podman build --arch=$(ARCH) --label "app=visa processor" -f Dockerfile -t quay.io/vuln/visa-processor:latest .
	podman build --arch=$(ARCH) --label "app=master-card processor" -f Dockerfile -t quay.io/vuln/mastercard-processor:latest .

push:
	podman push quay.io/vuln/struts-cve-2017-5638:latest
	podman push quay.io/vuln/visa-processor:latest
	podman push quay.io/vuln/mastercard-processor:latest