#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
NS="observability"

echo "==> Upgrading gateway with k8s_cluster + prometheusremotewrite"
helm upgrade otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values gateway-values.yaml \
  --wait --timeout 5m

echo "==> Upgrading agent with hostmetrics + kubeletstats"
helm upgrade otel-agent open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values agent-values.yaml \
  --wait --timeout 5m

cat <<'EOF'

Verify in Grafana → Explore → Prometheus:
  # node metrics from hostmetricsreceiver
  system_cpu_load_average_1m
  system_memory_usage_bytes{state="used"}

  # kubelet pod/container metrics
  k8s_pod_cpu_utilization
  k8s_container_memory_usage

  # cluster receiver
  k8s_node_condition_ready
  k8s_pod_phase

Next: ./06-validation/deploy-demo.sh
EOF
