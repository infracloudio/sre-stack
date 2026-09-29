#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
NS="observability"

if ! kubectl -n "${NS}" get secret otel-aws >/dev/null 2>&1; then
  echo "Create the otel-aws Secret first (see overlay file header)." >&2
  exit 1
fi

echo "==> Upgrading gateway with awscloudwatchreceiver"
helm upgrade otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  -f ../../05-metrics-migration/gateway-values.yaml \
  -f gateway-overlay-values.yaml \
  --wait --timeout 5m

echo "Done. AWS metrics now flow through the collector — apply k8sattributes,"
echo "redaction, and routing uniformly with the rest of the signals."
