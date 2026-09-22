#!/bin/bash
set -euo pipefail

GIT_TLD=$(git rev-parse --show-toplevel)
source "${GIT_TLD}/.env"

echo "Cleaning up Istio from namespace ${ISTIO_NAMESPACE}..."

# Uninstall in reverse order of installation: gateway first, then control plane, then base
# This prevents CRD removal ordering issues.

for release in istio-ingressgateway istiod istio-base; do
    if helm status "${release}" -n "${ISTIO_NAMESPACE}" >/dev/null 2>&1; then
        echo "Uninstalling ${release}..."
        helm uninstall "${release}" -n "${ISTIO_NAMESPACE}" --wait
    else
        echo "${release} not found, skipping"
    fi
done

echo "Istio cleanup completed."
exit 0
