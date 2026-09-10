#!/bin/bash
# verify-cluster-aks.sh — read-only check of the aks cluster (STACK_MODE=aks).
#
# specs/001-azure-aks-setup T010. Never calls create/update/delete: reads
# `az aks show`, `az aks nodepool list`, and `kubectl get namespaces`, compares
# against the data-model §3 table, and prints one plain ✓/✗ line per resource
# (contracts/azure-cli-contract.md §1). Exit non-zero when anything mismatches
# so callers can gate on it; the report itself is the SC-004 evidence.

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/infra/scripts/cluster/azure-common.sh" || exit 1

failures=0

_bad() {  # print a ✗ line plus the expectation, count the failure
    echo "✗ $1" >&2
    echo "   expected: $2" >&2
    failures=$((failures + 1))
}

# --- 1. control plane -----------------------------------------------------------
_read=$(az aks show --resource-group "${AZURE_RESOURCE_GROUP}" --name "${AZURE_CLUSTER_NAME}" \
    --query '{s: provisioningState, p: powerState.code}' --output tsv 2>/dev/null)
_state="${_read%%	*}"
_power="${_read##*	}"
if [ -z "${_read}" ]; then
    _bad "control plane: cluster ${AZURE_CLUSTER_NAME} not found in ${AZURE_RESOURCE_GROUP}" "set up by make setup-cluster"
elif [ "${_state}" = "Succeeded" ] && [ "${_power}" = "Running" ]; then
    echo "✓ control plane: Succeeded / Running"
else
    _bad "control plane: provisioningState ${_state:-unknown}, powerState ${_power:-unknown}" "Succeeded / Running"
fi

# --- 2. node pools vs the §3 table (JSON shapes from research.md A7) --------------
_pools_json=$(az aks nodepool list --resource-group "${AZURE_RESOURCE_GROUP}" --cluster-name "${AZURE_CLUSTER_NAME}" \
    --query '[].{name: name, mode: mode, count: count, min: minCount, max: maxCount, size: vmSize, labels: nodeLabels, taints: nodeTaints, spot: scaleSetPriority}' \
    --output json 2>/dev/null)
if [ -z "${_pools_json}" ] || [ "${_pools_json}" = "[]" ]; then
    _bad "node pools: az aks nodepool list returned nothing" "one system pool + the four workload pools"
fi

if [ -n "${_pools_json}" ] && [ "${_pools_json}" != "[]" ]; then
    _pool_rc=0
    VERIFY_POOL_JSON="${_pools_json}" \
    VERIFY_MODE="${AZURE_POOL_MODE}" \
    VERIFY_AUTO_TAINT="kubernetes.azure.com/scalesetpriority=spot:NoSchedule" \
    python3 <<'EOF' || _pool_rc=$?
import json, os, sys

try:
    pools = json.loads(os.environ["VERIFY_POOL_JSON"])
except (KeyError, ValueError):
    sys.exit(255)
if not isinstance(pools, list):
    sys.exit(255)
mode = os.environ["VERIFY_MODE"]
auto = os.environ["VERIFY_AUTO_TAINT"]
fail = 0

def bad(line, expect):
    global fail
    print("✗ " + line, file=sys.stderr)
    print("   expected: " + expect, file=sys.stderr)
    fail += 1

def good(line):
    print("✓ " + line)

def clean(p):  # older CLI/stand-in shapes may render a literal "null"
    out = dict(p)
    for k, v in list(out.items()):
        if v == "null":
            out[k] = None
    return out

TABLE = {  # data-model §3
    "app":        ("Standard_D2s_v5", 3, 6, "app",        None),
    "persistent": ("Standard_D4s_v5", 2, 2, "persistent", "persistent=true:NoSchedule"),
    "o11y":       ("Standard_D4s_v5", 2, 3, "o11y",       "o11y=true:NoSchedule"),
    "loadgen":    ("Standard_F4s_v2", 1, 1, "loadgen",    "loadgen=true:NoSchedule"),
}

system = [p for p in pools if p.get("mode") == "System"]
if len(system) != 1:
    bad("system pool: expected exactly one mode=System pool, found " + repr(len(system)),
        "one system pool (Azure names it itself, e.g. nodepool1)")
else:
    # the system pool is never one of the §3 pool names; match by mode (research fact 2)
    s = clean(system[0])
    errs = []
    if s.get("count") != 1:
        errs.append("count " + repr(s.get("count")) + " (want 1)")
    if s.get("size") != "Standard_D2s_v5":
        errs.append("size " + repr(s.get("size")) + " (want Standard_D2s_v5)")
    if s.get("spot") not in (None, "Regular"):
        errs.append("scaleSetPriority " + repr(s.get("spot")) + " (want null/Regular)")
    if s.get("taints"):
        errs.append("taints " + repr(s.get("taints")) + " (want none)")
    if errs:
        bad("system pool: " + "; ".join(errs), "1 node, Standard_D2s_v5, regular, no taints")
    else:
        good("system pool: 1 node, Standard_D2s_v5, regular — Azure housekeeping pool")

found = {p.get("name"): p for p in pools}
for name, (size, mn, mx, label, want_taint) in TABLE.items():
    row = found.get(name)
    if row is None:
        bad(name + ": pool missing", name + " in the nodepool list")
        continue
    row = clean(row)
    count = row.get("count")
    errs = []
    if not (isinstance(count, int) and mn <= count <= mx):
        errs.append("count " + repr(count) + " (want " + str(mn) + "–" + str(mx) + ")")
    if row.get("size") != size:
        errs.append("size " + repr(row.get("size")) + " (want " + size + ")")
    labels = row.get("labels") or {}
    if labels.get("workload") != label:
        errs.append("label workload=" + repr(labels.get("workload")) + " (want " + label + ")")
    if row.get("min") != mn or row.get("max") != mx:
        errs.append("autoscaler bounds " + repr(row.get("min")) + "–" + repr(row.get("max"))
                    + " (want " + str(mn) + "–" + str(mx) + ")")
    want = [want_taint] if want_taint else []
    if mode == "spot":
        if row.get("spot") != "Spot":
            errs.append("scaleSetPriority " + repr(row.get("spot")) + " (want Spot: the check chose spot)")
        allowed = want + [auto]
    else:
        if row.get("spot") not in (None, "Regular"):
            errs.append("scaleSetPriority " + repr(row.get("spot")) + " (want null/Regular: mode regular)")
        allowed = want
    taints = row.get("taints") or []
    for t in taints:
        if t not in allowed:
            errs.append("unexpected taint " + t)
    for t in want:
        if t not in taints:
            errs.append("missing taint " + t)
    if errs:
        bad(name + ": " + "; ".join(errs),
            size + ", " + str(mn) + "–" + str(mx) + " nodes, label workload=" + label
            + (", taint " + want_taint if want_taint else ", no extra taint")
            + (" (Azure's own spot auto-taint is allowed)" if mode == "spot" else "")
            + ", " + ("spot" if mode == "spot" else "regular"))
    else:
        word = "spot" if mode == "spot" else "regular"
        good(name + ": " + str(count) + " nodes, " + size + ", label workload=" + label
             + ", " + word + " — matches Amazon")

sys.exit(min(fail, 254))
EOF
    if [ "${_pool_rc}" -eq 255 ]; then
        _bad "node pools: verifier failed while reading pool data" "json shaped like research.md A7"
    elif [ "${_pool_rc}" -gt 0 ]; then
        failures=$((failures + _pool_rc))
    fi
fi

# --- 3. namespaces (FR-008) -------------------------------------------------------
# Fail closed: a failed or empty read must count as a mismatch, not vanish
# into a list that looks like an empty cluster.
if ! _ns_raw=$(kubectl get namespaces --output name 2>/dev/null) || [ -z "${_ns_raw}" ]; then
    _bad "namespaces: kubectl get namespaces failed or returned nothing" \
        "a reachable cluster (check kubectl and the kubeconfig context, then re-run)"
else
    _ns=$(printf '%s\n' "${_ns_raw}" | sed 's,namespace/,,')
    for _n in ${_ns}; do
        case "${_n}" in
            default|kube-*) ;;
            *) _bad "namespace ${_n} exists" "an empty cluster holds only default and kube-* namespaces" ;;
        esac
    done
fi

echo "report: ${failures} mismatch(es)"
if [ "${failures}" -gt 0 ]; then
    exit 1
fi
