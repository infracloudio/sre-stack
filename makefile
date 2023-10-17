help:
	@echo "Command can be used for setup/deploy app and tools:"
	@echo "	Run full setup via command:		make setup"
	@echo "	Or start EKS Cluster via:		make start-cluster"
	@echo "	Setup monitoring/observability via:	make setup-observability"
	@echo "	Setup istio and ingress via:		make setup-istio"
	@echo "	Setup APM via:				make setup-apm"
	@echo "	Deploy application via:			make deploy-app"
	@echo "	Setup kiali and jaeger via:		make setup-addons"
	@echo "	Setup Litmus-3 chaos tool via:		make setup-litmus"
	@echo "	Setup node auto scaling via:		make install-asg"
	@echo ""
	@echo "Command can be used for cleanup:"
	@echo "	Clenaup all via:			make cleanup-cluster"

setup: start-cluster setup-observability setup-istio deploy-app install-asg

start-cluster:
	eksctl create cluster -f infra/eksctl.yaml

setup-observability:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack --values ./monitoring/chart-values/prometheus-values.yaml -n monitoring --create-namespace --version 47.0.0
	helm upgrade --install loki grafana/loki-stack -n monitoring

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
	kubectl create namespace bookinfo-prod --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace bookinfo-prod istio-injection=enabled
	kubectl apply -f app/bookinfo.yaml -n bookinfo-prod
	kubectl apply -f infra/gateway.yaml -n bookinfo-prod
	kubectl apply -f app/virtual-services.yaml -n bookinfo-prod
	kubectl apply -f app/destination-rules.yaml -n bookinfo-prod

cleanup-cluster:
	eksctl utils associate-iam-oidc-provider \
    --region=us-east-1 --cluster eks-cluster \
    --approve
	aws iam delete-policy --policy-arn arn:aws:iam::813864300626:policy/k8s-asg-policy
	eksctl delete cluster --region=us-east-1 --name=eks-cluster --wait

setup-litmus:
	helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
	helm upgrade --install chaos litmuschaos/litmus --namespace=litmus --create-namespace --set portal.frontend.service.type=LoadBalancer
	kubectl get svc -n litmus | grep "9091"

install-asg:
	eksctl utils associate-iam-oidc-provider \
	--region=us-east-1 --cluster eks-cluster \
	--approve
	aws iam create-policy   \
	--policy-name k8s-asg-policy \
	--policy-document file://./infra/asg-policy.json
	eksctl create iamserviceaccount \
	--region=us-east-1 --name cluster-autoscaler \
	--namespace kube-system \
	--cluster eks-cluster \
	--attach-policy-arn "arn:aws:iam::813864300626:policy/k8s-asg-policy" \
	--approve \
	--override-existing-serviceaccounts
	kubectl apply -f infra/cluster-autoscale.yaml
	kubectl -n kube-system \
	annotate deployment.apps/cluster-autoscaler \
	cluster-autoscaler.kubernetes.io/safe-to-evict="false"
