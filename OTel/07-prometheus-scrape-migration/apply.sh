#!/usr/bin/env bash
# Step 07 — migrate Prometheus scraping into the collector.
#
# IMPORTANT: this step does NOT stop Prometheus from scraping. Both Prometheus
# AND the collector will scrape simultaneously until you narrow the
# ServiceMonitor selector on ONE side (or the other) to avoid duplicate
# series. That's intentional — you verify the collector is producing the
# right series before turning Prometheus scraping off.
#
# Recommended phasing:
#   1. Apply this file (collector starts scraping every ServiceMonitor).
#   2. In Grafana, compare a metric like `up{job="kps-kube-state-metrics"}`
#      — you should see two series, one from each scraper.
#   3. Drop one ServiceMonitor from Prometheus (set scrape selector or label
#      it explicitly so Prometheus ignores it).
#   4. Repeat per ServiceMonitor until Prometheus is just a store.
set -euo pipefail
cd "$(dirname "$0")"
NS="observability"

echo "==> Upgrading gateway with prometheusreceiver + target-allocator"
helm upgrade otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "${NS}" \
  --values gateway-values.yaml \
  --wait --timeout 5m

echo
echo "Verify:"
echo "  # target-allocator should have discovered ServiceMonitors:"
echo "  kubectl -n ${NS} port-forward svc/otel-gateway-targetallocator 8080:80"
echo "  curl -s http://localhost:8080/scrape_configs | jq 'keys'"
echo
echo "  # in Grafana, look for duplicate \`up\` series (one from kps-prometheus"
echo "  # scraping, one from the collector). Once you're happy, narrow the"
echo "  # Prometheus serviceMonitorSelector to phase scraping out."
