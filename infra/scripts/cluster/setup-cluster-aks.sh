#!/bin/bash
# setup-cluster-aks.sh — create the empty AKS cluster (STACK_MODE=aks).
#
# specs/001-azure-aks-setup T007. Idempotent, resource by resource: check each
# one by its exact name and create only what is missing (FR-003, FR-011).
# Build order and every command shape come from
# specs/001-azure-aks-setup/contracts/azure-cli-contract.md §1. On any failure
# the script stops, prints the partial-failure report (§3), never deletes
# anything on its own, and exits non-zero.

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/infra/scripts/cluster/azure-common.sh" || exit 1

cd "${_repo_root}" || exit 1

if [ -z "${AKS_KUBERNETES_VERSION:-}" ]; then
    echo "Cannot start: AKS_KUBERNETES_VERSION in .env is empty." >&2
    echo "Set the pinned version confirmed in the manual try-out (research.md §7), then try again. Nothing was created." >&2
    exit 1
fi

_rg="${AZURE_RESOURCE_GROUP}"
_cluster="${AZURE_CLUSTER_NAME}"
_loc="${AZURE_LOCATION}"

# Canonical step list (build order) and what landed. At failure time nothing
# reached "done" is reported as not created — the §3 report.
_steps=(group cluster system app persistent o11y loadgen kubecreds storage)
_setup_done=()
_system_pools_reached=0

_step_label() {
    case "$1" in
        group)     printf 'resource group %s' "${_rg}" ;;
        cluster)   printf 'cluster %s' "${_cluster}" ;;
        system)    printf 'node pool system (running)' ;;
        app)       printf 'node pool app (running)' ;;
        persistent) printf 'node pool persistent (running)' ;;
        o11y)      printf 'node pool o11y (running)' ;;
        loadgen)   printf 'node pool loadgen (running)' ;;
        kubecreds) printf 'kube credentials' ;;
        storage)   printf 'gp2 storage setting' ;;
    esac
}

_setup_fail() {
    echo "Setup stopped partway. Created so far:" >&2
    local _s
    for _s in "${_steps[@]}"; do
        case "${_s}" in
            system) [ "${_system_pools_reached}" -eq 1 ] && echo "  - node pool system (running)" >&2 ;;
            *) if printf '%s\n' "${_setup_done[@]:-}" | grep -qx "${_s}"; then
                   echo "  - $(_step_label "${_s}")" >&2
               fi ;;
        esac
    done
        printf 'Not created:' >&2
    for _s in "${_steps[@]}"; do
        case "${_s}" in
            system) [ "${_system_pools_reached}" -eq 1 ] && continue ;;
            *) printf '%s\n' "${_setup_done[@]:-}" | grep -qx "${_s}" && continue ;;
        esac
        case "${_s}" in
            group)     printf ' resource group,' >&2 ;;
            cluster)   printf ' cluster,' >&2 ;;
            system)    printf ' system pool,' >&2 ;;
            app)       printf ' app pool,' >&2 ;;
            persistent) printf ' persistent pool,' >&2 ;;
            o11y)      printf ' o11y pool,' >&2 ;;
            loadgen)   printf ' loadgen pool,' >&2 ;;
            kubecreds) printf ' kube credentials,' >&2 ;;
            storage)   printf ' gp2 storage setting,' >&2 ;;
        esac
    done
    echo " (pool adds that did not run may still be finishing on Azure's side; nothing was deleted by us)." >&2
    echo "" >&2
    echo "Nothing was deleted. Options:" >&2
    echo "  - run 'make setup-cluster' again to continue, or" >&2
    echo "  - run 'make cleanup-cluster' to remove everything and start fresh." >&2
    exit 1
}

_mark() {
    _setup_done+=("$1")
}

echo "Settings: STACK_MODE=aks, location ${_loc}, mode ${AZURE_POOL_MODE}."
echo "Names: resource group ${_rg}, cluster ${_cluster}."

# --- 1. resource group (exact-name check; FR-003) -----------------------------
if [ "$(az group exists --name "${_rg}" --output tsv 2>/dev/null)" = "true" ]; then
    echo "already exists: resource group ${_rg}"
    _mark group
else
    echo "creating resource group ${_rg}..."
    if ! az group create --name "${_rg}" --location "${_loc}" >/dev/null 2>&1; then
        echo "Failed to create resource group ${_rg}. Check location and sign-in, then try again." >&2
        _setup_fail
    fi
    _mark group
fi

# --- 2. cluster + system pool (az aks show decides; §1) ------------------------
if az aks show --resource-group "${_rg}" --name "${_cluster}" >/dev/null 2>&1; then
    echo "already exists: cluster ${_cluster} (system pool included)"
    # Version drift (T043): a reused cluster is never upgraded in place.
    _live_version=$(az aks show --resource-group "${_rg}" --name "${_cluster}" \
        --query kubernetesVersion --output tsv 2>/dev/null)
    if [ -n "${_live_version}" ] && [ "${_live_version}" != "${AKS_KUBERNETES_VERSION}" ]; then
        echo "WARNING: cluster ${_cluster} runs Kubernetes ${_live_version} but .env pins ${AKS_KUBERNETES_VERSION}." >&2
        echo "No automatic upgrade happens. To move deliberately: run 'make cleanup-cluster', then 'make setup-cluster'." >&2
    fi
    _mark cluster
    _mark system
    _system_pools_reached=1
else
    echo "creating cluster ${_cluster} (kubernetes ${AKS_KUBERNETES_VERSION}, 1× Standard_D2s_v5 system pool) — this takes ~10 minutes..."
    if ! az aks create --resource-group "${_rg}" --name "${_cluster}" --location "${_loc}" \
            --kubernetes-version "${AKS_KUBERNETES_VERSION}" \
            --node-count 1 --node-vm-size Standard_D2s_v5 \
            --generate-ssh-keys --no-wait >/dev/null 2>&1; then
        echo "Failed to create cluster ${_cluster}." >&2
        _setup_fail
    fi
    # az aks create ran with --no-wait; poll provisioningState until Succeeded.
    _state=""
    _waited=0
    while [ "${_state}" != "Succeeded" ]; do
        sleep 15
        _waited=$((_waited + 15))
        _state=$(az aks show --resource-group "${_rg}" --name "${_cluster}" \
            --query provisioningState --output tsv 2>/dev/null)
        if [ "${_state}" = "Failed" ]; then
            echo "Cluster ${_cluster} reached provisioningState Failed." >&2
            _setup_fail
        fi
        if [ "${_waited}" -ge 1800 ]; then
            echo "Gave up waiting for cluster ${_cluster} after 30 minutes (provisioningState: ${_state:-unknown})." >&2
            _setup_fail
        fi
        echo "  still provisioning (${_state:-unknown}, ${_waited}s)..."
    done
    _mark cluster
    _mark system
    _system_pools_reached=1
fi

# --- 3. workload pools, §3 table; spot flags only when the helper chose spot ---
_pool_add() {  # $1 name $2 size $3 count $4 min $5 max $6 label $7 taint
    local _name="$1" _size="$2" _count="$3" _min="$4" _max="$5" _label="$6" _taint="$7"
    if az aks nodepool show --resource-group "${_rg}" --cluster-name "${_cluster}" \
            --name "${_name}" >/dev/null 2>&1; then
        echo "already exists: node pool ${_name}"
        _mark "${_name}"
        return 0
    fi
    echo "adding node pool ${_name} (${_count}× ${_size}) — this takes ~4 minutes..."
    local _cmd
    _cmd=(az aks nodepool add --resource-group "${_rg}" --cluster-name "${_cluster}" \
        --name "${_name}" \
        --node-count "${_count}" --node-vm-size "${_size}" \
        --labels "${_label}" \
        --enable-cluster-autoscaler --min-count "${_min}" --max-count "${_max}")
    if [ -n "${_taint}" ]; then
        _cmd+=(--node-taints "${_taint}")
    fi
    if [ "${AZURE_POOL_MODE}" = "spot" ]; then
        _cmd+=(--priority Spot --eviction-policy Delete --spot-max-price -1)
    fi
    if ! "${_cmd[@]}" >/dev/null 2>&1; then
        echo "Failed to add node pool ${_name}." >&2
        _setup_fail
    fi
    _mark "${_name}"
}

_pool_add app         Standard_D2s_v5 3 3 6 "workload=app"        ""
_pool_add persistent  Standard_D4s_v5 2 2 2 "workload=persistent" "persistent=true:NoSchedule"
_pool_add o11y        Standard_D4s_v5 2 2 3 "workload=o11y"       "o11y=true:NoSchedule"
_pool_add loadgen     Standard_F4s_v2 1 1 1 "workload=loadgen"    "loadgen=true:NoSchedule"

# --- 4. kubeconfig -------------------------------------------------------------
echo "fetching kubeconfig for ${_cluster}..."
if ! az aks get-credentials --resource-group "${_rg}" --name "${_cluster}" \
        --overwrite-existing >/dev/null 2>&1; then
    echo "Failed to write kube credentials for ${_cluster}." >&2
    _setup_fail
fi
_mark kubecreds

# --- 5. gp2 storage setting -----------------------------------------------------
if kubectl get storageclass gp2 >/dev/null 2>&1; then
    echo "already exists: gp2 storage setting"
else
    echo "applying infra/azure/gp2-storageclass.yaml..."
    if ! kubectl apply -f infra/azure/gp2-storageclass.yaml >/dev/null 2>&1; then
        echo "Failed to apply the gp2 storage setting." >&2
        _setup_fail
    fi
fi
_mark storage

echo "Setup complete: cluster ${_cluster} in ${_rg} (${_loc}), mode ${AZURE_POOL_MODE}."
