#!/bin/bash
# setup-log-shipper-aks.sh — install the AKS log shipper
# (specs/002-azure-observability-stack T007, FR-002).
#
# The grafana-community/loki chart (setup-loki-aks) bundles no log shipper,
# and the standalone promtail chart is deprecated — Grafana Alloy is the
# actively-maintained successor (research.md finding 13). Installs chart
# grafana/alloy pinned at 1.13.0 with infra/azure/chart-values/alloy.yaml:
# a DaemonSet tolerating every taint, pushing to http://loki:3100 (the flat
# Service name setup-loki-aks's values guarantee, finding 14).
# helm upgrade --install is idempotent by construction.

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_monitoring_ns="${MONITORING_NS:-monitoring}"

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "Installing the Grafana Alloy log shipper (chart 1.13.0) into namespace ${_monitoring_ns}..."
helm upgrade --install alloy grafana/alloy \
    --version 1.13.0 \
    --values ./infra/azure/chart-values/alloy.yaml \
    -n "${_monitoring_ns}"

echo "Log shipper installed."
