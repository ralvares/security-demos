# --- Configuration ---
PLATFORMS ?= linux/amd64
# Update the registry and image name as needed
REGISTRY  ?= quay.io/vuln
APP_NAME  ?= url-shortener
TAG       ?= latest
IMAGE     ?= $(REGISTRY)/$(APP_NAME):$(TAG)

# --- Colors for Output ---
BLUE      := \033[36m
RESET     := \033[0m

.PHONY: build push clean deploy all

all: build push

clean:
	@echo "$(BLUE)🧹 Cleaning up local image: $(IMAGE)$(RESET)"
	# Remove the local image to ensure a fresh build
	-podman rmi -f $(IMAGE) >/dev/null 2>&1 || true

build: clean
	@echo "$(BLUE)🔧 Building single-arch image for: $(PLATFORMS)$(RESET)"
	@echo "$(BLUE)📂 Image Tag: $(IMAGE)$(RESET)"
	
	# Build directly to a tag using your Dockerfile
	podman build \
		--platform=$(PLATFORMS) \
		-t $(IMAGE) \
		-f Dockerfile \
		--label "app=url-shortener" \
		--label "description=Modular K8s-Native URL Shortener" .

push:
	@echo "$(BLUE)📦 Pushing image to registry: $(IMAGE)$(RESET)"
	podman push $(IMAGE)

deploy:
	@echo "$(BLUE)🚀 Deploying to OpenShift/Kubernetes...$(RESET)"
	# Assumes your manifest is named deploy.yaml
	oc apply -f deploy.yaml
	@echo "$(BLUE)✅ Deployment triggered. Check pods with: oc get pods -l app=url-shortener$(RESET)"