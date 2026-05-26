#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NS="observability"

echo "==> Adding helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

echo "==> Ensuring namespace ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

echo "==> Installing kube-prometheus-stack"
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace "${NS}" \
  --values prometheus-values.yaml \
  --wait --timeout 10m

echo "==> Installing Loki (single-binary)"
helm upgrade --install loki grafana/loki \
  --namespace "${NS}" \
  --values loki-values.yaml \
  --wait --timeout 10m

echo "==> Installing Tempo"
helm upgrade --install tempo grafana/tempo \
  --namespace "${NS}" \
  --values tempo-values.yaml \
  --wait --timeout 10m

echo
echo "==> Done. Grafana → http://localhost:3000  (admin / admin)"
echo "Next: ./03-otel-collector/install.sh"
