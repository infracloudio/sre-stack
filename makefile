help:
	@echo "Command can be used for setup/deploy app and tools:"
	@echo "	Run full setup via command:		make setup"
	@echo "	Or start EKS Cluster via:		make start-cluster"
	@echo "	Setup node auto scaling via:		make setup-cluster-autoscaler"
	@echo "	Setup monitoring/observability via:	make setup-observability"
	@echo "	Setup istio and ingress via:		make setup-istio"
	@echo "	Setup RDS - mysql, documentdb:		make setup-dbs-rds"
	@echo "	Setup rabbitmq-operator:			make setup-rabbitmq-operator"
	@echo "	Deploy application via:			make setup-robot-shop"
	@echo "	Setup Ingress gateway:		make setup-gateway"
	@echo "	Setup kiali and jaeger via:		make setup-istio-observability-addons"
	@echo ""
	@echo "Command can be used for cleanup:"
	@echo "	Clenaup cluster via:			make cleanup-cluster"
	@echo "	Clenaup all via:			make cleanup"

include .env

REQUIRED_VARS := AWS_REGION CLUSTER_NAME RDS_MYSQL_DB_NAME AUTO_SCALING_GROUP_POLICY_NAME MONITORING_NS RABBITMQ_NS APP_NS RDS_MYSQL_DB_MASTER_PASSWORD APP_RELEASE_NAME APP_SETUP_TIMEOUT APP_STACK
AWS_ACCOUNT_ID=$(shell aws sts get-caller-identity --query "Account" --output text --no-cli-pager)
MYSQL_HOST=$(shell aws rds describe-db-instances --db-instance-identifier $(RDS_MYSQL_DB_NAME)  --region $(AWS_REGION) --query 'DBInstances[*].Endpoint.Address' --output text --no-cli-pager)
OBSERVABILITY_NODEGROUP_ROLE_NAME=$(shell eksctl get nodegroup --cluster $(CLUSTER_NAME) --region $(AWS_REGION) --output json | jq '.[] | select(.Name == "$(OBSERVABILITY_NODEGROUP_NAME)") | .NodeInstanceRoleARN | split("/") | .[1]')
LB_ENDPOINT=$(shell kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

$(foreach var,$(REQUIRED_VARS),$(if $(value $(var)),,$(error $(var) is not set)))

setup:

ifeq ($(APP_STACK),hotrod)
setup: setup-cluster setup-cluster-autoscaler setup-istio setup-psql setup-prometheus-stack setup-otel setup-tempo setup-hotrod setup-gateway get-services-endpoint
else ifeq ($(APP_STACK),sre-stack)
setup: setup-cluster setup-cluster-autoscaler setup-yace-cloudwatch-policy setup-istio setup-psql setup-prometheus-stack setup-observability setup-tempo setup-beyla setup-dbs-rds setup-rabbitmq-operator setup-robot-shop setup-gateway get-services-endpoint
else ifeq ($(APP_STACK),all)
setup: setup-cluster setup-cluster-autoscaler setup-yace-cloudwatch-policy setup-istio setup-psql setup-prometheus-stack setup-observability setup-dbs-rds setup-rabbitmq-operator setup-robot-shop setup-otel setup-hotrod setup-gateway get-services-endpoint
else 
	@echo "Nothing to setup"
endif

optional-setup: setup-keda setup-loadgen

cleanup: destroy-istio-gateway destroy-dbs-rds cleanup-cluster

setup-cluster:
	eksctl create cluster -f infra/eksctl.yaml

setup-yace-cloudwatch-policy:
	aws iam create-policy  \
	--policy-name $(YACE_CLOUDWATCH_POLICY_NAME) \
	--policy-document file://./infra/yace-cloudwatch-policy.json \
	--no-cli-pager
	aws iam attach-role-policy --role-name $(OBSERVABILITY_NODEGROUP_ROLE_NAME) --policy-arn arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(YACE_CLOUDWATCH_POLICY_NAME)

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

setup-observability:
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install loki grafana/loki-stack -n $(MONITORING_NS) --create-namespace --values ./monitoring/chart-values/loki.yaml
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/  && helm repo update
	helm upgrade --install metrics-server metrics-server/metrics-server --values ./monitoring/chart-values/metric-server.yaml -n $(MONITORING_NS) --create-namespace
	helm repo add yace https://nerdswords.github.io/helm-charts
	helm upgrade --install yace yace/yet-another-cloudwatch-exporter -f monitoring/chart-values/yace.yaml --set aws_region=$(AWS_REGION) --set db_name=$(RDS_MYSQL_DB_NAME) -n $(MONITORING_NS)
	kubectl apply -f  monitoring/istio-observability-addons/
	kubectl apply -f ./monitoring/dashboards/

setup-prometheus-stack:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack --values ./monitoring/chart-values/prometheus-values.yaml -n $(MONITORING_NS) --create-namespace --version 52.0.0

setup-otel:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update
	helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector --values ./monitoring/chart-values/otel-collector.yaml -n $(MONITORING_NS)
	
setup-tempo:
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install tempo grafana/tempo --values ./monitoring/chart-values/tempo.yaml -n $(MONITORING_NS)

setup-beyla:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f monitoring/beyla -n $(MONITORING_NS)

setup-caretta:
	helm repo add groundcover https://helm.groundcover.com
	helm repo update
	helm upgrade --install caretta groundcover/caretta --values ./monitoring/chart-values/caretta.yaml --create-namespace -n $(MONITORING_NS)

setup-db-rds-mysql:
	./infra/scripts/dbs/rds/mysql/create.sh

setup-db-rds-documentdb:
	./infra/scripts/dbs/rds/documentdb/create.sh

setup-dbs-rds: setup-db-rds-mysql

setup-rabbitmq-operator:
	helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
	helm upgrade --install rabbitmq-operator bitnami/rabbitmq-cluster-operator -f infra/chart-values/rabbitmq-values.yaml -n $(RABBITMQ_NS) --create-namespace --version 3.10.4 --wait

setup-robot-shop:
	kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace robot-shop istio-injection=enabled
	helm upgrade --install $(APP_RELEASE_NAME) -n $(APP_NS) --create-namespace ./app/robot-shop/helm/ --set mysql_host=$(MYSQL_HOST) --set mysql_password=$(RDS_MYSQL_DB_MASTER_PASSWORD) --wait --timeout $(APP_SETUP_TIMEOUT)

setup-hotrod:
	kustomize build app/hotrod | kubectl apply -f -	

setup-gateway:
	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n $(APP_NS)

setup-keda:
	helm repo add kedacore https://kedacore.github.io/charts && helm repo update ; \
	helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --values ./infra/chart-values/keda-values.yaml --version 2.11.1 ;

setup-loadgen:
	kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f scenarios/load-gen/load.yaml

setup-psql:
	kubectl create ns $(MONITORING_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f monitoring/grafana-postgres/statefulset.yaml
	kubectl wait --for=condition=ready pod -l app=postgresql --timeout=300s -n $(MONITORING_NS)
	kubectl apply -f monitoring/grafana-postgres/job.yaml

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

destroy-db-rds-documentdb:
	./infra/scripts/dbs/rds/documentdb/destroy.sh

destroy-db-rds-sg:
	./infra/scripts/dbs/rds/sg-destroy.sh

destroy-istio-gateway:
	helm uninstall istio-ingressgateway -n istio-system 

destroy-dbs-rds: destroy-db-rds-mysql destroy-db-rds-sg

destroy-loadgen:
	kubectl delete -f scenarios/load-gen/load.yaml

cleanup-cluster:
	eksctl delete cluster --region=$(AWS_REGION) --name=$(CLUSTER_NAME) --wait
	aws iam delete-policy --policy-arn arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(AUTO_SCALING_GROUP_POLICY_NAME)
	aws iam delete-policy --policy-arn arn:aws:iam::$(AWS_ACCOUNT_ID):policy/$(YACE_CLOUDWATCH_POLICY_NAME)

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