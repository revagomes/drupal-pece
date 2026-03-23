include docker.mk

.PHONY: test install build site-install distro-install nuxt-install nuxt-build nuxt-lint nuxt-run start-automation k8s-build k8s-deploy k8s-rollback k8s-status k8s-logs \
        compose-deploy compose-rollback compose-status compose-logs

DRUPAL_VER ?= 8
PHP_VER ?= 8.1
FILE_MATCH ?=

BRANCH = $(shell git rev-parse --abbrev-ref HEAD)
PHP_CONTAINER = $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}")

##	hlp	:	Print commands help.
hlp : Makefile
	@sed -n 's/^##//p' $<

##	test	: 	Run test automation.
test:
	cd ./tests/$(DRUPAL_VER) && PHP_VER=$(PHP_VER) ./run.sh

##	install	:	Install project dependencies.
##		Set ENVIRONMENT variable as prod to skip development dependencies.
##		By default it will install dev dependencies if ENVIRONMENT is not set. 
install:
	@echo "Install $(PROJECT_NAME) dependencies..."
ifeq ($(ENVIRONMENT), prod)
	docker exec -t $(PHP_CONTAINER) composer install --no-dev
else
	docker exec -t $(PHP_CONTAINER) composer install
endif
	@echo "Finished installing $(PROJECT_NAME) dependencies..."

##	build	:	Build the project.
build:
	@echo "Build $(PROJECT_NAME)..."
	@make install
# TODO: Add drush config:import -y when there are settings files 
	docker exec -t $(PHP_CONTAINER) bash -c 'vendor/bin/drush updb -y'
	@echo "Finished building $(PROJECT_NAME)"

##	site-install	:	(Re)Install PECE profile.
site-install:
	@echo "Starting $(PROJECT_NAME) install phase..."
	docker exec -t $(PHP_CONTAINER) bash -c 'vendor/bin/drush si pece install_configure_form.site_name=PECE2 -y'
	@make perm-fix
	@echo "Finish $(PROJECT_NAME) Install phase."

##	config-import	:	Import configuration and run update process.
config-import:
	@echo "Importing configuration for $(PROJECT_NAME)..."
	docker exec -t $(PHP_CONTAINER) bash -c 'vendor/bin/drush cim --partial -y'
	@echo "Finished importing configuration."
	@make update

##	update	:	Run update process	
update:
	@echo "Starting update process for $(PROJECT_NAME)..."
	docker exec -t $(PHP_CONTAINER) bash -c 'vendor/bin/drush updb -y'
	@echo "Finish $(PROJECT_NAME) update."

##	perm-fix	:	Fix permission for web/sites/default/files dir	
perm-fix:
	docker exec -t $(PHP_CONTAINER) bash -c 'chown -R wodby:www-data web/sites/default/files'

distro-install:
	docker-compose -f services-drupal.yml run --rm install

nuxt-install:
	cd $(FRONT_DIR) && make install

nuxt-build:
	cd $(FRONT_DIR) && make build

nuxt-lint:
	cd $(FRONT_DIR) && make lint

nuxt-run:
	cd $(FRONT_DIR) && make run

##	start-automation	:	Start automation workflows.
start-automation:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_n8n' --format "{{ .ID }}") python /root/.pece/startWorkflows.py

##	k8s-build	:	Build container images for Kubernetes deployment.
##		Set IMAGE_TAG to specify version (default: latest).
##		Set CONTAINER_REGISTRY to push to private registry.
k8s-build:
	@echo "Building container images for Kubernetes..."
	cd deploy && $(MAKE) build
	@echo "Finished building container images."

##	k8s-deploy	:	Deploy to Kubernetes cluster.
##		Set ENV to specify environment (default: production).
##		Deploys all services and waits for rollout completion.
k8s-deploy:
	@echo "Deploying $(PROJECT_NAME) to Kubernetes..."
	cd deploy && $(MAKE) deploy
	@echo "Finished deploying $(PROJECT_NAME) to Kubernetes."

##	k8s-rollback	:	Rollback Kubernetes deployment to previous version.
##		Set COMPONENT to rollback specific service (php, nginx, mariadb).
##		Default: rollback all components.
k8s-rollback:
	@echo "Rolling back Kubernetes deployment..."
	cd deploy && $(MAKE) rollback
	@echo "Finished rollback."

##	k8s-status	:	Show Kubernetes deployment status.
##		Displays pods, deployments, services, ingress, and HPA status.
k8s-status:
	@echo "Kubernetes deployment status for $(PROJECT_NAME):"
	cd deploy && $(MAKE) status

##	k8s-logs	:	View Kubernetes deployment logs.
##		Set COMPONENT to view specific service logs (php, nginx, mariadb).
##		Default: show all logs.
k8s-logs:
	cd deploy && $(MAKE) logs

##	compose-deploy	:	Deploy to VPS 1 via Docker Compose + Easypanel.
##		Requires env: VPS_HOST, VPS_USER, VPS_SSH_KEY, VPS_DEPLOY_PATH, DB_PASSWORD, DB_ROOT_PASSWORD
compose-deploy:
	cd deploy && $(MAKE) compose-deploy

##	compose-rollback	:	Rollback Docker Compose deployment to a specific image tag.
##		Requires: TAG=sha-<short> (e.g. make compose-rollback TAG=sha-abc1234)
compose-rollback:
	cd deploy && $(MAKE) compose-rollback TAG=$(TAG)

##	compose-status	:	Show running Docker Compose services on VPS 1.
##		Requires env: VPS_HOST, VPS_USER, VPS_SSH_KEY, VPS_DEPLOY_PATH
compose-status:
	cd deploy && $(MAKE) compose-status VPS_HOST=$(VPS_HOST) VPS_USER=$(VPS_USER) VPS_SSH_KEY=$(VPS_SSH_KEY) VPS_DEPLOY_PATH=$(VPS_DEPLOY_PATH)

##	compose-logs	:	Tail logs from Docker Compose services on VPS 1.
##		Optionally pass SERVICE=php|nginx|mariadb to limit output.
compose-logs:
	cd deploy && $(MAKE) compose-logs VPS_HOST=$(VPS_HOST) VPS_USER=$(VPS_USER) VPS_SSH_KEY=$(VPS_SSH_KEY) VPS_DEPLOY_PATH=$(VPS_DEPLOY_PATH) SERVICE=$(SERVICE)
