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
# 	kubectl get svc -n litmus | grep "9091"