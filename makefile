help:
	@echo "Run: make setup"

setup: start-cluster setup-observability deploy-app setup-istio install-asg

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

setup-addons:
	kubectl apply -f  monitoring/istio-addons/

deploy-app:
	kubectl apply -f app/complete-demo.yaml
	kubectl apply -f infra/gateway.yaml
	kubectl apply -f infra/virtualservice.yaml

cleanup-cluster:
	eksctl utils associate-iam-oidc-provider \
    --region=us-east-1 --cluster eks-cluster \
    --approve
	aws iam delete-policy --policy-arn arn:aws:iam::813864300626:policy/k8s-asg-policy
	eksctl delete cluster --region=us-east-1 --name=eks-cluster --wait

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
