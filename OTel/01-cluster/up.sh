#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER_NAME="otel-lab"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists — skipping create."
else
  echo "==> Creating kind cluster '${CLUSTER_NAME}'"
  kind create cluster --config kind-cluster.yaml --wait 120s
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes -o wide

echo
echo "Next: ./02-lgtm-stack/install.sh"
