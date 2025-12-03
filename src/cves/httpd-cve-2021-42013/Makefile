PLATFORMS ?= linux/amd64,linux/arm64
IMAGE ?= quay.io/vuln/asset-cache:v1

build:
	@echo "🔧 Building multi-arch image for: $(PLATFORMS)"
	# Clean any existing single-arch image with the same tag
	-podman rmi -f $(IMAGE) >/dev/null 2>&1 || true
	# Remove any old manifest list
	-podman manifest rm $(IMAGE) >/dev/null 2>&1 || true
	# Create a new manifest list
	podman manifest create $(IMAGE)
	# Build all target architectures and add them to the manifest
	podman build \
		--platform=$(PLATFORMS) \
		--manifest $(IMAGE) \
		-f Dockerfile \
		--label "app=Security Demo" .

push:
	@echo "📦 Pushing multi-arch manifest to registry: $(IMAGE)"
	podman manifest push $(IMAGE) docker://$(IMAGE)