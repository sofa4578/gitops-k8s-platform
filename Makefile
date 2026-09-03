.PHONY: help up down bootstrap verify drift-demo seal-secret lint test

CLUSTER_NAME ?= gitops-platform

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up:  ## Create the kind cluster
	kind create cluster --name $(CLUSTER_NAME) --config kind/cluster.yaml

down:  ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

bootstrap:  ## Install Argo CD and apply the root app-of-apps Application
	scripts/bootstrap.sh

verify:  ## Check that every platform and tenant workload is healthy
	scripts/verify.sh

drift-demo:  ## Demonstrate Argo CD self-heal by introducing manual drift
	scripts/drift-demo.sh

seal-secret:  ## Wrap kubeseal (usage: make seal-secret ARGS="-n team-alpha secret.yaml")
	scripts/seal-secret.sh $(ARGS)

lint:  ## Lint YAML manifests and the webapp Helm chart
	yamllint -c .yamllint.yaml .
	helm lint charts/webapp -f charts/webapp/ci-values.yaml
	helm unittest charts/webapp

test:  ## Run the webapp unit tests
	cd src/webapp && pytest -q tests/
