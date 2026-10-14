#!/bin/bash
# setup-aks-o11y-routes.sh — apply the AKS observability routing and scrape
# files (specs/002-azure-observability-stack T006, FR-005).
#
# Applies four unmodified files individually — the same files EKS/local
# already use via setup-istio-o11y-addons — rather than that whole-folder
# target (docs/architectural-decisions.md, story 002's ADR). The two routes
# need Istio's VirtualService type and the two monitors live in the
# istio-system namespace, so all four need the mesh installed (setup-istio),
# though not istiod actually running. When the type or the namespace is
# missing, none of the four is applied: the script says what is missing and
# exits 0 so the rest of setup-aks-o11y still runs (specs/005, FR-006). When
# kubectl itself fails, the script exits 1 rather than guess.
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

# No mesh, no routes: skip all four together (the monitors only scrape mesh
# components) and let the chain continue. --ignore-not-found makes "absent"
# an empty answer, so any kubectl failure (wrong context, expired
# credentials, API timeout) stops the script instead of passing for a
# cluster without the mesh.
_exists() {  # $1 kind, $2 name; prints the object name when it exists
    if ! kubectl get "$1" "$2" --ignore-not-found -o name; then
        echo "Could not check for $1 $2 (kubectl failed; see above). Check the current context and credentials, then re-run 'make setup-aks-o11y-routes'." >&2
        exit 1
    fi
}
_missing=""
_crd=$(_exists crd virtualservices.networking.istio.io)
if [ -z "${_crd}" ]; then
    _missing="no Istio VirtualService type"
else
    _ns=$(_exists ns istio-system)
    if [ -z "${_ns}" ]; then
        _missing="no istio-system namespace"
    fi
fi
if [ -n "${_missing}" ]; then
    echo "The service mesh is not installed (${_missing}), so the Grafana/Prometheus routes and the mesh scrape configs were skipped. Run 'make setup-istio', then 'make setup-aks-o11y-routes'."
    exit 0
fi

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
