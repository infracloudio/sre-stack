#!/bin/bash
# azure-common.sh — shared settings, pre-checks, and generated names for the
# STACK_MODE=aks path (specs/001-azure-aks-setup, T005).
#
# Sourced by the aks setup/cleanup/verify scripts; never executed directly.
# Read-only: it only inspects Azure. Every refusal prints what is wrong, what
# to do, and that nothing was created — before anything is created or deleted
# (contracts/azure-cli-contract.md §3).
#
# Cleanup mode (AZURE_CLEANUP=1, T014): teardown must never be blocked by a
# create-time fact that changed since setup (quota, offered sizes,
# permissions). It keeps the sign-in check and the generated names, skips the
# create-time probes, and refusals say "Nothing was deleted".
#
# Exports for callers after success:
#   AZURE_LOCATION         resolved location (setting or the eastus2 fallback)
#   AZURE_RESOURCE_GROUP   generated resource group name <name>-aks-<code>
#   AZURE_CLUSTER_NAME     generated cluster name sre-stack-<code>
#   AZURE_POOL_MODE        workload-pool mode the allowance check chose:
#                          spot | regular (FR-014, AD-002)
#   AZURE_SPOT_VCPU_CURRENT/LIMIT   the spot vCPU numbers that fed the choice
#   AZURE_DSV5_VCPU_CURRENT/LIMIT   the DSv5 family numbers
#   AZURE_FSV2_VCPU_CURRENT/LIMIT   the FSv2 family numbers
#   AZURE_RBAC_ROLE        proven permission role (Owner / Contributor /
#                          custom-role-with-create) feeding the refusal if none
#   AZURE_RBAC_SCOPE       the scope (subscription, "/", or parent MG) proven

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

if [ -n "${AZURE_CLEANUP:-}" ]; then
    _azure_result_word="deleted"
else
    _azure_result_word="created"
fi

# --- STACK_MODE gate (FR-006) ------------------------------------------------
# Skipped in cleanup mode: cleanup-cluster.sh dispatches on STACK_MODE itself
# before sourcing the helper.
if [ -z "${AZURE_CLEANUP:-}" ]; then
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
fi

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
    echo "Run 'az login' first, then try again. Nothing was ${_azure_result_word}." >&2
    return 1
fi

# --- pre-check 2: subscription ------------------------------------------------
# The signed-in principal id (UPN for a person, clientId for a service
# principal — either works directly as --assignee) computed once, reused by
# pre-check 2b and the generated-name recipe.
_azure_user=$(az account show --query user.name --output tsv 2>/dev/null)
if [ -z "${_azure_user}" ] || [ "${_azure_user}" = "null" ]; then
    echo "Cannot start: the signed-in identity has no usable principal name." >&2
    echo "Re-run az login with an account or service principal that has one. Nothing was ${_azure_result_word}." >&2
    return 1
fi
if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
    if ! az account set --subscription "${AZURE_SUBSCRIPTION_ID}" 2>/dev/null; then
        echo "Cannot start: subscription '${AZURE_SUBSCRIPTION_ID}' was not found or is not accessible." >&2
        echo "Check AZURE_SUBSCRIPTION_ID in .env (or leave it empty to use the signed-in subscription). Nothing was ${_azure_result_word}." >&2
        return 1
    fi
fi

# --- location fallback + generated names (data-model §2) ------------------------
# Computed before the create-time probes (they use the location) and early for
# cleanup mode, which only needs the sign-in and the names.
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"
_azure_name=$(printf '%s' "${_azure_user}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
_azure_code=$(printf '%s' "${AZURE_SUBSCRIPTION_ID:-}:${AZURE_LOCATION}:${CLUSTER_SHAPE_VERSION}" \
    | { sha256sum 2>/dev/null || shasum -a 256; } \
    | cut -c1-6)

AZURE_RESOURCE_GROUP="${_azure_name}-aks-${_azure_code}"
AZURE_CLUSTER_NAME="sre-stack-${_azure_code}"
export AZURE_LOCATION AZURE_RESOURCE_GROUP AZURE_CLUSTER_NAME

if [ -n "${AZURE_CLEANUP:-}" ]; then
    # Cleanup only needs sign-in and the names; the create-time probes below
    # are skipped so teardown is never blocked by changed quota or sizes.
    AZURE_COMMON_LOADED=1
    export AZURE_COMMON_LOADED
    return 0
fi

# --- pre-check 2b: the signed-in identity may actually create things ----------
# (contract §1; story-owner request 2026-09-10). The four independent
# read-only probes — permission, location, machine sizes, allowance — run
# in parallel (every az invocation boots ~1 s serially), then the checks
# below evaluate their answers in the contract order: permission,
# location, sizes, allowance.
#
# Speed note (2026-09-10): `az vm list-skus` downloads a multi-MB response
# for all resource types and filters client-side — 90 s+ per call even with
# exact filters (azure-cli issues #31592/#30389). The location filter on
# the underlying REST API IS server-side, so the size check reads it
# directly: `az rest` + Resource Skus List (api-version 2021-07-01; the
# only supported $filter is location). Same --all semantics: names are
# matched regardless of `restrictions` in the payload; no cache — one
# small live GET per run.
_azure_skus_out() {
    az rest --method GET \
        --url "https://management.azure.com/subscriptions/${_azure_sub_id}/providers/Microsoft.Compute/skus?api-version=2021-07-01&%24filter=location%20eq%20%27${AZURE_LOCATION}%27" 2>/dev/null
}

# Did an az read fail because the thing is absent? az has no per-category
# exit code (every failure is 1) and no JSON error mode — `--output` shapes
# stdout only; errors always reach stderr as text. The ARM error *code* is
# structured, though: az prints it as the `(<Code>)` prefix of the first
# error line and again as a `Code: <Code>` line. Match only those, only
# the codes that mean "absent", anchored and case-sensitive — a message
# that merely contains "not found" (SubscriptionNotFound, an expired token
# "not found in cache") is an unrelated failure and must never read as
# absent, or a duplicate gets created (T057).
_az_err_is_not_found() {  # $1 stderr capture of an az show/exists call
    grep -qE '^(ERROR: )?\((ResourceNotFound|ResourceGroupNotFound|AgentPoolNotFound|NotFound)\)|^Code: (ResourceNotFound|ResourceGroupNotFound|AgentPoolNotFound|NotFound)$' \
        "$1" 2>/dev/null
}

_az_will_parallel_checks() {
    _azure_sub_id=$(az account show --query id --output tsv 2>/dev/null)
    _azure_jobsdir=$(mktemp -d)
    # --include-inherited lets Azure resolve its own scope hierarchy: only
    # assignments at the current subscription and its parent scopes (the
    # management-group chain, up to root) come back, so a management-group
    # row is provably an ancestor of the subscription. An assignment on an
    # unrelated management group is never returned, whatever its scope
    # string says (contract §1, T027).
    az role assignment list \
        --assignee "${_azure_user}" --include-groups --include-inherited \
        --query "[].{id: roleDefinitionId, role: roleDefinitionName, scope: scope}" \
        --output tsv > "${_azure_jobsdir}/rbac.out" 2>/dev/null &
    az account list-locations --query "[?name=='${AZURE_LOCATION}'].name" --output tsv \
        > "${_azure_jobsdir}/locations.out" 2>/dev/null &
    # Allowance: plain JSON, parsed by field name below (T054). Object-shaped
    # TSV has no ordering guarantee — Azure sorts projected keys alphabetically
    # as a best effort, so a reader that trusts `{name, what, cur, lim}` order
    # can silently swap the numbers. JSON keyed by name cannot.
    az vm list-usage --location "${AZURE_LOCATION}" \
        --output json > "${_azure_jobsdir}/usage.json" 2>/dev/null &
    ( _azure_skus_out > "${_azure_jobsdir}/skus.out" 2>/dev/null ) &
    # Does the cluster (and its system pool) already exist? The allowance
    # check needs this: a rerun must not demand room for what already exists,
    # and a resume must keep the mode the existing workload pools use (T050).
    # T057: a failed read is never "absent" — only a NotFound answer means
    # absent; anything else refuses before anything is created.
    ( az aks show --resource-group "${AZURE_RESOURCE_GROUP}" --name "${AZURE_CLUSTER_NAME}" \
          --output none 2> "${_azure_jobsdir}/aks.err"
      echo $? > "${_azure_jobsdir}/aks.rc" ) &
    wait
}
_az_will_parallel_checks

# --- permission (pre-check 2b) -------------------------------------------------
_azure_assignments=$(cat "${_azure_jobsdir}/rbac.out")
if [ -z "${_azure_assignments}" ]; then
    echo "Cannot start: the role assignments for ${_azure_user} could not be read (az role assignment list returned nothing)." >&2
    echo "Check the sign-in and subscription (az role assignment list --assignee ${_azure_user} --include-groups). Nothing was created." >&2
    return 1
fi
AZURE_RBAC_ROLE=""
AZURE_RBAC_SCOPE=""
_azure_custom_defs=""
# Covering scopes for the new resource group: the exact subscription, root,
# or a parent management group — ancestry guaranteed by the inherited
# lookup above, not by matching the scope string alone (T027).
while IFS=$'\t' read -r _azure_def _azure_role _azure_scope; do
    case "${_azure_scope}" in
        "/subscriptions/${_azure_sub_id}"|"/"|"/providers/Microsoft.Management/managementGroups/"*) ;;
        *) continue ;;
    esac
    case "${_azure_role}" in
        Owner|Contributor)
            AZURE_RBAC_ROLE="${_azure_role}"
            AZURE_RBAC_SCOPE="${_azure_scope}"
            break
            ;;
        null|"") ;;
        *) _azure_custom_defs="${_azure_custom_defs} ${_azure_def}" ;;
    esac
done <<< "${_azure_assignments}"
if [ -z "${AZURE_RBAC_ROLE}" ] && [ -n "${_azure_custom_defs}" ]; then
    _azure_actions=$(az role definition list \
        --query "[?contains('${_azure_custom_defs}', id)].[].permissions[].actions" \
        --output tsv 2>/dev/null)
    if printf '%s' "${_azure_actions}" | grep -Eq '(^|[[:space:],])\*($|[[:space:],])|\*/write|Microsoft\.ContainerService/\*'; then
        AZURE_RBAC_ROLE="custom-role-with-create"
        AZURE_RBAC_SCOPE="${_azure_sub_id}"
    fi
fi
if [ -z "${AZURE_RBAC_ROLE}" ]; then
    echo "Cannot start: ${_azure_user} has no permission in subscription ${_azure_sub_id} to create the resources this stack needs." >&2
    echo "Ask the subscription administrator for Owner or Contributor (Portal → Subscriptions → Access control (IAM); group-based grant works too). Nothing was created." >&2
    return 1
fi
echo "permission check: '${AZURE_RBAC_ROLE}' on ${AZURE_RBAC_SCOPE:+$AZURE_RBAC_SCOPE}"

# --- pre-check 3: location is real ---------------------------------------------
echo "checking: location '${AZURE_LOCATION}' is real (az account list-locations)..."
if ! grep -qx "${AZURE_LOCATION}" "${_azure_jobsdir}/locations.out" 2>/dev/null; then
    echo "Cannot start: location '${AZURE_LOCATION}' is not a real Azure location for this account." >&2
    echo "Set AZURE_LOCATION in .env to a listed one (az account list-locations --query \"[].name\" -o tsv). Nothing was created." >&2
    return 1
fi

# --- pre-check 4: every machine size offered there ------------------------------
# No silent swap, no automatic move to another region (data-model §1).
# `az rest`-fetched file with the exact names; missing = refuse.
for _azure_size in Standard_D2s_v5 Standard_D4s_v5 Standard_F4s_v2; do
    echo "checking: machine size ${_azure_size} offered in ${AZURE_LOCATION} (resource skus)..."
    _azure_skus_file="${_azure_jobsdir}/skus.out"
    if ! [ -s "${_azure_skus_file}" ] || \
        ! AZURE_SIZE="${_azure_size}" AZURE_SKUS_FILE="${_azure_skus_file}" \
        python3 -c "
import json, os, sys
size = os.environ['AZURE_SIZE']
doc = json.load(open(os.environ['AZURE_SKUS_FILE']))
names = {s.get('name') for s in doc.get('value', [])
         if s.get('resourceType') == 'virtualMachines'}
sys.exit(0 if size in names else 1)
" 2>/dev/null; then
        echo "Cannot start: machine size ${_azure_size} is not offered in ${AZURE_LOCATION}." >&2
        echo "Pick a location that offers it (Resource Skus List API). Nothing was created." >&2
        return 1
    fi
done
# --- existing cluster inventory (FR-003/FR-011, T050) ---------------------------
# A rerun must never demand fresh capacity for resources that already exist,
# and a partly built cluster must keep the machine mode its existing workload
# pools already use — flipping modes mid-build would create a mixed cluster.
# Read-only; skipped when the cluster does not exist yet.
# T057: only a NotFound answer means "absent". Any other non-zero read is a
# failed read — refuse, never assume missing and create a duplicate.
_azure_pools_json="[]"
_azure_aks_rc=$(cat "${_azure_jobsdir}/aks.rc" 2>/dev/null)
if [ "${_azure_aks_rc}" = "0" ]; then
    if ! _azure_pools_json=$(az aks nodepool list \
            --resource-group "${AZURE_RESOURCE_GROUP}" --cluster-name "${AZURE_CLUSTER_NAME}" \
            --query "[].{name: name, mode: mode, priority: scaleSetPriority}" \
            --output json 2>/dev/null); then
        echo "Cannot start: the node pools of the existing cluster ${AZURE_CLUSTER_NAME} could not be read." >&2
        echo "Check the sign-in and the cluster (az aks nodepool list), then try again. Nothing was created." >&2
        return 1
    fi
    [ -n "${_azure_pools_json}" ] || _azure_pools_json="[]"
elif [ -n "${_azure_aks_rc}" ] && ! _az_err_is_not_found "${_azure_jobsdir}/aks.err"; then
    echo "Cannot start: the state of cluster ${AZURE_CLUSTER_NAME} could not be read (az aks show failed)." >&2
    echo "Check the sign-in, the resource group ${AZURE_RESOURCE_GROUP}, and the network, then try again. Nothing was created." >&2
    return 1
fi

# --- pre-check 5: the machine allowance decides the workload pool mode --------
# (FR-014, AD-002, T050; contract §1). The usage answer is plain JSON parsed
# by field name (T054) — never by column order. The needs below are for the
# resources that do not exist yet: a full cluster reruns with needs 0 and can
# never be blocked by its own consumption. The system pool is always regular
# (Azure requires the first pool to be non-spot), so the DSv5 family carries
# it whenever the cluster itself is missing. Fresh cluster: spot first (the
# four workload pools at minimum counts — app 6 + persistent 8 + o11y 8 +
# loadgen 4 = 26 — plus 2 DSv5 for the system pool), then regular per family
# (DSv5 24 = workload 22 + system 2; FSv2 4), else refuse naming the short
# family with its numbers, before anything is created. Judged against
# minimum counts only; autoscaler growth is capped by the allowance, never
# dodged. Field names confirmed by hand and recorded in research.md (T023,
# constitution VIII).
# Full-shape vCPU at minimum counts (data-model §3): workload pools 26 spot
# / 22 DSv5 + 4 FSv2 regular; the system pool adds 2 DSv5 while the cluster
# itself is missing. The per-run needs below count only missing resources.
AZURE_DSV5_SYSTEM_NEEDED=2

_azure_usage_norm=$(AZURE_USAGE_FILE="${_azure_jobsdir}/usage.json" python3 - <<'PYEOF'
import json, os, sys

try:
    doc = json.load(open(os.environ["AZURE_USAGE_FILE"]))
except (OSError, ValueError):
    sys.exit(1)

# Real `az vm list-usage --output json` is a bare array of usage items
# (T058). Accept a REST-style {"value": [...]} object only for backward
# compat with older stand-ins; anything else is malformed.
if isinstance(doc, dict):
    items = doc.get("value")
elif isinstance(doc, list):
    items = doc
else:
    sys.exit(1)
if not isinstance(items, list):
    sys.exit(1)

def to_int(v):
    # The CLI may render numbers as ints or numeric strings (T058).
    if isinstance(v, bool):
        raise ValueError("bool is not a vCPU count")
    if isinstance(v, int):
        return v
    if isinstance(v, float):
        if not v.is_integer():
            raise ValueError("non-integer vCPU count")
        return int(v)
    s = str(v).strip()
    try:
        return int(s)
    except (TypeError, ValueError):
        f = float(s)
        if not f.is_integer():
            raise ValueError("non-integer vCPU count")
        return int(f)

wanted = {"lowPriorityCores", "standardDSv5Family", "standardFSv2Family"}
seen = set()
for item in items:
    if not isinstance(item, dict):
        sys.exit(1)
    name = ((item.get("name") or {}).get("value")) or ""
    if not isinstance(name, str) or name not in wanted:
        continue
    if name in seen:
        continue
    try:
        cur = to_int(item.get("currentValue"))
        lim = to_int(item.get("limit"))
    except (TypeError, ValueError, AttributeError):
        sys.exit(1)
    seen.add(name)
    print("%s\t%s\t%s" % (name, cur, lim))
PYEOF
)
if [ -z "${_azure_usage_norm}" ]; then
    echo "Cannot start: the machine allowance for ${AZURE_LOCATION} could not be read (az vm list-usage gave nothing usable)." >&2
    echo "Check the location and sign-in (az vm list-usage --location ${AZURE_LOCATION}). Nothing was created." >&2
    return 1
fi
AZURE_SPOT_VCPU_CURRENT=""
AZURE_SPOT_VCPU_LIMIT=""
AZURE_DSV5_VCPU_CURRENT=""
AZURE_DSV5_VCPU_LIMIT=""
AZURE_FSV2_VCPU_CURRENT=""
AZURE_FSV2_VCPU_LIMIT=""
while IFS=$'\t' read -r _azure_item _azure_cur _azure_lim; do
    case "${_azure_item}" in
        lowPriorityCores)   AZURE_SPOT_VCPU_CURRENT="${_azure_cur}" ; AZURE_SPOT_VCPU_LIMIT="${_azure_lim}" ;;
        standardDSv5Family) AZURE_DSV5_VCPU_CURRENT="${_azure_cur}" ; AZURE_DSV5_VCPU_LIMIT="${_azure_lim}" ;;
        standardFSv2Family) AZURE_FSV2_VCPU_CURRENT="${_azure_cur}" ; AZURE_FSV2_VCPU_LIMIT="${_azure_lim}" ;;
    esac
done <<< "${_azure_usage_norm}"

_azure_room_ok() {
    # room = limit − current must cover the needed vCPU; integer math.
    [ "$(( ${1} - ${2} ))" -ge "${3}" ]
}

_azure_entryOrFail() {
    # $1 current var name, $2 limit var name, $3 quota family display id
    if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
        echo "Cannot start: the allowance list for ${AZURE_LOCATION} has no '${3}' entry." >&2
        echo "Pick a location that reports it (az vm list-usage --location <loc>). Nothing was created." >&2
        return 1
    fi
    return 0
}

_azure_entryOrFail "${AZURE_SPOT_VCPU_CURRENT}" "${AZURE_SPOT_VCPU_LIMIT}" \
    "lowPriorityCores (Total Regional Low-priority vCPUs)" || return 1
_azure_entryOrFail "${AZURE_DSV5_VCPU_CURRENT}" "${AZURE_DSV5_VCPU_LIMIT}" \
    "standardDSv5Family (Standard DSv5 Family vCPUs)" || return 1
_azure_entryOrFail "${AZURE_FSV2_VCPU_CURRENT}" "${AZURE_FSV2_VCPU_LIMIT}" \
    "standardFSv2Family (Standard FSv2 Family vCPUs)" || return 1

# Which workload pools already exist, and on what priority? JSON parsed by
# field name (the nodepool row order is not promised either).
_azure_existing_pools=$(AZURE_POOLS_JSON="${_azure_pools_json}" python3 - <<'PYEOF'
import json, os

try:
    pools = json.loads(os.environ.get("AZURE_POOLS_JSON") or "[]")
except ValueError:
    pools = []

workload = ("app", "persistent", "o11y", "loadgen")
for p in (pools if isinstance(pools, list) else []):
    name = p.get("name")
    if name not in workload:
        continue
    prio = p.get("priority")
    if prio in (None, "", "null"):
        prio = "regular"
    elif prio == "Spot":
        prio = "spot"
    else:
        prio = str(prio).lower()
    print("%s\t%s" % (name, prio))
PYEOF
)
_azure_have_app=0
_azure_have_persistent=0
_azure_have_o11y=0
_azure_have_loadgen=0
_azure_spot_seen=0
_azure_regular_seen=0
_azure_priority_unknown=""
while IFS=$'\t' read -r _azure_pool_name _azure_priority; do
    [ -n "${_azure_pool_name}" ] || continue
    case "${_azure_pool_name}" in
        app)        _azure_have_app=1 ;;
        persistent) _azure_have_persistent=1 ;;
        o11y)       _azure_have_o11y=1 ;;
        loadgen)    _azure_have_loadgen=1 ;;
    esac
    case "${_azure_priority}" in
        spot)    _azure_spot_seen=1 ;;
        regular) _azure_regular_seen=1 ;;
        *)       _azure_priority_unknown="${_azure_pool_name}=${_azure_priority}" ;;
    esac
done <<< "${_azure_existing_pools}"

if [ -n "${_azure_priority_unknown}" ]; then
    echo "Cannot start: the existing workload pool ${_azure_priority_unknown} reports an unexpected machine priority." >&2
    echo "Expected Spot or regular (null) machines (az aks nodepool list). Nothing was created." >&2
    return 1
fi
if [ "${_azure_spot_seen}" -eq 1 ] && [ "${_azure_regular_seen}" -eq 1 ]; then
    echo "Cannot start: the existing ${AZURE_CLUSTER_NAME} workload pools mix spot and regular machines." >&2
    echo "One cluster runs one mode (AD-002): run 'make cleanup-cluster' and build again. Nothing was created." >&2
    return 1
fi

# Needs are only for the missing resources (T050); the system pool travels
# with the cluster, so it is missing exactly when the cluster is.
_azure_missing_spot=0
_azure_missing_dsv5=0
_azure_missing_fsv2=0
[ "${_azure_have_app}" -eq 0 ] && {
    _azure_missing_spot=$((_azure_missing_spot + 6))
    _azure_missing_dsv5=$((_azure_missing_dsv5 + 6))
}
[ "${_azure_have_persistent}" -eq 0 ] && {
    _azure_missing_spot=$((_azure_missing_spot + 8))
    _azure_missing_dsv5=$((_azure_missing_dsv5 + 8))
}
[ "${_azure_have_o11y}" -eq 0 ] && {
    _azure_missing_spot=$((_azure_missing_spot + 8))
    _azure_missing_dsv5=$((_azure_missing_dsv5 + 8))
}
[ "${_azure_have_loadgen}" -eq 0 ] && {
    _azure_missing_spot=$((_azure_missing_spot + 4))
    _azure_missing_fsv2=$((_azure_missing_fsv2 + 4))
}
_azure_missing_system=0
[ "$(cat "${_azure_jobsdir}/aks.rc" 2>/dev/null)" = "0" ] || _azure_missing_system="${AZURE_DSV5_SYSTEM_NEEDED}"

_azure_allowance_refuse() {
    # $1 quota display name, $2 current, $3 limit, $4 needed, $5 context phrase
    echo "Cannot start: not enough machine allowance in ${AZURE_LOCATION} — ${5:+existing workload pools run on ${5} machines, but }$1 is ${2} used of ${3} allowed, and ${4} free are needed for the missing pools." >&2
    echo "Raise the quota (Azure Portal → Quotas → Compute), free machines, or pick a different location. Nothing was created." >&2
}

if [ "${_azure_spot_seen}" -eq 1 ]; then
    # Resume: keep the spot mode the existing pools use (T050). No regular
    # fallback here — switching mid-build would mix machine types.
    if _azure_room_ok "${AZURE_SPOT_VCPU_LIMIT}" "${AZURE_SPOT_VCPU_CURRENT}" "${_azure_missing_spot}"; then
        AZURE_POOL_MODE="spot"
    else
        _azure_allowance_refuse "lowPriorityCores (Total Regional Low-priority vCPUs)" \
            "${AZURE_SPOT_VCPU_CURRENT}" "${AZURE_SPOT_VCPU_LIMIT}" "${_azure_missing_spot}" "spot"
        return 1
    fi
elif [ "${_azure_regular_seen}" -eq 1 ]; then
    # Resume: keep the regular mode the existing pools use (T050).
    if ! _azure_room_ok "${AZURE_DSV5_VCPU_LIMIT}" "${AZURE_DSV5_VCPU_CURRENT}" "${_azure_missing_dsv5}"; then
        _azure_allowance_refuse "Standard DSv5 Family vCPUs" \
            "${AZURE_DSV5_VCPU_CURRENT}" "${AZURE_DSV5_VCPU_LIMIT}" "${_azure_missing_dsv5}" "regular"
        return 1
    fi
    if ! _azure_room_ok "${AZURE_FSV2_VCPU_LIMIT}" "${AZURE_FSV2_VCPU_CURRENT}" "${_azure_missing_fsv2}"; then
        _azure_allowance_refuse "Standard FSv2 Family vCPUs" \
            "${AZURE_FSV2_VCPU_CURRENT}" "${AZURE_FSV2_VCPU_LIMIT}" "${_azure_missing_fsv2}" "regular"
        return 1
    fi
    AZURE_POOL_MODE="regular"
else
    # Fresh cluster: spot preferred, then regular, else refuse (FR-014).
    if _azure_room_ok "${AZURE_SPOT_VCPU_LIMIT}" "${AZURE_SPOT_VCPU_CURRENT}" "${_azure_missing_spot}" \
            && _azure_room_ok "${AZURE_DSV5_VCPU_LIMIT}" "${AZURE_DSV5_VCPU_CURRENT}" "${_azure_missing_system}"; then
        AZURE_POOL_MODE="spot"
    elif _azure_room_ok "${AZURE_DSV5_VCPU_LIMIT}" "${AZURE_DSV5_VCPU_CURRENT}" "$(( _azure_missing_dsv5 + _azure_missing_system ))" \
            && _azure_room_ok "${AZURE_FSV2_VCPU_LIMIT}" "${AZURE_FSV2_VCPU_CURRENT}" "${_azure_missing_fsv2}"; then
        AZURE_POOL_MODE="regular"
    else
        # Name the first short family with its current and limit numbers; spot
        # fits-but-was-not-chosen is not itself a refusal (regular is the
        # documented fallback), so the message is about the families. The DSv5
        # need includes the always-regular system pool (2 vCPU), so a spot
        # subscription with no DSv5 room is refused here too.
        if ! _azure_room_ok "${AZURE_DSV5_VCPU_LIMIT}" "${AZURE_DSV5_VCPU_CURRENT}" "$(( _azure_missing_dsv5 + _azure_missing_system ))"; then
            _azure_allowance_refuse "Standard DSv5 Family vCPUs" \
                "${AZURE_DSV5_VCPU_CURRENT}" "${AZURE_DSV5_VCPU_LIMIT}" "$(( _azure_missing_dsv5 + _azure_missing_system ))" ""
        else
            _azure_allowance_refuse "Standard FSv2 Family vCPUs" \
                "${AZURE_FSV2_VCPU_CURRENT}" "${AZURE_FSV2_VCPU_LIMIT}" "${_azure_missing_fsv2}" ""
        fi
        return 1
    fi
fi
echo "allowance check: spot ${AZURE_SPOT_VCPU_CURRENT}/${AZURE_SPOT_VCPU_LIMIT} (need ${_azure_missing_spot} for missing workload pools), DSv5 ${AZURE_DSV5_VCPU_CURRENT}/${AZURE_DSV5_VCPU_LIMIT} (need ${_azure_missing_dsv5} + ${_azure_missing_system} for the system pool), FSv2 ${AZURE_FSV2_VCPU_CURRENT}/${AZURE_FSV2_VCPU_LIMIT} (need ${_azure_missing_fsv2}) — chosen mode: ${AZURE_POOL_MODE}"


export AZURE_POOL_MODE AZURE_SPOT_VCPU_CURRENT AZURE_SPOT_VCPU_LIMIT \
    AZURE_DSV5_VCPU_CURRENT AZURE_DSV5_VCPU_LIMIT \
    AZURE_FSV2_VCPU_CURRENT AZURE_FSV2_VCPU_LIMIT \
    AZURE_RBAC_ROLE AZURE_RBAC_SCOPE
AZURE_COMMON_LOADED=1
export AZURE_COMMON_LOADED
