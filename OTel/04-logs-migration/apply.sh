#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
NS="observability"

echo "==> Upgrading gateway with k8s_events receiver + Loki exporter"
helm upgrade otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values gateway-values.yaml \
  --wait --timeout 5m

echo "==> Upgrading agent with filelog receiver"
helm upgrade otel-agent open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values agent-values.yaml \
  --wait --timeout 5m

cat <<'EOF'

Verify:
  # 1) Agent pods should now mount /var/log/pods
  kubectl -n observability exec ds/otel-agent-agent -- ls /var/log/pods | head

  # 2) Open Grafana → Explore → Loki, query:
  #      {service_name=~".+"}     (any service)
  #      {k8s_namespace_name="observability"}

  # 3) Kubernetes events should appear with:
  #      {k8s_resource_name=~".+"}

If you had Promtail installed previously, retire it now:
  helm uninstall promtail -n observability   # only if it exists

Next: ./05-metrics-migration/apply.sh
EOF
