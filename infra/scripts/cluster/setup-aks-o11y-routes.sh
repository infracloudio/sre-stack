#!/bin/bash
# setup-aks-o11y-routes.sh — apply the AKS observability routing and scrape
# files (specs/002-azure-observability-stack T006, FR-005).
#
# Applies four unmodified files individually — the same files EKS/local
# already use via setup-istio-o11y-addons — rather than that whole-folder
# target (docs/architectural-decisions.md, story 002's ADR). These four need
# only Istio's CRDs (already installed by setup-istio), not istiod actually
# running, so they ride with the core stack, ungated by mesh readiness.
# kubectl apply is idempotent by construction; safe to re-run.

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_addons=monitoring/istio-observability-addons

_file() {  # $1 file basename
    printf '%s/%s\n' "${_addons}" "$1"
}

# The four files the AKS path applies, individually.
_files=(
    "$(_file grafana-vs.yaml)"
    "$(_file prometheus-vs.yaml)"
    "$(_file istio-podmonitor.yaml)"
    "$(_file istio-servicemonitor.yaml)"
)

echo "Applying the AKS observability routes and scrape configs (the files carry their own namespaces: monitoring, istio-system)..."

# --dry-run (when given) proves the files parse and apply without touching
# the cluster; real runs apply each file individually. Every manifest names
# its own namespace (monitoring / istio-system), so no -n is passed.
_dry_run=""
if [ "${1:-}" = "--dry-run" ]; then
    _dry_run="--dry-run=client"
fi

_rc=0
for _f in "${_files[@]}"; do
    kubectl apply ${_dry_run} -f "${_f}" || _rc=1
done

if [ "${_rc}" -ne 0 ]; then
    echo "One or more files failed to apply. Nothing was deleted; re-run to retry." >&2
    exit 1
fi

echo "Observability routes applied."
