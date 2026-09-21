#!/bin/bash
set -euo pipefail

GIT_TLD=$(git rev-parse --show-toplevel)
source "${GIT_TLD}/.env"

# No-op placeholder for AKS. Robot Shop deployment (and its Gateway/VirtualService routing)
# is out of scope for this story (see story #102). The setup-gateway target is extended
# to support STACK_MODE=aks with this script so that the makefile target exists and
# matches the pattern of setup-istio, but creates no resources on AKS yet.

echo "Gateway setup: no-op for AKS (Robot Shop deployment pending story #102)"
exit 0
