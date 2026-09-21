#!/bin/bash
set -euo pipefail

GIT_TLD=$(git rev-parse --show-toplevel)
source "${GIT_TLD}/.env"

echo "Setting up Istio ${ISTIO_VERSION} on AKS in namespace ${ISTIO_NAMESPACE}..."

# Add Helm repo
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Install istio-base (cluster-scoped CRDs)
if helm status istio-base -n "${ISTIO_NAMESPACE}" >/dev/null 2>&1; then
    echo "istio-base already exists, skipping install"
else
    echo "Installing istio-base ${ISTIO_VERSION}..."
    helm upgrade --install istio-base istio/base \
        -n "${ISTIO_NAMESPACE}" \
        --create-namespace \
        --version "${ISTIO_VERSION}" \
        --wait \
        --timeout "${HELM_TIMEOUT}"
fi

# Install istiod (control plane)
if helm status istiod -n "${ISTIO_NAMESPACE}" >/dev/null 2>&1; then
    echo "istiod already exists, skipping install"
else
    echo "Installing istiod ${ISTIO_VERSION}..."
    helm upgrade --install istiod istio/istiod \
        -n "${ISTIO_NAMESPACE}" \
        --version "${ISTIO_VERSION}" \
        --wait \
        --timeout "${HELM_TIMEOUT}"
fi

# Install istio-ingressgateway (gateway chart)
if helm status istio-ingressgateway -n "${ISTIO_NAMESPACE}" >/dev/null 2>&1; then
    echo "istio-ingressgateway already exists, skipping install"
else
    echo "Installing istio-ingressgateway ${ISTIO_VERSION}..."
    helm upgrade --install istio-ingressgateway istio/gateway \
        -n "${ISTIO_NAMESPACE}" \
        --version "${ISTIO_VERSION}" \
        --wait \
        --timeout "${HELM_TIMEOUT}"
fi

echo "Istio setup completed successfully."
