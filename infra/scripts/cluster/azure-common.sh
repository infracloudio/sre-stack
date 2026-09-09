#!/bin/bash
# azure-common.sh — shared settings, pre-checks, and generated names for the
# STACK_MODE=aks path (specs/001-azure-aks-setup, T005).
#
# Sourced by the aks setup/cleanup/verify scripts; never executed directly.
# Read-only: it only inspects Azure. Every refusal prints what is wrong, what
# to do, and that nothing was created — before anything is created or deleted
# (contracts/azure-cli-contract.md §3).
#
# Exports for callers after success:
#   AZURE_LOCATION         resolved location (setting or the eastus2 fallback)
#   AZURE_RESOURCE_GROUP   generated resource group name <name>-aks-<code>
#   AZURE_CLUSTER_NAME     generated cluster name sre-stack-<code>

# Double-source guard: the pre-checks are slow; run them once per script run.
if [ -n "${AZURE_COMMON_LOADED:-}" ]; then
    return 0
fi

# --- repo root + settings ---------------------------------------------------
_azure_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_azure_repo_root}" ]; then
    _azure_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_azure_repo_root}/.env"

# Bump only when the pool table in data-model.md §3 changes; the hash code in
# the generated names reflects this, so a bump means a fresh cluster.
CLUSTER_SHAPE_VERSION="1"

_azure_refuse() {
    echo "Cannot start: $1" >&2
    echo "$2" >&2
    echo "Nothing was created." >&2
    return 1
}

# --- STACK_MODE gate (FR-006) ------------------------------------------------
case "${STACK_MODE:-}" in
    aks) ;;
    eks|local)
        echo "Cannot start: the Azure helper only works with STACK_MODE=aks." >&2
        echo "Valid choices: eks | local | aks. Nothing was created." >&2
        return 1
        ;;
    *)
        echo "Cannot start: STACK_MODE is '${STACK_MODE:-}' but must be eks | local | aks." >&2
        echo "Set it in .env, then try again. Nothing was created." >&2
        return 1
        ;;
esac

# --- CLI presence and version -------------------------------------------------
if ! command -v az >/dev/null 2>&1; then
    echo "Cannot start: the az command was not found." >&2
    echo "Install the Azure CLI, then try again. Nothing was created." >&2
    return 1
fi
_azure_cli_version=$(az version --query azure-cli --output tsv 2>/dev/null)
if [ -z "${_azure_cli_version}" ]; then
    _azure_cli_version=$(az --version 2>/dev/null | head -n 1 | awk '{print $2}')
fi
echo "az CLI version: ${_azure_cli_version:-unknown}"
_azure_cli_minimum="2.87.0"
_azure_cli_oldest=$(printf '%s\n%s\n' "${_azure_cli_version:-0}" "${_azure_cli_minimum}" | sort -V | head -n 1)
if [ "${_azure_cli_oldest}" != "${_azure_cli_minimum}" ]; then
    echo "WARNING: az CLI ${_azure_cli_version} is older than the tested minimum ${_azure_cli_minimum}." >&2
    echo "Update the Azure CLI; these checks were proven on ${_azure_cli_minimum} and newer only." >&2
fi

# --- pre-check 1: signed in ---------------------------------------------------
if ! az account show --output none 2>/dev/null; then
    echo "Cannot start: no Azure sign-in found." >&2
    echo "Run 'az login' first, then try again. Nothing was created." >&2
    return 1
fi

# --- pre-check 2: subscription ------------------------------------------------
if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
    if ! az account set --subscription "${AZURE_SUBSCRIPTION_ID}" 2>/dev/null; then
        echo "Cannot start: subscription '${AZURE_SUBSCRIPTION_ID}' was not found or is not accessible." >&2
        echo "Check AZURE_SUBSCRIPTION_ID in .env (or leave it empty to use the signed-in subscription). Nothing was created." >&2
        return 1
    fi
fi

# --- pre-check 3: location is real ---------------------------------------------
# The eastus2 fallback applies only when AZURE_LOCATION is empty (FR-010).
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"
if ! az account list-locations --query "[].name" --output tsv 2>/dev/null | grep -qx "${AZURE_LOCATION}"; then
    echo "Cannot start: location '${AZURE_LOCATION}' is not a real Azure location for this account." >&2
    echo "Set AZURE_LOCATION in .env to a listed one (az account list-locations --query \"[].name\" -o tsv). Nothing was created." >&2
    return 1
fi

# --- pre-check 4: every machine size offered there ------------------------------
# No silent swap, no automatic move to another region (data-model §1).
_azure_vm_sizes=$(az vm list-skus --location "${AZURE_LOCATION}" --all --query "[].name" --output tsv 2>/dev/null)
for _azure_size in Standard_D2s_v5 Standard_D4s_v5 Standard_F4s_v2; do
    if ! printf '%s\n' "${_azure_vm_sizes}" | grep -qx "${_azure_size}"; then
        echo "Cannot start: machine size ${_azure_size} is not offered in ${AZURE_LOCATION}." >&2
        echo "Pick a location that offers it (az vm list-skus --location <loc> --all). Nothing was created." >&2
        return 1
    fi
done

# --- generated names (data-model §2) --------------------------------------------
_azure_user=$(az account show --query user.name --output tsv 2>/dev/null)
if [ -z "${_azure_user}" ] || [ "${_azure_user}" = "null" ]; then
    _azure_user="${USER:-unknown}"
fi
_azure_name=$(printf '%s' "${_azure_user}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
_azure_code=$(printf '%s' "${AZURE_SUBSCRIPTION_ID:-}:${AZURE_LOCATION}:${CLUSTER_SHAPE_VERSION}" \
    | { sha256sum 2>/dev/null || shasum -a 256; } \
    | cut -c1-6)

AZURE_RESOURCE_GROUP="${_azure_name}-aks-${_azure_code}"
AZURE_CLUSTER_NAME="sre-stack-${_azure_code}"
export AZURE_LOCATION AZURE_RESOURCE_GROUP AZURE_CLUSTER_NAME
AZURE_COMMON_LOADED=1
export AZURE_COMMON_LOADED
