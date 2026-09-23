#!/bin/bash
set -euo pipefail

GIT_TLD=$(git rev-parse --show-toplevel)
source "${GIT_TLD}/.env"

kubectl apply -f app/robot-shop/Istio/gateway.yaml -n robot-shop
kubectl apply -f app/hotrod/istio-gateway.yaml -n hotrod
