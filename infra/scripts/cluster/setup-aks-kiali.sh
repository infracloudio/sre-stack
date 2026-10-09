#!/bin/bash
# setup-aks-kiali.sh — install the service mesh dashboard on AKS
# (specs/002-azure-observability-stack T011, FR-013, FR-018).
#
# A missing mesh never blocks the core stack (setup-aks-o11y): this script
# refuses on its own instead. It checks the mesh is actually running
# (helm status istiod -n istio-system) before applying anything, then applies
# the AKS-specific Kiali manifest — infra/azure/kiali/kiali.yaml, rendered
# from kiali-server 2.32.0 because the shared manifest's v1.63 crashes its
# graph API against Kubernetes 1.34's Endpoints API (specs/002 follow-up;
# EKS/local keep the shared v1.63 manifest via setup-istio-o11y-addons,
# FR-017). The shared kiali-vs.yaml (a hand-written VirtualService) is
# platform-agnostic and stays in use. kubectl apply is idempotent.

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_mesh_ns="${ISTIO_NAMESPACE:-istio-system}"

# --- gate: is the mesh actually running? (FR-013) -------------------------------
if ! helm status istiod -n "${_mesh_ns}" >/dev/null 2>&1; then
    echo "Cannot start: the service mesh is not running (no istiod found in namespace ${_mesh_ns})." >&2
    echo "Kiali needs the Istio mesh to show its traffic graph. Run 'make setup-istio' first, then try again." >&2
    echo "Nothing was applied." >&2
    exit 1
fi

echo "Mesh is running (istiod found in ${_mesh_ns}). Applying Kiali (v2.32.0)..."

_addons="monitoring/istio-observability-addons"

kubectl apply -f "infra/azure/kiali/kiali.yaml"
kubectl apply -f "${_addons}/kiali-vs.yaml"

echo "Kiali applied. The dashboard becomes reachable through the shared entry point once its pod is ready."
