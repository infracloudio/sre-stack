#!/bin/bash
set -euo pipefail

GIT_TLD=$(git rev-parse --show-toplevel)
source "${GIT_TLD}/.env"

# No-op placeholder for AKS. There are no app-specific Gateway/VirtualService resources
# to clean up on AKS yet (Robot Shop deployment is pending story #102). This script
# exists so the makefile target cleanup-gateway exists and is consistent with the
# pattern of cleanup-istio.

echo "Gateway cleanup: no-op for AKS (no app-specific resources to remove yet)"
exit 0
