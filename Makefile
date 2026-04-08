# NexusLiberty — Common Development Targets
# Run 'make help' to see available targets.

.DEFAULT_GOAL := help

.PHONY: help build build-ihs test lint deploy clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Liberty application image
	docker build -t ghcr.io/jconover/nexusliberty-app:latest -f docker/liberty-app/Dockerfile .

build-ihs: ## Build IHS load balancer image
	docker build -t ghcr.io/jconover/nexusliberty-ihs:latest -f docker/ihs/Dockerfile .

test: ## Run Maven unit and integration tests
	cd app && mvn clean verify -B

lint: ## Run Ansible lint on playbooks and roles
	cd ansible && ansible-lint playbooks/ roles/

deploy: ## Apply Liberty manifests to OKD (requires oc login)
	oc apply -f openshift/liberty-deployment/

clean: ## Remove local Docker images
	docker rmi ghcr.io/jconover/nexusliberty-app:latest 2>/dev/null || true
	docker rmi ghcr.io/jconover/nexusliberty-ihs:latest 2>/dev/null || true
