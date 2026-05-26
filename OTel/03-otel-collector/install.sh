#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NS="observability"

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update >/dev/null

echo "==> Installing OTel Collector — gateway (Deployment)"
helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values gateway-values.yaml \
  --wait --timeout 5m

echo "==> Installing OTel Collector — agent (DaemonSet)"
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values agent-values.yaml \
  --wait --timeout 5m

echo
echo "Verify with:"
echo "  kubectl -n ${NS} get pods -l 'app.kubernetes.io/name=opentelemetry-collector'"
echo
echo "Smoke test (send one trace via OTLP HTTP to the gateway NodePort):"
cat <<'EOF'
  curl -s -X POST http://localhost:4318/v1/traces \
    -H 'Content-Type: application/json' \
    -d '{
      "resourceSpans": [{
        "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "smoke-test"}}]},
        "scopeSpans": [{
          "spans": [{
            "traceId": "00112233445566778899aabbccddeeff",
            "spanId":  "1122334455667788",
            "name":    "hello",
            "kind":    1,
            "startTimeUnixNano": "1700000000000000000",
            "endTimeUnixNano":   "1700000000100000000"
          }]
        }]
      }]
    }'
EOF
echo
echo "Then open Grafana → Tempo and search service.name=smoke-test."
echo "Next: ./04-logs-migration/apply.sh"
