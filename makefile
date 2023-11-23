help:
	@echo "Command can be used for setup/deploy app and tools:"
	@echo "	Run full setup via command:		make setup"
	@echo "	Or start EKS Cluster via:		make start-cluster"
	@echo "	Setup node auto scaling via:		make install-asg"
	@echo "	Setup monitoring/observability via:	make setup-observability"
	@echo "	Setup istio and ingress via:		make setup-istio"
	@echo "	Deploy application via:			make deploy-app"
	@echo "	Setup Ingress gateway:		make setup-gateway"
	@echo "	Setup kiali and jaeger via:		make setup-addons"
	@echo "	Setup Litmus-3 chaos tool via:		make setup-litmus"
	@echo "	Setup APM via:				make setup-apm"
	@echo ""
	@echo "Command can be used for cleanup:"
	@echo "	Clenaup all via:			make cleanup-cluster"

setup: start-cluster install-asg setup-observability setup-istio deploy-app setup-gateway setup-addons

start-cluster:
	eksctl create cluster -f infra/eksctl.yaml

setup-observability:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack --values ./monitoring/chart-values/prometheus-values.yaml -n monitoring --create-namespace --version 52.0.0
	kubectl apply -f ./monitoring/istio-addons/prometheus-vs.yaml
	kubectl apply -f ./monitoring/istio-addons/grafana-vs.yaml
	helm upgrade --install loki grafana/loki-stack -n monitoring --create-namespace
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/  && helm repo update
	helm upgrade --install metrics-server metrics-server/metrics-server --values ./monitoring/chart-values/metric-server.yaml -n monitoring --create-namespace

setup-apm:
	helm repo add signoz https://charts.signoz.io && helm repo updates
	helm upgrade --install install apm-platform signoz/signoz -n monitoring --create-namespace
	kubectl get svc svc/apm-platform-frontend -n monitoring | grep "3301"

setup-istio:
	helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update
	helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.17.2 --wait --timeout 2m0s
	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 --set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100 --wait --timeout 2m0s
	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 --wait --timeout 2m0s

setup-addons:
	kubectl apply -f  monitoring/istio-addons/

deploy-app:
	kubectl create namespace prod-robot-shop --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace prod-robot-shop istio-injection=enabled
	helm upgrade --install roboshop -n prod-robot-shop --create-namespace ./app/robot-shop/helm/ --wait --timeout 1m0s

setup-gateway:
	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n prod-robot-shop

setup-keda:
	helm repo add kedacore https://kedacore.github.io/charts && helm repo update ; \
	helm upgrade --install keda kedacore/keda --namespace keda --create-namespace --values ./infra/chart-values/keda-values.yaml --version 2.11.1 ; \
	kubectl apply -f infra/keda-policy/scaled-obj-ratings.yaml

cleanup-cluster:
	eksctl delete cluster --region=us-east-1 --name=prod-eks-cluster --wait
	aws iam delete-policy --policy-arn arn:aws:iam::813864300626:policy/k8s-asg-policy

setup-litmus:
	helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
	helm upgrade --install chaos litmuschaos/litmus --namespace=litmus --create-namespace --set portal.frontend.service.type=LoadBalancer
	kubectl get svc -n litmus | grep "9091"

install-asg:
	eksctl utils associate-iam-oidc-provider \
	--region=us-east-1 --cluster prod-eks-cluster \
	--approve
	aws iam create-policy   \
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
