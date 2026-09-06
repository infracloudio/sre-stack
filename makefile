help:
	@echo "EKS setup/deploy/cleanup commands:"
	@echo "	setup                               - End-to-end setup on EKS"
	@echo "	start-cluster                       - start EKS Cluster"
	@echo "	setup-cluster-autoscaler            - Setup node auto scaling"
	@echo "	setup-observability                 - Setup monitoring/observability"
	@echo "	setup-optional-otel                 - Setup OpenTelemetry"
	@echo "	setup-istio                         - Setup istio and ingress"
	@echo "	setup-db-rds-mysql                  - Setup RDS - mysql"
	@echo "	setup-rabbitmq-operator             - Setup rabbitmq-operator"
	@echo "	setup-robot-shop                    - Deploy robot-shop app-stack."
	@echo "	setup-optional-rmq-consumer-scaling - Setup keda to scale dispatch (optional)"
	@echo "	setup-gateway                       - Setup Ingress gateway"
	@echo "	cleanup-cluster                     - Cleanup cluster"
	@echo "	cleanup                             - Clenaup all resources and EKS cluster"
	@echo ""
	@echo ""
	@echo "Local (k3D) setup/deploy/cleanup commands:"
	@echo "	setup-local                         - Setup end-to-end stack on local k8s (k3d)"
	@echo "	setup-local-cluster                 - Setup local k3d cluster"
	@echo "	cleanup-local                       - Cleanup end-to-end stack on local k8s (k3d)"
	@echo ""
	@echo ""
	@echo "Utilities:"
	@echo " get-service-endpoints           - Print exposed service endpoints."

include .env
BASE_SCRIPT_PATH := ./infra/scripts
CLUSTER_SCRIPT_PATH := $(BASE_SCRIPT_PATH)/cluster

REQUIRED_VARS := AWS_REGION CLUSTER_NAME RDS_MYSQL_DB_NAME AUTO_SCALING_GROUP_POLICY_NAME MONITORING_NS RABBITMQ_NS APP_NS RDS_MYSQL_DB_MASTER_PASSWORD APP_RELEASE_NAME APP_SETUP_TIMEOUT LOCAL_APP_SETUP_TIMEOUT APP_STACK STACK_MODE LOCAL_NODES INOTIFY_MAX_USER_INSTANCES INOTIFY_MAX_USER_WATCHES
MYSQL_HOST=$(shell aws rds describe-db-instances --db-instance-identifier $(RDS_MYSQL_DB_NAME)  --region $(AWS_REGION) --query 'DBInstances[*].Endpoint.Address' --output text --no-cli-pager)
ifeq ($(STACK_MODE),eks)
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
else 
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
endif

$(foreach var,$(REQUIRED_VARS),$(if $(value $(var)),,$(error $(var) is not set)))

CHECK_ISTIO_GATEWAY_EXISTS := $(shell helm status istio-ingressgateway -n istio-system 2>/dev/null)
setup:

ifeq ($(APP_STACK),hotrod)
setup: setup-cluster setup-cluster-autoscaler setup-istio setup-observability setup-hotrod setup-gateway get-service-endpoints
else ifeq ($(APP_STACK),robot-shop)
setup: setup-cluster setup-cluster-autoscaler setup-yace setup-istio setup-observability setup-db-rds-mysql setup-rabbitmq-operator setup-robot-shop setup-gateway get-service-endpoints
else ifeq ($(APP_STACK),all)
setup: setup-cluster setup-cluster-autoscaler setup-yace setup-istio setup-observability setup-db-rds-mysql setup-rabbitmq-operator setup-robot-shop setup-hotrod setup-gateway get-service-endpoints
else 
	@echo "Nothing to setup"
endif

setup-cluster:
	$(CLUSTER_SCRIPT_PATH)/setup-cluster.sh

setup-cluster-autoscaler:
	$(CLUSTER_SCRIPT_PATH)/setup-cluster-autoscaler.sh

setup-istio:
	helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update
	helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.17.2 --wait --timeout 2m0s
	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 --set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100 --wait --timeout 2m0s
	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 --wait --timeout 2m0s

setup-db-grafana-psql:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f monitoring/grafana-postgres/statefulset.yaml
	kubectl wait --for=condition=ready pod -l app=postgresql --timeout=300s -n $(MONITORING_NS)
	kubectl apply -f monitoring/grafana-postgres/job.yaml
	kubectl wait --for=condition=complete  jobs create-grafana-database --timeout=300s -n $(MONITORING_NS)

setup-kube-prometheus-stack:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack --values ./monitoring/chart-values/prometheus-values.yaml -n $(MONITORING_NS) --create-namespace --version 52.0.0

setup-loki:
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install loki grafana/loki-stack -n $(MONITORING_NS) --create-namespace --values ./monitoring/chart-values/loki.yaml

setup-beyla:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f monitoring/beyla -n $(MONITORING_NS)

setup-tempo:
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install tempo grafana/tempo --values ./monitoring/chart-values/tempo.yaml --create-namespace -n $(MONITORING_NS)

setup-caretta:
	helm repo add groundcover https://helm.groundcover.com/
	helm repo update
	helm upgrade --install caretta groundcover/caretta --values ./monitoring/chart-values/caretta.yaml --create-namespace -n $(MONITORING_NS)

setup-metric-server:
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/  && helm repo update
	helm upgrade --install metrics-server metrics-server/metrics-server --values ./monitoring/chart-values/metric-server.yaml -n $(MONITORING_NS) --create-namespace

setup-yace:
	$(CLUSTER_SCRIPT_PATH)/setup-yace.sh

setup-istio-o11y-addons:
	kubectl apply -f  monitoring/istio-observability-addons/

setup-dashboards:
	kubectl apply -f ./monitoring/dashboards/

setup-observability: setup-db-grafana-psql setup-kube-prometheus-stack setup-loki setup-beyla setup-tempo setup-caretta setup-metric-server setup-yace setup-istio-o11y-addons setup-dashboards

setup-optional-otel:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update
	helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector --values ./monitoring/chart-values/otel-collector.yaml -n $(MONITORING_NS)


setup-db-rds-mysql:
	./infra/scripts/dbs/rds/mysql/create.sh

setup-rabbitmq-operator:
	helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
	helm upgrade --install rabbitmq-operator bitnami/rabbitmq-cluster-operator -f infra/chart-values/rabbitmq-values.yaml -n $(RABBITMQ_NS) --create-namespace --version 3.10.4 --wait

setup-robot-shop:
	kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace robot-shop istio-injection=enabled
ifeq ($(STACK_MODE),eks)
	helm upgrade --install $(APP_RELEASE_NAME) -n $(APP_NS) --create-namespace ./app/robot-shop/helm/ --set mysql_host=$(MYSQL_HOST) --set mysql_root_password=$(RDS_MYSQL_DB_MASTER_PASSWORD) --wait --timeout $(APP_SETUP_TIMEOUT)
else
	helm upgrade --install $(APP_RELEASE_NAME) -n $(APP_NS) --create-namespace ./app/robot-shop/helm/ --set stack_mode=$(STACK_MODE) --set mysql_root_password=$(RDS_MYSQL_DB_MASTER_PASSWORD) --wait --timeout $(LOCAL_APP_SETUP_TIMEOUT)
endif

setup-hotrod:
	kustomize build app/hotrod | kubectl apply -f -	

setup-gateway:
	kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n $(APP_NS)


setup-keda:
	helm repo add kedacore https://kedacore.github.io/charts && helm repo update ; \
	helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --values ./infra/chart-values/keda-values.yaml --version 2.11.1 ;
	kubectl apply -f ./infra/keda-policy/scaled-obj-dispatch.yaml

setup-loadgen:
	kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f scenarios/load-gen/load.yaml

setup-optional-rmq-consumer-scaling: setup-keda setup-loadgen


get-service-endpoints:
ifeq ($(APP_STACK),hotrod)
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "ToDo"
else ifeq ($(APP_STACK),robot-shop)
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "Visit Robot shop http://$(LB_ENDPOINT)"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else ifeq ($(APP_STACK),all)
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "----------------------------------------------------------------------------------------"
	@echo ""
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "Visit Robot shop http://$(LB_ENDPOINT)"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else 
	@echo "---------------------------- Non-existent APP_STACK --------------------------------------"
endif

destroy-db-rds-mysql:
	./infra/scripts/dbs/rds/mysql/destroy.sh
	./infra/scripts/dbs/rds/sg-destroy.sh

destroy-istio-gateway:
ifeq ($(CHECK_ISTIO_GATEWAY_EXISTS),)
	@echo "istio ingress gateway does not exists"
else 
	helm uninstall istio-ingressgateway -n istio-system
endif

destroy-loadgen:
	kubectl delete -f scenarios/load-gen/load.yaml

destroy-cluster-autoscaler:
	$(CLUSTER_SCRIPT_PATH)/destroy-cluster-autoscaler.sh

destroy-yace:
	$(CLUSTER_SCRIPT_PATH)/destroy-yace.sh

cleanup-cluster: destroy-cluster-autoscaler destroy-yace
	$(CLUSTER_SCRIPT_PATH)/cleanup-cluster.sh


cleanup: destroy-istio-gateway destroy-db-rds-mysql cleanup-cluster

### Local Cluster sre-stack setup
# @saurabh: --disable=metrics-server@server:* (if bundled metrics-server does not work)

setup-local-cluster:
	@echo "[WARNING]	Make sure you can access docker-daemon in a sudoless way.Else this setup step will fail."
	@echo "[WARNING]	Follow documentation here: https://docs.docker.com/engine/install/linux-postinstall/"

	k3d cluster create $(CLUSTER_NAME)-local --agents $(LOCAL_NODES) --k3s-arg "--disable=traefik@server:*" 
	k3d kubeconfig merge $(CLUSTER_NAME)-local -d -s
	
	kubectl label nodes k3d-$(CLUSTER_NAME)-local-agent-0 k3d-$(CLUSTER_NAME)-local-agent-1 workload=o11y
	kubectl taint nodes k3d-$(CLUSTER_NAME)-local-agent-0 k3d-$(CLUSTER_NAME)-local-agent-1 o11y=true:NoSchedule

	kubectl label nodes k3d-$(CLUSTER_NAME)-local-agent-2 workload=app
	kubectl label nodes k3d-$(CLUSTER_NAME)-local-agent-3 workload=persistent
	kubectl label nodes k3d-$(CLUSTER_NAME)-local-agent-4 workload=loadgen

	# Apply sysctl settings to each node
	$(foreach node, $(shell seq 0 $(shell echo $(LOCAL_NODES)-1 | bc)), \
		@echo "" && \
		docker exec -it k3d-$(CLUSTER_NAME)-local-agent-$(node) sh -c 'sysctl fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES) && sysctl fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES)' \
	)

	kubectl apply -f ./infra/local/gp2-storageclass.yaml

setup-local-o11y: setup-db-grafana-psql setup-kube-prometheus-stack setup-loki setup-istio-o11y-addons setup-dashboards

setup-local: setup-local-cluster setup-istio setup-local-o11y setup-robot-shop setup-gateway get-service-endpoints

cleanup-local:
	k3d cluster delete $(CLUSTER_NAME)-local


## TBD integrations
#	@echo "	Setup Litmus-3 chaos tool via:		make setup-litmus"
# @echo "	Setup APM via:				make setup-apm"

# setup-apm:
# 	helm repo add signoz https://charts.signoz.io && helm repo updates
# 	helm upgrade --install install apm-platform signoz/signoz -n $(MONITORING_NS) --create-namespace
# 	kubectl get svc svc/apm-platform-frontend -n $(MONITORING_NS) | grep "3301"

# setup-litmus:
# 	helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
# 	helm upgrade --install chaos litmuschaos/litmus --namespace=litmus --create-namespace --set portal.frontend.service.type=LoadBalancer
# 	kubectl get svc -n litmus | grep "9091"# ============================================================
# MAKEFILE ADDITIONS -- append these targets to the real makefile.
#
# Written to match the existing file's style: each command on its own
# line (no .ONESHELL assumed, matching how setup-db-grafana-psql etc. are
# written), using the same $(MONITORING_NS) variable the rest of the file
# already uses.
#
# HONESTY NOTE: the underlying commands in every target below have been
# proven end-to-end against a real cluster (as a set of standalone shell
# scripts). Translating them into this exact `make` target form is NEW --
# it has NOT been run in this exact shape yet. Treat your first
# `make setup-llm-observability` as a real first test of the make-target
# wiring itself, even though every individual command has already worked.
# ============================================================

## --- OpenTelemetry two-tier migration -------------------------------

.PHONY: setup-otel-patch-prometheus setup-otel-loki setup-otel-tempo setup-otel-gateway setup-otel-agent migrate-to-otel

# Enables the remote-write receiver on the EXISTING Prometheus (installed
# by setup-kube-prometheus-stack) -- no new metrics backend introduced.
# --version is pinned to match whatever was originally installed;
# --reuse-values alone pulls whatever chart version is newest in the
# local Helm cache, which broke on a template/values mismatch when this
# was tested live against a 52.0.0 install.
setup-otel-patch-prometheus:
	helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack -n $(MONITORING_NS) --reuse-values --version 52.0.0 --set prometheus.prometheusSpec.enableRemoteWriteReceiver=true --wait --timeout 5m

# Replaces the "loki" release (installed by setup-loki via the deprecated
# loki-stack chart, Loki 2.6.1) with a modern 3.x install -- see
# LOKI-DECISION.md for why loki.yaml itself is left unchanged (Option B).
# REQUIRED, not optional: 2.6.1 predates OTLP log ingestion entirely
# (added in Loki 3.0) -- confirmed live via a 404 on /otlp/v1/logs.
# Uninstalling the old loki-stack release also retires its bundled
# Promtail in the same step (closes issue #79, "too many open files").
setup-otel-loki:
	helm uninstall loki -n $(MONITORING_NS) || true
	kubectl -n $(MONITORING_NS) delete svc loki-headless --ignore-not-found
	helm upgrade --install loki grafana/loki -n $(MONITORING_NS) -f monitoring/chart-values/loki-otlp.yaml --wait --timeout 5m

# Tempo ALREADY EXISTS in this repo (monitoring/chart-values/tempo.yaml)
# but its receivers don't include zipkin -- apply patches/PATCHES.md's
# zipkin receiver addition to that file FIRST, then this target installs
# it (or re-applies, if some other target already did) and adds a
# "zipkin" Service alias so Istio's already-configured tracing endpoint
# (zipkin.monitoring:9411, set by setup-istio) has something to actually
# reach -- zero changes to Istio itself. If a `setup-tempo` target
# already exists elsewhere in this makefile using the same values file,
# this is likely redundant with it -- check before assuming this is the
# only place Tempo gets installed.
setup-otel-tempo:
	helm upgrade --install tempo grafana/tempo -n $(MONITORING_NS) -f monitoring/chart-values/tempo.yaml --wait --timeout 5m
	kubectl apply -f monitoring/chart-values/zipkin-service-alias.yaml

# Gateway tier: cluster-wide Deployment. Deploy before the agent tier,
# since agents forward to it via OTLP. Additional to (not a replacement
# for) the existing otel-collector.yaml / setup-optional-otel.
setup-otel-gateway:
	helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector -n $(MONITORING_NS) -f monitoring/chart-values/otel-collector-gateway.yaml --wait --timeout 5m

# Agent tier: DaemonSet, one per node. Requires a toleration for the
# "o11y" taint applied by setup-local-cluster -- without it, the 2 nodes
# actually running Prometheus/Grafana/Loki are silently never covered
# (confirmed live: DESIRED showed 4, not 6, before this was added to the
# values file).
setup-otel-agent:
	helm upgrade --install otel-agent open-telemetry/opentelemetry-collector -n $(MONITORING_NS) -f monitoring/chart-values/otel-collector-agent.yaml --wait --timeout 5m

# Full migration, in dependency order.
migrate-to-otel: setup-otel-patch-prometheus setup-otel-loki setup-otel-tempo setup-otel-gateway setup-otel-agent
	@echo "OTel migration complete. Validate with:"
	@echo "  kubectl -n $(MONITORING_NS) get pods -l app.kubernetes.io/name=opentelemetry-collector"
	@echo "  kubectl -n $(MONITORING_NS) get daemonset otel-agent-agent"
	@echo "See YACE-DECISION.md and LOKI-DECISION.md for recorded decisions."

## --- LLM observability demo ------------------------------------------

.PHONY: setup-llm-secrets setup-llm-image setup-llm-ollama setup-llm-litellm setup-llm-app setup-llm-dashboard setup-llm-observability run-llm-scenarios

# Generates a random LiteLLM master key if one doesn't already exist.
# Never overwrites an existing secrets file.
setup-llm-secrets:
	@test -f app/llm-demo/secrets.yaml || ( \
		echo "apiVersion: v1" > app/llm-demo/secrets.yaml; \
		echo "kind: Secret" >> app/llm-demo/secrets.yaml; \
		echo "metadata:" >> app/llm-demo/secrets.yaml; \
		echo "  name: litellm-secrets" >> app/llm-demo/secrets.yaml; \
		echo "  namespace: $(MONITORING_NS)" >> app/llm-demo/secrets.yaml; \
		echo "type: Opaque" >> app/llm-demo/secrets.yaml; \
		echo "stringData:" >> app/llm-demo/secrets.yaml; \
		echo "  LITELLM_MASTER_KEY: \"sk-demo-$$(python3 -c 'import secrets; print(secrets.token_hex(16))')\"" >> app/llm-demo/secrets.yaml; \
		echo "  OPENAI_API_KEY: \"\"" >> app/llm-demo/secrets.yaml; \
		echo "  ANTHROPIC_API_KEY: \"\"" >> app/llm-demo/secrets.yaml; \
	)
	kubectl apply -f app/llm-demo/secrets.yaml

# Builds the demo app image and imports it directly into k3d's
# containerd -- no external registry needed for the local path.
setup-llm-image:
	docker build -t llm-demo:latest app/llm-demo
	k3d image import llm-demo:latest -c $(CLUSTER_NAME)-local

# Ollama + model pull, with a fallback direct pull if the in-manifest Job
# doesn't report complete in time.
setup-llm-ollama:
	kubectl apply -f app/llm-demo/ollama.yaml
	kubectl -n $(MONITORING_NS) rollout status deployment/ollama --timeout=180s
	kubectl -n $(MONITORING_NS) wait --for=condition=complete job/ollama-pull-model --timeout=600s || \
		kubectl -n $(MONITORING_NS) exec deploy/ollama -- ollama pull llama3.2:1b
	kubectl -n $(MONITORING_NS) exec deploy/ollama -- ollama list | grep -q "llama3.2:1b"

setup-llm-litellm:
	helm upgrade --install litellm-proxy oci://ghcr.io/berriai/litellm-helm -n $(MONITORING_NS) -f monitoring/chart-values/litellm.yaml --wait --timeout 5m

setup-llm-app:
	kubectl apply -f app/llm-demo/deployment.yaml
	kubectl -n $(MONITORING_NS) rollout status deployment/llm-demo --timeout=120s

setup-llm-dashboard:
	kubectl apply -f monitoring/dashboards/llm-dashboard.yaml

# Full LLM observability setup, in dependency order. Assumes
# migrate-to-otel has already run (needs svc/otel-gateway to exist).
setup-llm-observability: setup-llm-secrets setup-llm-image setup-llm-ollama setup-llm-litellm setup-llm-app setup-llm-dashboard
	@echo "LLM observability demo deployed. Check the 'LLM Observability (GenAI)' dashboard in Grafana."

run-llm-scenarios:
	bash scenarios/llm/run.sh both
