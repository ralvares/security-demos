PLATFORMS ?= linux/amd64,linux/arm64
IMAGE ?= quay.io/vuln/mastercard-processor:latest

.PHONY: build push clean

clean:
	-podman manifest rm $(IMAGE) >/dev/null 2>&1 || true
	-podman rmi -f $(IMAGE) >/dev/null 2>&1 || true

build: clean
	@echo "🔧 Building multi-arch image for: $(PLATFORMS)"
	
	# Create the manifest list
	podman manifest create $(IMAGE)
	
	# Build for all platforms using standard emulation
	podman build \
		--platform=$(PLATFORMS) \
		--manifest $(IMAGE) \
		-f Dockerfile \
		--label "app=mastercard processor" .

push:
	@echo "📦 Pushing multi-arch manifest to registry: $(IMAGE)"
	podman manifest push $(IMAGE) docker://$(IMAGE)