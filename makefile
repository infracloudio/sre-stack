help:
	@echo "EKS setup/deploy/cleanup commands:"
	@echo "	setup                               - End-to-end setup on EKS"
	@echo "	start-cluster                       - start EKS Cluster"
	@echo "	setup-cluster-autoscaler            - Setup node auto scaling"
	@echo "	setup-observability                 - Setup monitoring/observability"
	@echo "	setup-optional-otel                 - Setup OpenTelemetry"
	@echo "	setup-istio                         - Setup istio and ingress"
	@echo "	setup-dbs-rds-mysql                 - Setup RDS - mysql, documentdb"
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

include .env

REQUIRED_VARS := AWS_REGION CLUSTER_NAME RDS_MYSQL_DB_NAME AUTO_SCALING_GROUP_POLICY_NAME MONITORING_NS RABBITMQ_NS APP_NS RDS_MYSQL_DB_MASTER_PASSWORD APP_RELEASE_NAME APP_SETUP_TIMEOUT LOCAL_APP_SETUP_TIMEOUT APP_STACK STACK_MODE LOCAL_NODES INOTIFY_MAX_USER_INSTANCES INOTIFY_MAX_USER_WATCHES
AWS_ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text --no-cli-pager)
MYSQL_HOST=$(shell aws rds describe-db-instances --db-instance-identifier $(RDS_MYSQL_DB_NAME)  --region $(AWS_REGION) --query 'DBInstances[*].Endpoint.Address' --output text --no-cli-pager)
OBSERVABILITY_NODEGROUP_ROLE_NAME=$(shell eksctl get nodegroup --cluster $(CLUSTER_NAME) --region $(AWS_REGION) --output json | jq '.[] | select(.Name == "$(OBSERVABILITY_NODEGROUP_NAME)") | .NodeInstanceRoleARN | split("/") | .[1]')
ifeq ($(STACK_MODE),eks)
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
else 
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
endif

$(foreach var,$(REQUIRED_VARS),$(if $(value $(var)),,$(error $(var) is not set)))

setup:

ifeq ($(APP_STACK),hotrod)
setup: setup-cluster setup-cluster-autoscaler setup-istio setup-psql setup-prometheus-stack setup-otel setup-tempo setup-hotrod setup-gateway get-services-endpoint
else ifeq ($(APP_STACK),sre-stack)
setup: setup-cluster setup-cluster-autoscaler setup-yace-cloudwatch-policy setup-istio setup-psql setup-prometheus-stack setup-observability setup-caretta setup-tempo setup-beyla setup-dbs-rds-mysql setup-rabbitmq-operator setup-robot-shop setup-gateway get-services-endpoint
else ifeq ($(APP_STACK),all)
setup: setup-cluster setup-cluster-autoscaler setup-yace-cloudwatch-policy setup-istio setup-psql setup-prometheus-stack setup-observability setup-dbs-rds-mysql setup-rabbitmq-operator setup-robot-shop setup-otel setup-hotrod setup-gateway get-services-endpoint
else 
	@echo "Nothing to setup"
endif

setup-cluster:
	eksctl create cluster -f infra/eksctl.yaml

setup-cluster-autoscaler:
	eksctl utils associate-iam-oidc-provider \
	--region=$(AWS_REGION) --cluster $(CLUSTER_NAME) \
	--approve
	aws iam create-policy  \
	--policy-name $(AUTO_SCALING_GROUP_POLICY_NAME) \
	--policy-document file://./infra/asg-policy.json \
	--no-cli-pager
	eksctl create iamserviceaccount \
	--region=$(AWS_REGION) --name cluster-autoscaler \
	--namespace kube-system \
	--cluster $(CLUSTER_NAME) \
	--attach-policy-arn "arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(AUTO_SCALING_GROUP_POLICY_NAME)" \
	--approve \
	--override-existing-serviceaccounts
	kubectl apply -f infra/cluster-autoscale.yaml
	kubectl -n kube-system \
	annotate deployment.apps/cluster-autoscaler \
	cluster-autoscaler.kubernetes.io/safe-to-evict="false"

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
	helm upgrade --install tempo grafana/tempo --values ./monitoring/chart-values/tempo.yaml -n $(MONITORING_NS)

setup-caretta:
	helm repo add groundcover https://helm.groundcover.com/
	helm repo update
	helm upgrade --install caretta groundcover/caretta --values ./monitoring/chart-values/caretta.yaml --create-namespace -n $(MONITORING_NS)

setup-metric-server:
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/  && helm repo update
	helm upgrade --install metrics-server metrics-server/metrics-server --values ./monitoring/chart-values/metric-server.yaml -n $(MONITORING_NS) --create-namespace

setup-yace:
	aws iam create-policy  \
	--policy-name $(YACE_CLOUDWATCH_POLICY_NAME) \
	--policy-document file://./infra/yace-cloudwatch-policy.json \
	--no-cli-pager
	aws iam attach-role-policy --role-name $(OBSERVABILITY_NODEGROUP_ROLE_NAME) --policy-arn arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(YACE_CLOUDWATCH_POLICY_NAME)

	helm repo add yace https://nerdswords.github.io/helm-charts
	helm upgrade --install yace yace/yet-another-cloudwatch-exporter -f monitoring/chart-values/yace.yaml --set aws_region=$(AWS_REGION) --set db_name=$(RDS_MYSQL_DB_NAME) -n $(MONITORING_NS)

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
	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n $(APP_NS)


setup-keda:
	helm repo add kedacore https://kedacore.github.io/charts && helm repo update ; \
	helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --values ./infra/chart-values/keda-values.yaml --version 2.11.1 ;
	kubectl apply -f ./infra/keda-policy/scaled-obj-dispatch.yaml

setup-loadgen:
	kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f scenarios/load-gen/load.yaml

setup-optional-rmq-consumer-scaling: setup-keda setup-loadgen


get-services-endpoint:
ifeq ($(APP_STACK),hotrod)
	@echo "---------------------------- $(APP_STACK) services endpoint ----------------------------"
	@echo "----------------------------------------------------------------------------------------"
else ifeq ($(APP_STACK),sre-stack)
	@echo "---------------------------- $(APP_STACK) services endpoint ----------------------------"
	@echo "Visit Robot shop http://$(LB_ENDPOINT)"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else ifeq ($(APP_STACK),all)
	@echo "---------------------------- $(APP_STACK) services endpoint ----------------------------"
	@echo "----------------------------------------------------------------------------------------"
	@echo ""
	@echo "---------------------------- $(APP_STACK) services endpoint ----------------------------"
	@echo "Visit Robot shop http://$(LB_ENDPOINT)"
	@echo "Visit Grafana dashboard http://$(LB_ENDPOINT)/grafana"
	@echo "Visit Istio kiali http://$(LB_ENDPOINT)/kiali"
	@echo "----------------------------------------------------------------------------------------"
else 
	@echo "---------------------------- No services endpoint --------------------------------------"
endif

destroy-db-rds-mysql:
	./infra/scripts/dbs/rds/mysql/destroy.sh
	./infra/scripts/dbs/rds/sg-destroy.sh

destroy-istio-gateway:
	helm uninstall istio-ingressgateway -n istio-system 

destroy-loadgen:
	kubectl delete -f scenarios/load-gen/load.yaml

cleanup-cluster:
	eksctl delete cluster --region=$(AWS_REGION) --name=$(CLUSTER_NAME) --wait
	aws iam delete-policy --policy-arn arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(AUTO_SCALING_GROUP_POLICY_NAME)
	aws iam delete-policy --policy-arn arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(YACE_CLOUDWATCH_POLICY_NAME)

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

setup-local: setup-local-cluster setup-istio setup-local-o11y setup-robot-shop setup-gateway get-services-endpoint

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