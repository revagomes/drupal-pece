.PHONY: help build build-php build-nginx push deploy rollback logs shell shell-php shell-nginx shell-mariadb status validate clean \
        compose-deploy compose-rollback compose-status compose-logs

# Environment variables with defaults
PROJECT_NAME ?= pece
ENV ?= production
IMAGE_TAG ?= latest
CONTAINER_REGISTRY ?=
BUILD_ENGINE ?= podman
NAMESPACE ?= pece
KUBECTL ?= kubectl
TAG ?=
SERVICE ?=

# VPS / Docker Compose variables
VPS_HOST ?=
VPS_USER ?=
VPS_SSH_KEY ?=
VPS_DEPLOY_PATH ?= /opt/pece2

# Derived variables
PHP_IMAGE = $(if $(CONTAINER_REGISTRY),$(CONTAINER_REGISTRY)/)$(PROJECT_NAME)-php:$(IMAGE_TAG)
NGINX_IMAGE = $(if $(CONTAINER_REGISTRY),$(CONTAINER_REGISTRY)/)$(PROJECT_NAME)-nginx:$(IMAGE_TAG)

##	help	:	Print commands help.
help:
	@echo "Deployment Makefile for $(PROJECT_NAME)"
	@echo ""
	@echo "Available targets:"
	@sed -n 's/^##//p' Makefile
	@echo ""
	@echo "Environment variables:"
	@echo "  PROJECT_NAME      - Project name (default: pece)"
	@echo "  ENV               - Environment (default: production)"
	@echo "  IMAGE_TAG         - Container image tag (default: latest)"
	@echo "  CONTAINER_REGISTRY - Container registry URL (default: none)"
	@echo "  BUILD_ENGINE      - Build engine: podman or docker (default: podman)"
	@echo "  NAMESPACE         - Kubernetes namespace (default: pece)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                           # Build all images"
	@echo "  make build-php IMAGE_TAG=v1.0.0      # Build PHP image with tag"
	@echo "  make push CONTAINER_REGISTRY=registry.example.com  # Push to registry"
	@echo "  make deploy ENV=staging              # Deploy to staging"
	@echo "  make rollback                        # Rollback to previous version"

##	build	:	Build all container images.
build:
	@echo "Building all container images for $(PROJECT_NAME)..."
	@./scripts/build.sh all --tag $(IMAGE_TAG) $(if $(CONTAINER_REGISTRY),--registry $(CONTAINER_REGISTRY))
	@echo "Finished building all images."

##	build-php	:	Build PHP-FPM container image.
build-php:
	@echo "Building PHP-FPM image..."
	@./scripts/build.sh php --tag $(IMAGE_TAG) $(if $(CONTAINER_REGISTRY),--registry $(CONTAINER_REGISTRY))
	@echo "Finished building PHP-FPM image: $(PHP_IMAGE)"

##	build-nginx	:	Build Nginx container image.
build-nginx:
	@echo "Building Nginx image..."
	@./scripts/build.sh nginx --tag $(IMAGE_TAG) $(if $(CONTAINER_REGISTRY),--registry $(CONTAINER_REGISTRY))
	@echo "Finished building Nginx image: $(NGINX_IMAGE)"

##	push	:	Push container images to registry.
##		Requires CONTAINER_REGISTRY to be set.
push:
ifndef CONTAINER_REGISTRY
	$(error CONTAINER_REGISTRY is not set. Use: make push CONTAINER_REGISTRY=registry.example.com)
endif
	@echo "Pushing images to $(CONTAINER_REGISTRY)..."
	@./scripts/build.sh all --tag $(IMAGE_TAG) --registry $(CONTAINER_REGISTRY) --push
	@echo "Finished pushing images to registry."

##	deploy	:	Deploy to Kubernetes cluster.
##		Set ENV variable to specify environment (default: production).
deploy:
	@echo "Deploying $(PROJECT_NAME) to Kubernetes ($(ENV))..."
	@./scripts/deploy-k8s.sh --namespace $(NAMESPACE) --wait
	@echo "Finished deploying $(PROJECT_NAME)."

##	rollback	:	Rollback Kubernetes deployment to previous version.
rollback:
	@echo "Rolling back $(PROJECT_NAME) deployment..."
	@./scripts/rollback-k8s.sh all --namespace $(NAMESPACE) --wait
	@echo "Finished rollback."

##	rollback-php	:	Rollback PHP-FPM deployment only.
rollback-php:
	@echo "Rolling back PHP-FPM deployment..."
	@./scripts/rollback-k8s.sh php --namespace $(NAMESPACE) --wait
	@echo "Finished PHP-FPM rollback."

##	rollback-nginx	:	Rollback Nginx deployment only.
rollback-nginx:
	@echo "Rolling back Nginx deployment..."
	@./scripts/rollback-k8s.sh nginx --namespace $(NAMESPACE) --wait
	@echo "Finished Nginx rollback."

##	rollback-mariadb	:	Rollback MariaDB StatefulSet.
rollback-mariadb:
	@echo "Rolling back MariaDB StatefulSet..."
	@./scripts/rollback-k8s.sh mariadb --namespace $(NAMESPACE) --wait
	@echo "Finished MariaDB rollback."

# --- Docker Compose / Easypanel targets (VPS 1) ----------------------------

##	compose-deploy	:	Deploy to VPS 1 via Docker Compose + Easypanel.
##		Requires: VPS_HOST, VPS_USER, VPS_SSH_KEY, VPS_DEPLOY_PATH, DB_PASSWORD, DB_ROOT_PASSWORD
compose-deploy:
	@echo "Deploying $(PROJECT_NAME) to VPS 1 via Docker Compose..."
	@./scripts/deploy-compose.sh
	@echo "Finished Docker Compose deployment."

##	compose-rollback	:	Rollback Docker Compose deployment to a specific image tag.
##		Requires: TAG=sha-<short> (e.g. make compose-rollback TAG=sha-abc1234)
compose-rollback:
ifndef TAG
	$(error TAG is not set. Use: make compose-rollback TAG=sha-<short>)
endif
	@echo "Rolling back $(PROJECT_NAME) to tag $(TAG)..."
	@./scripts/rollback-compose.sh --tag $(TAG)
	@echo "Finished rollback to tag $(TAG)."

##	compose-status	:	Show running Docker Compose services on VPS 1.
compose-status:
	@ssh -i "$(VPS_SSH_KEY)" -o StrictHostKeyChecking=no \
		"$(VPS_USER)@$(VPS_HOST)" \
		"cd '$(VPS_DEPLOY_PATH)' && docker compose ps"

##	compose-logs	:	Tail logs from Docker Compose services on VPS 1.
##		Optionally pass SERVICE=php|nginx|mariadb to limit output.
compose-logs:
	@ssh -i "$(VPS_SSH_KEY)" -o StrictHostKeyChecking=no \
		"$(VPS_USER)@$(VPS_HOST)" \
		"cd '$(VPS_DEPLOY_PATH)' && docker compose logs --tail=100 -f $(SERVICE)"

##	logs	:	View deployment logs.
##		You can optionally pass an argument with the component name to limit logs:
##		make logs COMPONENT=php     : View PHP-FPM logs.
##		make logs COMPONENT=nginx   : View Nginx logs.
##		make logs COMPONENT=mariadb : View MariaDB logs.
logs:
	@if [ -n "$(COMPONENT)" ]; then \
		echo "Viewing logs for $(COMPONENT)..."; \
		$(KUBECTL) logs -n $(NAMESPACE) -l app=$(PROJECT_NAME),component=$(COMPONENT) --tail=100 -f; \
	else \
		echo "Viewing logs for all components..."; \
		$(KUBECTL) logs -n $(NAMESPACE) -l app=$(PROJECT_NAME) --tail=50 -f --all-containers=true; \
	fi

##	shell	:	Access PHP-FPM pod via shell.
shell: shell-php

##	shell-php	:	Access PHP-FPM pod via shell.
shell-php:
	@echo "Accessing PHP-FPM pod shell..."
	@$(KUBECTL) exec -it -n $(NAMESPACE) \
		-e COLUMNS=$$(tput cols) -e LINES=$$(tput lines) \
		$$($(KUBECTL) get pods -n $(NAMESPACE) -l app=$(PROJECT_NAME),component=php-fpm -o jsonpath='{.items[0].metadata.name}') \
		-- /bin/bash

##	shell-nginx	:	Access Nginx pod via shell.
shell-nginx:
	@echo "Accessing Nginx pod shell..."
	@$(KUBECTL) exec -it -n $(NAMESPACE) \
		-e COLUMNS=$$(tput cols) -e LINES=$$(tput lines) \
		$$($(KUBECTL) get pods -n $(NAMESPACE) -l app=$(PROJECT_NAME),component=nginx -o jsonpath='{.items[0].metadata.name}') \
		-- /bin/bash

##	shell-mariadb	:	Access MariaDB pod via shell.
shell-mariadb:
	@echo "Accessing MariaDB pod shell..."
	@$(KUBECTL) exec -it -n $(NAMESPACE) \
		-e COLUMNS=$$(tput cols) -e LINES=$$(tput lines) \
		$$($(KUBECTL) get pods -n $(NAMESPACE) -l app=$(PROJECT_NAME),component=database -o jsonpath='{.items[0].metadata.name}') \
		-- /bin/bash

##	drush	:	Execute drush command in PHP-FPM pod.
##		Doesn't support --flag arguments unless wrapped in quotes.
##		Example: make drush ARGS="status"
##		Example: make drush ARGS="cr"
drush:
	@$(KUBECTL) exec -it -n $(NAMESPACE) \
		$$($(KUBECTL) get pods -n $(NAMESPACE) -l app=$(PROJECT_NAME),component=php-fpm -o jsonpath='{.items[0].metadata.name}') \
		-- drush -r /var/www/html/web $(ARGS)

##	status	:	Show deployment status.
status:
	@echo "=== Deployment Status for $(PROJECT_NAME) in $(NAMESPACE) ==="
	@echo ""
	@echo "--- Namespaces ---"
	@$(KUBECTL) get namespace $(NAMESPACE) 2>/dev/null || echo "Namespace $(NAMESPACE) not found"
	@echo ""
	@echo "--- Pods ---"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo ""
	@echo "--- Deployments ---"
	@$(KUBECTL) get deployments -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo ""
	@echo "--- StatefulSets ---"
	@$(KUBECTL) get statefulsets -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo ""
	@echo "--- Services ---"
	@$(KUBECTL) get services -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo ""
	@echo "--- Ingress ---"
	@$(KUBECTL) get ingress -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo ""
	@echo "--- PersistentVolumeClaims ---"
	@$(KUBECTL) get pvc -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo ""
	@echo "--- HorizontalPodAutoscaler ---"
	@$(KUBECTL) get hpa -n $(NAMESPACE) -l app=$(PROJECT_NAME)

##	validate	:	Validate Kubernetes manifests and OpenTofu configuration.
validate:
	@echo "Validating Kubernetes manifests..."
	@$(KUBECTL) apply --dry-run=client -f kubernetes/ 2>&1 | head -20
	@echo ""
	@echo "Validating OpenTofu configuration..."
	@cd opentofu && tofu init -backend=false && tofu validate

##	clean	:	Remove deployed resources from Kubernetes.
##		WARNING: This will delete all resources in the namespace!
clean:
	@echo "WARNING: This will delete all resources in namespace $(NAMESPACE)!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted."; exit 1)
	@echo "Deleting all resources in $(NAMESPACE)..."
	@$(KUBECTL) delete all -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@$(KUBECTL) delete pvc -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@$(KUBECTL) delete configmap -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@$(KUBECTL) delete secret -n $(NAMESPACE) -l app=$(PROJECT_NAME)
	@echo "Finished cleaning up resources."

# https://stackoverflow.com/a/6273809/1826109
%:
	@:
