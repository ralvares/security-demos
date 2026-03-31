PLATFORMS ?= linux/amd64
IMAGE ?= quay.io/vuln/webapp:latest

.PHONY: build push clean

clean:
	# Remove the local image to ensure a fresh build
	-podman rmi -f $(IMAGE) >/dev/null 2>&1 || true

build: clean
	@echo "🔧 Building single-arch image for: $(PLATFORMS)"

	# Build directly to a tag (no manifest list)
	podman build \
		--platform=$(PLATFORMS) \
		-t $(IMAGE) \
		-f Dockerfile \
		--label "app=webapp" .

push:
	@echo "📦 Pushing image to registry: $(IMAGE)"
	podman push $(IMAGE)
