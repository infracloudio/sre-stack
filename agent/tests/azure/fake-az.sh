#!/bin/bash
# fake-az.sh — offline stand-in for `az` (specs/001-azure-aks-setup T011).
#
# Contract (contracts/azure-cli-contract.md §2): every call is appended in
# full to $FAKE_AZ_LOG (one line per call, in order); every answer comes
# from the scenario file at $FAKE_AZ_SCENARIO (a sourced shell file that
# sets the knobs below) shaped like the real output recorded in
# research.md A7 and the §4 findings; the stand-in never touches the
# network. Unknown commands exit non-zero so contract drift can't pass
# quietly.
#
# Scenario knobs (defaults shown; the scenario file may override any):
#   SIGNED_IN=1|0                     az account show succeeds/fails
#   FAKE_USER / FAKE_SUB              identity for names and the RBAC check
#   RBAC_ROLE=Contributor             role recorded in the assignment row
#   LOCATIONS="eastus2 centralindia"  az account list-locations answers
#   SIZES="…"                         az vm list-skus answers
#   SPOT_LIMIT/DSV5_LIMIT/FSV2_LIMIT  az vm list-usage limits (current 0)
#   PRE_GROUP/PRE_CLUSTER/PRE_SC=1    what already exists before the run
#   PRE_POOLS="app persistent …"      workload pools that already exist
#   MC_LINGERS=1                      az group show --name MC_… succeeds
#                                     (the node resource group outlives delete)
#   CLUSTER_FAIL=1 / ADD_FAIL=<pool>  create steps that fail
#   POOL_MODE=spot|regular            scaleSetPriority the list answer shows

if [ -z "${FAKE_AZ_LOG:-}" ]; then
    echo "fake-az: FAKE_AZ_LOG is not set." >&2
    exit 64
fi
if [ -z "${FAKE_AZ_SCENARIO:-}" ]; then
    echo "fake-az: FAKE_AZ_SCENARIO is not set." >&2
    exit 64
fi
# shellcheck disable=SC1090
source "${FAKE_AZ_SCENARIO}"

# Every call, in order, with its full argument list.
printf '%s\n' "az $*" >> "${FAKE_AZ_LOG}"

SIGNED_IN="${SIGNED_IN:-1}"
FAKE_USER="${FAKE_USER:-someone@contoso.com}"
FAKE_SUB="${FAKE_SUB:-00000000-0000-0000-0000-000000000000}"
RBAC_ROLE="${RBAC_ROLE:-Contributor}"
LOCATIONS="${LOCATIONS:-eastus2 centralindia}"
SIZES="${SIZES:-Standard_D2s_v5 Standard_D4s_v5 Standard_F4s_v2}"
SPOT_LIMIT="${SPOT_LIMIT:-0}"
DSV5_LIMIT="${DSV5_LIMIT:-50}"
FSV2_LIMIT="${FSV2_LIMIT:-50}"
PRE_GROUP="${PRE_GROUP:-0}"
PRE_CLUSTER="${PRE_CLUSTER:-0}"
PRE_SC="${PRE_SC:-0}"
PRE_POOLS="${PRE_POOLS:-}"
CLUSTER_FAIL="${CLUSTER_FAIL:-0}"
ADD_FAIL="${ADD_FAIL:-}"
POOL_MODE="${POOL_MODE:-regular}"

_existed() {  # $1 pattern — already recorded in the log?
    grep -q "$1" "${FAKE_AZ_LOG}" 2>/dev/null
}

cluster_exists() {
    [ "${PRE_CLUSTER}" = "1" ] || _existed '^az aks create '
}

pool_exists() {  # pre-existing from scenario, or added earlier in this run
    [ -n "${1:-}" ] || return 1
    for _p in ${PRE_POOLS}; do
        [ "${_p}" = "$1" ] && return 0
    done
    _existed "^az aks nodepool add .*--name ${1} "
}

emit_pool_list() {
    FAKE_PRE_POOLS="${PRE_POOLS}" \
    FAKE_POOL_MODE="${POOL_MODE}" \
    FAKE_LOG_PATH="${FAKE_AZ_LOG}" \
    python3 <<'PYEOF'
import json, os

pre = (os.environ.get("FAKE_PRE_POOLS") or "").split()
mode = os.environ.get("FAKE_POOL_MODE") or "regular"
created = []
for line in open(os.environ["FAKE_LOG_PATH"]):
    if line.startswith("az aks nodepool add "):
        toks = line.split()
        for i, t in enumerate(toks):
            if t == "--name":
                created.append(toks[i + 1])

TABLE = {
    "app":        {"size": "Standard_D2s_v5", "min": 3, "max": 6,
                   "label": "app",        "taints": []},
    "persistent": {"size": "Standard_D4s_v5", "min": 2, "max": 2,
                   "label": "persistent", "taints": ["persistent=true:NoSchedule"]},
    "o11y":       {"size": "Standard_D4s_v5", "min": 2, "max": 3,
                   "label": "o11y",       "taints": ["o11y=true:NoSchedule"]},
    "loadgen":    {"size": "Standard_F4s_v2", "min": 1, "max": 1,
                   "label": "loadgen",    "taints": ["loadgen=true:NoSchedule"]},
}
auto = "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

pools = [{
    "name": "nodepool1", "mode": "System", "count": 1, "min": 1, "max": 1,
    "size": "Standard_D2s_v5", "labels": None, "taints": None, "spot": None,
}]
for name in pre + created:
    if name == "nodepool1" or name not in TABLE:
        continue
    row = TABLE[name]
    taints = list(row["taints"]) + ([auto] if mode == "spot" else [])
    pools.append({
        "name": name, "mode": "User",
        "count": row["min"], "min": row["min"], "max": row["max"],
        "size": row["size"],
        "labels": {"workload": row["label"]},
        "taints": taints or None,
        "spot": ("Spot" if mode == "spot" else None),
    })
print(json.dumps(pools))
PYEOF
}

_fake_add_fail() {  # $1 pool name — does this scenario fail that add?
    if [ -n "${ADD_FAIL}" ] && [ "${ADD_FAIL}" = "$1" ]; then
        echo "simulated nodepool add failure for ${ADD_FAIL}" >&2
        return 1
    fi
    return 0
}

_fake_name_arg() {  # pull the value of --name from "$@"
    printf '%s\n' "$@" | tr '\n' ' ' | sed 's/.*--name \([^ ]*\).*/\1/'
}

# Dispatch: one branch per command shape the repo's scripts use
# (contracts/azure-cli-contract.md §1).
case "${1:-}" in
    rest)
        # the resource-sku answer for the size check: contract §1 speed pass
        # (2026-09-10) — the helper reads Resource Skus List with a server-side
        # location filter; the stand-in answers with the same JSON shape.
        case "$*" in
            *"Microsoft.Compute/skus"*)
                FAKE_REST_LOCATIONS="${LOCATIONS}" FAKE_REST_SIZES="${SIZES}" python3 <<'PYEOF'
import json, os

doc = {"value": []}
for size in (os.environ.get("FAKE_REST_SIZES") or "").split():
    doc["value"].append({
        "resourceType": "virtualMachines",
        "name": size,
        "restrictions": [],
    })
print(json.dumps(doc))
PYEOF
                ;;
            *) echo "fake-az: unknown rest url: $*" >&2; exit 127 ;;
        esac
        ;;
    version)
        echo "2.90.0"
        ;;
    account)
        case "${2:-}" in
            show)
                if [ "${SIGNED_IN}" != "1" ]; then
                    echo "not signed in, run az login to access your accounts." >&2
                    exit 1
                fi
                case "$*" in
                    *user.name*) printf '%s\n' "${FAKE_USER}" ;;
                    *--query=id-*|*"--query id"*) printf '%s\n' "${FAKE_SUB}" ;;
                    *"--output none"*) : ;;
                    *) printf '{ "id": "%s", "name": "Pune - Sandbox (TPM)", "user": { "name": "%s" } }\n' \
                        "${FAKE_SUB}" "${FAKE_USER}" ;;
                esac
                ;;
            set)
                if [ "${SIGNED_IN}" != "1" ]; then
                    echo "Please run 'az login' to set up an account." >&2
                    exit 1
                fi
                ;;
            list-locations)
                if [ "${SIGNED_IN}" != "1" ]; then
                    echo "Please run 'az login'." >&2
                    exit 1
                fi
                for _loc in ${LOCATIONS}; do
                    echo "${_loc}"
                done
                ;;
            *) echo "fake-az: unknown account subcommand: $2" >&2; exit 127 ;;
        esac
        ;;
    group)
        case "${2:-}" in
            exists)
                if [ "${PRE_GROUP}" = "1" ] || _existed '^az group create '; then
                    echo "true"
                else
                    echo "false"
                fi
                ;;
            create)
                printf '{ "properties": { "provisioningState": "Succeeded" } }\n'
                ;;
            delete)
                : ;;
            show)
                if [ "${MC_LINGERS:-0}" = "1" ] && printf '%s\n' "$*" | grep -q 'MC_'; then
                    printf '{ "name": "fake-mc" }\n'
                elif _existed '^az group create ' && ! _existed '^az group delete '; then
                    printf '{ "name": "fake" }\n'
                else
                    exit 1
                fi
                ;;
            *) echo "fake-az: unknown group subcommand: $2" >&2; exit 127 ;;
        esac
        ;;
    aks)
        case "${2:-}" in
            show)
                if ! cluster_exists; then
                    exit 1
                fi
                case "$*" in
                    *'{s: provisioningState, p: powerState.code}'*)
                        printf 'Succeeded\tRunning\n' ;;
                    *provisioningState*)
                        printf 'Succeeded\n' ;;
                    *) : ;;
                esac
                ;;
            create)
                if [ "${CLUSTER_FAIL}" = "1" ]; then
                    echo "simulated cluster create failure" >&2
                    exit 1
                fi
                printf '{ "name": "sre-stack-000000" }\n'
                ;;
            nodepool)
                case "${3:-}" in
                    show)
                        _pool=$(_fake_name_arg "$@")
                        if pool_exists "${_pool}"; then
                            printf '{ "name": "%s" }\n' "${_pool}"
                        else
                            exit 1
                        fi
                        ;;
                    add)
                        _pool=$(_fake_name_arg "$@")
                        if ! _fake_add_fail "${_pool}"; then
                            exit 1
                        fi
                        printf '{ "name": "%s" }\n' "${_pool}"
                        ;;
                    list)
                        emit_pool_list
                        ;;
                    *) echo "fake-az: unknown nodepool subcommand: $3" >&2; exit 127 ;;
                esac
                ;;
            get-credentials)
                ;;
            *) echo "fake-az: unknown aks subcommand: $2" >&2; exit 127 ;;
        esac
        ;;
    vm)
        case "${2:-}" in
            list-skus)
                for _s in ${SIZES}; do
                    echo "${_s}"
                done
                ;;
            list-usage)
                printf 'lowPriorityCores\tTotal Regional Low-priority vCPUs\t0\t%s\n' "${SPOT_LIMIT}"
                printf 'standardDSv5Family\tStandard DSv5 Family vCPUs\t0\t%s\n' "${DSV5_LIMIT}"
                printf 'standardFSv2Family\tStandard FSv2 Family vCPUs\t0\t%s\n' "${FSV2_LIMIT}"
                ;;
            *) echo "fake-az: unknown vm subcommand: $2" >&2; exit 127 ;;
        esac
        ;;
    role)
        case "${2:-}" in
            assignment)
                if [ "${SIGNED_IN}" != "1" ]; then
                    echo "Please run 'az login'." >&2
                    exit 1
                fi
                printf '/subscriptions/%s/providers/Microsoft.Authorization/roleDefinitions/8e3af657\t%s\t/subscriptions/%s\n' \
                    "${FAKE_SUB}" "${RBAC_ROLE}" "${FAKE_SUB}"
                ;;
            definition)
                printf '[ ]\n'
                ;;
            *) echo "fake-az: unknown role subcommand: $2" >&2; exit 127 ;;
        esac
        ;;
    *)
        echo "fake-az: unknown command: az ${1:-}" >&2
        exit 127
        ;;
esac
exit 0
