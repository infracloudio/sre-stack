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
#   RBAC_MG_SCOPE=ancestor|unrelated  a second assignment sits on a parent
#                                     management group; the stand-in mirrors
#                                     Azure: an ancestor row appears only
#                                     when the call carries
#                                     --include-inherited, an unrelated one
#                                     never appears
#   RBAC_MG_ID / RBAC_MG_ROLE         that management group and its role
#   LOCATIONS="eastus2 centralindia"  az account list-locations answers
#   SIZES="…"                         az rest resource-skus answers
#   SPOT_LIMIT/DSV5_LIMIT/FSV2_LIMIT  az vm list-usage limits
#   SPOT_CURRENT/DSV5_CURRENT/FSV2_CURRENT
#                                     az vm list-usage used vCPU (default 0);
#                                     nonzero values model an existing cluster
#   PRE_GROUP/PRE_CLUSTER/PRE_SC=1    what already exists before the run
#   PRE_POOLS="app persistent …"      workload pools that already exist
#   MC_LINGERS=1                      az group exists --name MC_… says true
#                                     (the node resource group outlives delete)
#   GROUP_READ_FAIL=1                 az group exists fails (unreadable state)
#   DELETE_FAIL=1                     az group delete fails (partial delete)
#   CLUSTER_FAIL=1 / ADD_FAIL=<pool>  create steps that fail
#   CLUSTER_STATE_FAIL=1              az aks show provisioningState reads fail
#                                     after the create was submitted (T056)
#   POOL_MODE=spot|regular            scaleSetPriority the list answer shows
#   K8S_VERSION=1.34                  live kubernetesVersion a reused cluster
#                                     reports (setup compares it to the pin)
#   POOL_MUTATIONS="…"                space-separated pool.field=value patches
#                                     applied to the nodepool list answer:
#                                     count/min/max/size/label/taints/spot/mode
#                                     (taints=none clears, spot=none/null clears)
#                                     or <pool>.missing=1 to drop the row;
#                                     <pool> is a workload name or `system`.
#                                     Unknown target = stand-in error, exit 2

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
SPOT_CURRENT="${SPOT_CURRENT:-0}"
DSV5_CURRENT="${DSV5_CURRENT:-0}"
FSV2_CURRENT="${FSV2_CURRENT:-0}"
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
    FAKE_POOL_MUTATIONS="${POOL_MUTATIONS:-}" \
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
        # `spot` is what the verifier projects; `priority` is what the
        # helper's allowance check projects (T050). The stand-in answers the
        # full object either way, exactly like a real unqueried az answer.
        "spot": ("Spot" if mode == "spot" else None),
        "priority": ("Spot" if mode == "spot" else None),
    })

# Malformed-row patches for the verify scenarios: pool.field=value, or
# pool.missing=1 to drop the row. Unknown target = loud stand-in error.
def patch(target, field, value):
    if field == "count":
        target["count"] = int(value)
    elif field == "min":
        target["min"] = int(value)
    elif field == "max":
        target["max"] = int(value)
    elif field == "size":
        target["size"] = value
    elif field == "label":
        target["labels"] = {"workload": value}
    elif field == "taints":
        target["taints"] = None if value == "none" else [value]
    elif field == "spot":
        _spot = None if value in ("none", "null") else value
        target["spot"] = _spot
        target["priority"] = _spot
    elif field == "mode":
        target["mode"] = value

for spec in (os.environ.get("FAKE_POOL_MUTATIONS") or "").split():
    path, _, value = spec.partition("=")
    name, _, field = path.partition(".")
    target = next((p for p in pools if p.get("name") == name
                   or (name == "system" and p.get("mode") == "System")), None)
    if not name or not field or target is None:
        print("fake-az: unknown pool mutation: " + spec, file=sys.stderr)
        sys.exit(2)
    if field == "missing" and value == "1":
        pools.remove(target)
    else:
        patch(target, field, value)

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
                    *) printf '{ "id": "%s", "name": "Example Subscription", "user": { "name": "%s" } }\n' \
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
                if [ "${GROUP_READ_FAIL:-0}" = "1" ]; then
                    echo "fake-az: simulated resource group read failure" >&2
                    exit 1
                fi
                _group=$(_fake_name_arg "$@")
                case "${_group}" in
                    MC_*)
                        # Another person's or our own exact MC_ name both
                        # answer by name; only our predicted name is asked.
                        if [ "${MC_LINGERS:-0}" = "1" ]; then echo "true"; else echo "false"; fi
                        ;;
                    *)
                        if [ "${PRE_GROUP}" = "1" ] || _existed '^az group create '; then
                            # A simulated failed delete must not make the
                            # group disappear (T056 partial-delete case).
                            if _existed '^az group delete ' && [ "${DELETE_FAIL:-0}" != "1" ]; then
                                echo "false"
                            else
                                echo "true"
                            fi
                        else
                            echo "false"
                        fi
                        ;;
                esac
                ;;
            create)
                printf '{ "properties": { "provisioningState": "Succeeded" } }\n'
                ;;
            delete)
                if [ "${DELETE_FAIL:-0}" = "1" ]; then
                    echo "fake-az: simulated resource group delete failure" >&2
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
                if [ "${CLUSTER_STATE_FAIL:-0}" = "1" ] \
                    && printf '%s\n' "$*" | grep -q 'provisioningState'; then
                    # The create was accepted (--no-wait) but the state read
                    # fails: setup must report it as submitted, not missing.
                    echo "fake-az: simulated cluster state read failure" >&2
                    exit 1
                fi
                case "$*" in
                    *'[provisioningState, powerState.code]'*)
                        printf 'Succeeded\tRunning\n' ;;
                    *kubernetesVersion*)
                        printf '%s\n' "${K8S_VERSION:-1.34}" ;;
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
                        if ! cluster_exists; then
                            exit 1
                        fi
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
            list-usage)
                if printf '%s\n' "$*" | grep -q -- '--output json'; then
                    # T054: JSON parsed by field name. The keys are emitted in
                    # a deliberately non-alphabetical order to prove the
                    # reader never depends on it.
                    FAKE_SPOT_CURRENT="${SPOT_CURRENT}" FAKE_DSV5_CURRENT="${DSV5_CURRENT}" \
                    FAKE_FSV2_CURRENT="${FSV2_CURRENT}" FAKE_SPOT_LIMIT="${SPOT_LIMIT}" \
                    FAKE_DSV5_LIMIT="${DSV5_LIMIT}" FAKE_FSV2_LIMIT="${FSV2_LIMIT}" \
                    python3 <<'PYEOF'
import json, os

def item(name, display, current, limit):
    return {"name": {"localizedValue": display, "value": name},
            "limit": int(limit), "unit": "Count", "currentValue": int(current)}

print(json.dumps({"value": [
    item("lowPriorityCores", "Total Regional Low-priority vCPUs",
         os.environ["FAKE_SPOT_CURRENT"], os.environ["FAKE_SPOT_LIMIT"]),
    item("standardDSv5Family", "Standard DSv5 Family vCPUs",
         os.environ["FAKE_DSV5_CURRENT"], os.environ["FAKE_DSV5_LIMIT"]),
    item("standardFSv2Family", "Standard FSv2 Family vCPUs",
         os.environ["FAKE_FSV2_CURRENT"], os.environ["FAKE_FSV2_LIMIT"]),
]}))
PYEOF
                else
                    # Old object-projection TSV path: Azure documents no
                    # ordering guarantee and alphabetizes keys as a best
                    # effort (cur, lim, name, what). Returning that order
                    # makes any order-dependent reader fail loudly offline.
                    printf '%s\t%s\tlowPriorityCores\tTotal Regional Low-priority vCPUs\n' \
                        "${SPOT_CURRENT}" "${SPOT_LIMIT}"
                    printf '%s\t%s\tstandardDSv5Family\tStandard DSv5 Family vCPUs\n' \
                        "${DSV5_CURRENT}" "${DSV5_LIMIT}"
                    printf '%s\t%s\tstandardFSv2Family\tStandard FSv2 Family vCPUs\n' \
                        "${FSV2_CURRENT}" "${FSV2_LIMIT}"
                fi
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
                if [ "${RBAC_MG_SCOPE:-}" = "ancestor" ] \
                    && printf '%s\n' "$*" | grep -q -- '--include-inherited'; then
                    printf '/providers/Microsoft.Management/managementGroups/%s/providers/Microsoft.Authorization/roleDefinitions/8e3af657\t%s\t/providers/Microsoft.Management/managementGroups/%s\n' \
                        "${RBAC_MG_ID:-contoso-parent}" "${RBAC_MG_ROLE:-Contributor}" \
                        "${RBAC_MG_ID:-contoso-parent}"
                fi
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
