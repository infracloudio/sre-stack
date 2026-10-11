#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
NS="observability"

helm repo add nerdswords https://nerdswords.github.io/helm-charts >/dev/null
helm repo update >/dev/null

echo "==> Installing YACE (writes directly to Prometheus via ServiceMonitor)"
helm upgrade --install yace nerdswords/yet-another-cloudwatch-exporter \
  --namespace "${NS}" \
  --values yace-values.yaml \
  --wait --timeout 5m

echo "Done. CloudWatch metrics will appear in Prometheus tagged with the"
echo "YACE job labels. Collector configs need no changes for this path."
