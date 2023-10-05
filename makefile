help:
	@echo "Run: make setup"

setup: start-cluster setup-observability setup-istio

start-cluster:
	eksctl create cluster -f infra/eksctl.yaml

setup-observability:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update	
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack --values ./monitoring/chart-values/prometheus-values.yaml -n monitoring --create-namespace --version 47.0.0
	helm upgrade --install loki grafana/loki-stack -n monitoring

setup-istio:
	helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update
	helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.17.2 --wait --timeout 2m0s
	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 --set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100 --wait --timeout 2m0s
	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 --wait --timeout 2m0s
	kubectl label namespace sock-shop istio-injection=enabled

deploy-app:
	kubectl apply -f app/complete-demo.yaml

clenup-cluster:
	eksctl delete cluster --region=us-east-1 --name=eks-cluster --wait
