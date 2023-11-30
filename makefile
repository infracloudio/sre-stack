help:
	@echo "Command can be used for setup/deploy app and tools:"
	@echo "	Run full setup via command:		make setup"
	@echo "	Or start EKS Cluster via:		make start-cluster"
	@echo "	Setup node auto scaling via:		make setup-cluster-autoscaler"
	@echo "	Setup monitoring/observability via:	make setup-observability"
	@echo "	Setup istio and ingress via:		make setup-istio"
	@echo "	Setup RDS - mysql, documentdb:		make setup-dbs-rds"
	@echo "	Setup rabbitmq-operator:			make setup-rabbitmq-operator"
	@echo "	Deploy application via:			make setup-app"
	@echo "	Setup Ingress gateway:		make setup-gateway"
	@echo "	Setup kiali and jaeger via:		make setup-istio-observability-addons"
	@echo ""
	@echo "Command can be used for cleanup:"
	@echo "	Clenaup cluster via:			make cleanup-cluster"
	@echo "	Clenaup all via:			make cleanup"

setup: setup-cluster setup-cluster-autoscaler setup-istio setup-observability setup-dbs-rds setup-rabbitmq-operator setup-app setup-gateway setup-keda

cleanup: destroy-istio-gateway destroy-dbs-rds cleanup-cluster

setup-cluster:
	eksctl create cluster -f infra/eksctl.yaml

setup-cluster-autoscaler:
	eksctl utils associate-iam-oidc-provider \
	--region=us-east-1 --cluster prod-eks-cluster \
	--approve
	aws iam create-policy  \
	--policy-name k8s-asg-policy \
	--policy-document file://./infra/asg-policy.json
	eksctl create iamserviceaccount \
	--region=us-east-1 --name cluster-autoscaler \
	--namespace kube-system \
	--cluster prod-eks-cluster \
	--attach-policy-arn "arn:aws:iam::813864300626:policy/k8s-asg-policy" \
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
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack --values ./monitoring/chart-values/prometheus-values.yaml -n monitoring --create-namespace --version 52.0.0
	helm upgrade --install loki grafana/loki-stack -n monitoring --create-namespace
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/  && helm repo update
	helm upgrade --install metrics-server metrics-server/metrics-server --values ./monitoring/chart-values/metric-server.yaml -n monitoring --create-namespace
	helm repo add yace https://nerdswords.github.io/helm-charts
	helm upgrade --install yace yace/yet-another-cloudwatch-exporter -f monitoring/chart-values/yace.yaml -n monitoring
	kubectl apply -f  monitoring/istio-observability-addons/
	kubectl apply -f ./monitoring/dashboards/

setup-db-rds-mysql:
	./infra/scripts/dbs/rds/mysql/create.sh

setup-db-rds-documentdb:
	./infra/scripts/dbs/rds/documentdb/create.sh

setup-dbs-rds: setup-db-rds-mysql setup-db-rds-documentdb

setup-rabbitmq-operator:
	helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
	helm upgrade --install rabbitmq-operator bitnami/rabbitmq-cluster-operator -f infra/chart-values/rabbitmq-values.yaml -n rabbitmq-operator --create-namespace --version 3.10.4 --wait

setup-app:
	make setup-rabbitmq-operator
	make setup-loadgen
	kubectl create namespace prod-robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace prod-robot-shop istio-injection=enabled
	helm upgrade --install roboshop -n prod-robot-shop --create-namespace ./app/robot-shop/helm/ --wait --timeout 2m0s

setup-loadgen:
	kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f scenarios/load-gen/load.yaml

setup-gateway:
	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n prod-robot-shop

setup-keda:
	helm repo add kedacore https://kedacore.github.io/charts && helm repo update ; \
	helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --values ./infra/chart-values/keda-values.yaml --version 2.11.1 ; \
	kubectl apply -f infra/keda-policy/scaled-obj-ratings.yaml

destroy-db-rds-mysql:
	./infra/scripts/dbs/rds/mysql/destroy.sh

destroy-db-rds-documentdb:
	./infra/scripts/dbs/rds/documentdb/destroy.sh

destroy-db-rds-sg:
	./infra/scripts/dbs/rds/destroy-sg.sh

destroy-istio-gateway:
	helm uninstall istio-ingressgateway -n istio-system 

destroy-dbs-rds: destroy-db-rds-mysql destroy-db-rds-documentdb destroy-db-rds-sg

cleanup-cluster:
	eksctl delete cluster --region=us-east-1 --name=prod-eks-cluster --wait
	aws iam delete-policy --policy-arn arn:aws:iam::813864300626:policy/k8s-asg-policy


## TBD integrations
#	@echo "	Setup Litmus-3 chaos tool via:		make setup-litmus"
# @echo "	Setup APM via:				make setup-apm"

# setup-apm:
# 	helm repo add signoz https://charts.signoz.io && helm repo updates
# 	helm upgrade --install install apm-platform signoz/signoz -n monitoring --create-namespace
# 	kubectl get svc svc/apm-platform-frontend -n monitoring | grep "3301"

# setup-litmus:
# 	helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
# 	helm upgrade --install chaos litmuschaos/litmus --namespace=litmus --create-namespace --set portal.frontend.service.type=LoadBalancer
# 	kubectl get svc -n litmus | grep "9091"