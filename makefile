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
	@echo "Azure (AKS) setup/cleanup commands:"
	@echo "	setup                             - Setup empty AKS cluster (cluster only)"
	@echo "	setup-aks-o11y                    - Setup monitoring/observability on AKS (Prometheus, Grafana, Loki, Alloy, routes)"
	@echo "	setup-loki-aks                    - Setup Loki (AKS-specific chart and values)"
	@echo "	setup-log-shipper-aks             - Setup the Grafana Alloy log shipper (AKS)"
	@echo "	setup-aks-o11y-routes             - Apply the observability routes and scrape configs (AKS)"
	@echo "	setup-kiali-aks                   - Setup Kiali (AKS, refuses when the mesh is not running)"
	@echo "	setup-optional-otel               - Setup OpenTelemetry (works on AKS too)"
	@echo "	cleanup                           - Cleanup AKS cluster"
	@echo ""
	@echo ""
	@echo "Utilities:"
	@echo " get-service-endpoints           - Print exposed service endpoints."
	@echo " install                         - Install all dev dependencies (lint tools, kubectl, helm, k3d, eksctl, aws/az CLI)"
	@echo " install-check                   - Report missing dev dependencies (no changes)"

include .env
BASE_SCRIPT_PATH := ./infra/scripts
CLUSTER_SCRIPT_PATH := $(BASE_SCRIPT_PATH)/cluster

# FR-006: refuse before scheduling anything when no supported provider is
# selected. A value set on the command line (`make STACK_MODE=... setup`)
# overrides .env, so the refusal also covers that path.
ifeq ($(filter $(STACK_MODE),eks local aks),)
$(error STACK_MODE is '$(STACK_MODE)' but must be eks | local | aks — set it in .env)
endif

REQUIRED_VARS := AWS_REGION CLUSTER_NAME RDS_MYSQL_DB_NAME AUTO_SCALING_GROUP_POLICY_NAME MONITORING_NS RABBITMQ_NS APP_NS RDS_MYSQL_DB_MASTER_PASSWORD APP_RELEASE_NAME APP_SETUP_TIMEOUT LOCAL_APP_SETUP_TIMEOUT APP_STACK STACK_MODE LOCAL_NODES INOTIFY_MAX_USER_INSTANCES INOTIFY_MAX_USER_WATCHES
# AWS-specific; commented out for now, returns in a future PR (see setup-robot-shop below)
# MYSQL_HOST=$(shell aws rds describe-db-instances --db-instance-identifier $(RDS_MYSQL_DB_NAME)  --region $(AWS_REGION) --query 'DBInstances[*].Endpoint.Address' --output text --no-cli-pager)
ifeq ($(STACK_MODE),eks)
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
else 
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
endif

$(foreach var,$(REQUIRED_VARS),$(if $(value $(var)),,$(error $(var) is not set)))

CHECK_ISTIO_GATEWAY_EXISTS := $(shell helm status istio-ingressgateway -n istio-system 2>/dev/null)
setup:

ifeq ($(STACK_MODE),aks)
# The aks lifecycle is the empty cluster only (FR-008): no Amazon helpers,
# no application or observability installs. The workloads come in later
# stories, exactly as the Azure spec scopes them.
setup: setup-cluster
# AWS/app-specific composite chains; commented out for now, return in a future PR
# else ifeq ($(APP_STACK),hotrod)
# setup: setup-cluster setup-cluster-autoscaler setup-istio setup-observability setup-hotrod setup-gateway get-service-endpoints
# else ifeq ($(APP_STACK),robot-shop)
# setup: setup-cluster setup-cluster-autoscaler setup-yace setup-istio setup-observability setup-db-rds-mysql setup-rabbitmq-operator setup-robot-shop setup-gateway get-service-endpoints
# else ifeq ($(APP_STACK),all)
# setup: setup-cluster setup-cluster-autoscaler setup-yace setup-istio setup-observability setup-db-rds-mysql setup-rabbitmq-operator setup-robot-shop setup-hotrod setup-gateway get-service-endpoints
else 
	@echo "Nothing to setup"
endif

setup-cluster:
	$(CLUSTER_SCRIPT_PATH)/setup-cluster.sh

# AWS-specific; commented out for now, returns in a future PR
# setup-cluster-autoscaler:
# 	$(CLUSTER_SCRIPT_PATH)/setup-cluster-autoscaler.sh

setup-istio:
ifeq ($(STACK_MODE),aks)
	$(CLUSTER_SCRIPT_PATH)/setup-istio-aks.sh
else
	helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update
	helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.17.2 --wait --timeout 2m0s
	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 --set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100 --wait --timeout 2m0s
	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 --wait --timeout 2m0s
endif

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

# AWS-specific (CloudWatch exporter); commented out for now, returns in a future PR
# setup-yace:
# 	$(CLUSTER_SCRIPT_PATH)/setup-yace.sh

setup-istio-o11y-addons:
	kubectl apply -f  monitoring/istio-observability-addons/

setup-dashboards:
ifeq ($(STACK_MODE),aks)
# RDS is AWS-only; on AKS apply every dashboard except rds.yaml (specs/002).
# The for-loop keeps the individual-file apply shape used elsewhere on AKS.
	@for _f in monitoring/dashboards/*.yaml; do \
		case "$$_f" in \
			*rds.yaml) echo "skipping $$(basename $$_f) (AWS RDS dashboard, not applicable on AKS)";; \
			*) kubectl apply -f "$$_f";; \
		esac; \
	done
else
	kubectl apply -f ./monitoring/dashboards/
endif

# setup-yace dropped here: AWS-specific, commented out below, returns in a future PR
setup-observability: setup-db-grafana-psql setup-kube-prometheus-stack setup-loki setup-beyla setup-tempo setup-caretta setup-metric-server setup-istio-o11y-addons setup-dashboards

setup-optional-otel:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update
ifeq ($(STACK_MODE),aks)
# AKS-specific values (specs/002 FR-010, corrected): the shared values pin an
# old collector image (0.94.0) while this target never pinned the chart, so
# the chart floated to latest and generated newer component names
# (file_log / k8s_attributes / otlp_grpc) plus removed config keys
# (memory_ballast, service.telemetry.metrics.address) that crash-loop that
# image. Chart 0.81.2 is the release whose app version is 0.94.0, so this pin
# keeps the existing values valid. EKS/local take the branch below unchanged
# (FR-017).
	helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector --version 0.81.2 --values ./infra/azure/chart-values/otel-collector.yaml -n $(MONITORING_NS)
else
	helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector --values ./monitoring/chart-values/otel-collector.yaml -n $(MONITORING_NS)
endif

# --- AKS observability (specs/002-azure-observability-stack) -------------------
# setup-aks-o11y chains the core monitoring stack; no setup-metric-server
# (AKS's built-in addon already serves the same API — installing a second one
# collides on ClusterRole system:metrics-server), no Tempo/Beyla/Caretta
# (out of scope). A missing mesh never blocks this chain (FR-013).
#
# setup-aks-o11y-routes applies only the four routing/scrape files the AKS
# path needs, individually — NOT the whole monitoring/istio-observability-
# addons/ folder (that shared apply stays EKS/local's). This coupling is
# recorded in docs/architectural-decisions.md (AD for story 002): a file
# added to that folder later does not automatically reach AKS.
setup-aks-o11y: setup-db-grafana-psql setup-kube-prometheus-stack setup-loki-aks setup-log-shipper-aks setup-aks-o11y-routes setup-dashboards

setup-loki-aks:
	helm repo add grafana-community https://grafana-community.github.io/helm-charts
	helm repo update
	helm upgrade --install loki grafana-community/loki --version 18.13.7 --values ./infra/azure/chart-values/loki.yaml -n $(MONITORING_NS) --create-namespace

setup-log-shipper-aks:
	bash $(CLUSTER_SCRIPT_PATH)/setup-log-shipper-aks.sh

setup-aks-o11y-routes:
	bash $(CLUSTER_SCRIPT_PATH)/setup-aks-o11y-routes.sh

# Separate from setup-aks-o11y on purpose (FR-013): it refuses when the mesh
# is not actually running, instead of failing the core stack.
setup-kiali-aks:
	bash $(CLUSTER_SCRIPT_PATH)/setup-kiali-aks.sh


# AWS-specific (RDS); commented out for now, returns in a future PR
# setup-db-rds-mysql:
# 	./infra/scripts/dbs/rds/mysql/create.sh

# App-specific (robot-shop messaging); commented out for now, returns in a future PR
# setup-rabbitmq-operator:
# 	helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
# 	helm upgrade --install rabbitmq-operator bitnami/rabbitmq-cluster-operator -f infra/chart-values/rabbitmq-values.yaml -n $(RABBITMQ_NS) --create-namespace --version 3.10.4 --wait

setup-robot-shop:
	kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace robot-shop istio-injection=enabled
	kubectl delete job mysql-seeder -n $(APP_NS) --ignore-not-found
ifeq ($(STACK_MODE),eks)
	helm upgrade --install $(APP_RELEASE_NAME) -n $(APP_NS) --create-namespace ./app/robot-shop/helm/ --set mysql_host=$(MYSQL_HOST) --set mysql_root_password=$(RDS_MYSQL_DB_MASTER_PASSWORD) --wait --timeout $(APP_SETUP_TIMEOUT)
else
	helm upgrade --install $(APP_RELEASE_NAME) -n $(APP_NS) --create-namespace ./app/robot-shop/helm/ --set stack_mode=$(STACK_MODE) --set mysql_root_password=$(RDS_MYSQL_DB_MASTER_PASSWORD) --wait --timeout $(LOCAL_APP_SETUP_TIMEOUT)
endif

setup-hotrod: setup-optional-otel
	kustomize build app/hotrod | kubectl apply -f -

setup-gateway:
	kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace hotrod --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n robot-shop
	kubectl apply -f ./app/hotrod/istio-gateway.yaml -n hotrod


# App-specific (robot-shop dispatch autoscaling); commented out for now, returns in a future PR
# setup-keda:
# 	helm repo add kedacore https://kedacore.github.io/charts && helm repo update ; \
# 	helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --values ./infra/chart-values/keda-values.yaml --version 2.11.1 ;
# 	kubectl apply -f ./infra/keda-policy/scaled-obj-dispatch.yaml

# App-specific (load generator); commented out for now, returns in a future PR
# setup-loadgen:
# 	kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
# 	kubectl apply -f scenarios/load-gen/load.yaml

# App-specific; commented out for now, returns in a future PR
# setup-optional-rmq-consumer-scaling: setup-keda setup-loadgen


get-service-endpoints:
ifeq ($(STACK_MODE),aks)
# AKS branch first (specs/002): the monitoring VirtualServices bind to the
# robotshop-gateway created only by the routing step (setup-gateway), so
# without it the URLs would print but not resolve (US1 scenario 5, FR-005).
	@if kubectl get gateway robotshop-gateway -n robot-shop >/dev/null 2>&1; then \
		echo "---------------------------- Azure AKS service endpoints -------------------------------"; \
		echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"; \
		echo "Visit Prometheus http://$(LB_ENDPOINT)/prometheus"; \
		echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"; \
		echo "-----------------------------------------------------------------------------------------"; \
	else \
		echo "---------------------------- Azure AKS service endpoints -------------------------------"; \
		echo "The monitoring stack is installed but its addresses are not reachable yet — the routing step hasn't run."; \
		echo "Run 'make setup-gateway' first, then 'make get-service-endpoints' again."; \
		echo "-----------------------------------------------------------------------------------------"; \
	fi
else ifeq ($(APP_STACK),hotrod)
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "Visit HotROD: curl -H \"Host: hotrod.demo.local\" http://$(LB_ENDPOINT)/"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else ifeq ($(APP_STACK),robot-shop)
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "Visit Robot shop http://$(LB_ENDPOINT)"
	@echo "Visit HotROD: curl -H \"Host: hotrod.demo.local\" http://$(LB_ENDPOINT)/"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else ifeq ($(APP_STACK),all)
	@echo "---------------------------- $(APP_STACK) service endpoints ----------------------------"
	@echo "Visit Robot shop http://$(LB_ENDPOINT)"
	@echo "Visit HotROD: curl -H \"Host: hotrod.demo.local\" http://$(LB_ENDPOINT)/"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else
	@echo "---------------------------- Non-existent APP_STACK --------------------------------------"
endif

# AWS-specific (RDS); commented out for now, returns in a future PR
# destroy-db-rds-mysql:
# 	./infra/scripts/dbs/rds/mysql/destroy.sh
# 	./infra/scripts/dbs/rds/sg-destroy.sh

destroy-istio-gateway:
ifeq ($(CHECK_ISTIO_GATEWAY_EXISTS),)
	@echo "istio ingress gateway does not exists"
else 
	helm uninstall istio-ingressgateway -n istio-system
endif

destroy-loadgen:
	kubectl delete -f scenarios/load-gen/load.yaml

# AWS-specific; commented out for now, returns in a future PR
# destroy-cluster-autoscaler:
# 	$(CLUSTER_SCRIPT_PATH)/destroy-cluster-autoscaler.sh

# AWS-specific; commented out for now, returns in a future PR
# destroy-yace:
# 	$(CLUSTER_SCRIPT_PATH)/destroy-yace.sh

ifeq ($(STACK_MODE),aks)
cleanup-istio:
	$(CLUSTER_SCRIPT_PATH)/cleanup-istio.sh
else
cleanup-istio:
	@echo "cleanup-istio is AKS-only; on EKS/local use destroy-istio-gateway"
endif

ifeq ($(STACK_MODE),aks)
cleanup-gateway:
	$(CLUSTER_SCRIPT_PATH)/cleanup-gateway.sh
else
cleanup-gateway:
	@echo "cleanup-gateway is AKS-only; nothing to do on EKS/local (see setup-gateway)"
endif

ifeq ($(STACK_MODE),aks)
cleanup-cluster:
	$(CLUSTER_SCRIPT_PATH)/cleanup-cluster.sh
else
# destroy-cluster-autoscaler / destroy-yace dropped here: AWS-specific, commented out above
cleanup-cluster:
	$(CLUSTER_SCRIPT_PATH)/cleanup-cluster.sh
endif


ifeq ($(STACK_MODE),aks)
# Azure cleanup is the cluster lifecycle only (FR-004): no gateway, RDS, or
# other Amazon-only teardown steps run before it.
cleanup: cleanup-cluster
else
# destroy-db-rds-mysql dropped here: AWS-specific, commented out above
cleanup: destroy-istio-gateway cleanup-cluster
endif

lint:
	@bash agent/hooks/check-hooks-enabled.sh
	@bash agent/hooks/check-secrets.sh $$(git ls-files)
	@bash agent/hooks/check-protected-paths.sh
	@bash agent/hooks/check-ratchets.sh
	@bash agent/hooks/lint-changed.sh $$(git ls-files)
	@helm lint app/robot-shop/helm --strict
	@bash agent/tests/azure/check-observability-placement.sh
	@bash agent/tests/azure/check-verify-observability-offline.sh
	@bash agent/hooks/check-speckit-version.sh
	@bash agent/tools/loom.sh --check

hooks:
	git config core.hooksPath .githooks
	@echo "pre-commit hooks enabled for this clone"

install:
	@bash infra/scripts/dev/install-deps.sh

install-check:
	@DRY_RUN=1 bash infra/scripts/dev/install-deps.sh

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

# setup-robot-shop dropped here: app-specific, commented out above
setup-local: setup-local-cluster setup-istio setup-local-o11y setup-gateway get-service-endpoints

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
# 	kubectl get svc -n litmus | grep "9091"
