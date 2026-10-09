#!/bin/bash
# check-verify-observability-offline.sh — offline tests for
# agent/scripts/verify-aks-observability.sh (specs/002-azure-observability-stack
# FR-012 / SC-006).
#
# The verifier is the story's acceptance evidence, so it must be able to fail.
# Each case puts a fake `kubectl` and a fake `curl` first on PATH, feeds the
# real verifier made-up pods and nodes, and asserts on its exit code and
# report:
#   - ok:            every pod on o11y, both helpers on every pool -> exit 0
#   - misplaced:     a Grafana pod on the app pool                 -> exit 1
#   - helper-gap:    Alloy missing from the app pool               -> exit 1
#   - helper-absent: no node-exporter pods at all                  -> exit 1
#
# No cluster or network needed. Prints one PASS/FAIL line per check; exits
# non-zero when any check fails.

set -u

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
_verify="${_repo_root}/agent/scripts/verify-aks-observability.sh"
_sandbox=$(mktemp -d)
trap 'rm -rf "${_sandbox}"' EXIT

total=0
failed=0

# One check. Usage: check <case-id> <ok:0/1> <detail>
check() {
    total=$((total + 1))
    if [ "$2" = "1" ]; then
        echo "  PASS $1"
    else
        echo "  FAIL $1 ${3:-}"
        failed=$((failed + 1))
    fi
}

# --- fakes ----------------------------------------------------------------------
mkdir -p "${_sandbox}/bin"
cat > "${_sandbox}/bin/kubectl" <<'SH'
#!/bin/bash
# Answers only the reads verify-aks-observability.sh makes.
case "$*" in
    "get nodes -o name"*)       echo "node/fake" ;;
    "get nodes -o json"*)       cat "${FAKE_NODES_JSON}" ;;
    "get pods -n monitoring -o json"*) cat "${FAKE_PODS_JSON}" ;;
    "get svc istio-ingressgateway"*) printf '10.0.0.1' ;;
    *admin-user*)               printf 'YWRtaW4=' ;;   # "admin"
    *admin-password*)           printf 'ZmFrZQ==' ;;   # "fake"
    *) echo "fake-kubectl: unexpected call: $*" >&2; exit 1 ;;
esac
SH
cat > "${_sandbox}/bin/curl" <<'SH'
#!/bin/bash
# Grafana answers: two datasources, both healthy.
for _arg in "$@"; do _url="${_arg}"; done
case "${_url}" in
    */api/datasources) echo '[{"name":"Prometheus","uid":"p"},{"name":"Loki","uid":"l"}]' ;;
    */health)          echo '{"status":"OK"}' ;;
    *) echo "fake-curl: unexpected url: ${_url}" >&2; exit 1 ;;
esac
SH
chmod +x "${_sandbox}/bin/kubectl" "${_sandbox}/bin/curl"

# Nodes: one per pool. Pods: built per case from a "name=node" list, plus
# per-machine helper pods ("ds:name=node", owned by DaemonSet ds).
python3 - "${_sandbox}/nodes.json" <<'PY'
import json, sys
nodes = [("sys-0", None), ("app-0", "app"), ("o11y-0", "o11y")]
items = [{"metadata": {"name": n, "labels": ({"workload": w} if w else {})}}
         for n, w in nodes]
json.dump({"items": items}, open(sys.argv[1], "w"))
PY

make_pods() {  # make_pods <case> <entry>...
    local _case="$1"
    shift
    python3 - "${_sandbox}/${_case}-pods.json" "$@" <<'PY'
import json, sys
items = []
for entry in sys.argv[2:]:
    owner, _, rest = entry.rpartition(":")
    name, node = rest.split("=")
    meta = {"name": name}
    if owner:
        meta["ownerReferences"] = [{"kind": "DaemonSet", "name": owner}]
    items.append({"metadata": meta, "spec": {"nodeName": node}})
json.dump({"items": items}, open(sys.argv[1], "w"))
PY
}

_ne="prometheus-stack-prometheus-node-exporter"
_helpers_all=(
    "alloy:alloy-a=sys-0" "alloy:alloy-b=app-0" "alloy:alloy-c=o11y-0"
    "${_ne}:ne-a=sys-0" "${_ne}:ne-b=app-0" "${_ne}:ne-c=o11y-0"
)

run_case() {  # run_case <case>; sets RC, OUT, ERR
    local _case="$1"
    OUT="${_sandbox}/${_case}.out"
    ERR="${_sandbox}/${_case}.err"
    FAKE_NODES_JSON="${_sandbox}/nodes.json" \
    FAKE_PODS_JSON="${_sandbox}/${_case}-pods.json" \
    PATH="${_sandbox}/bin:${PATH}" bash "${_verify}" > "${OUT}" 2> "${ERR}"
    RC=$?
}

# --- ok -------------------------------------------------------------------------
echo "case ok:"
make_pods ok "grafana-0=o11y-0" "prom-0=o11y-0" "${_helpers_all[@]}"
run_case ok
check "ok:exit-0" "$([ "${RC}" = "0" ] && echo 1 || echo 0)" "rc=${RC}; $(cat "${ERR}")"
check "ok:0 failures" "$(grep -q '0 failure(s)' "${OUT}" && echo 1 || echo 0)" "$(cat "${OUT}")"

# --- misplaced ------------------------------------------------------------------
echo "case misplaced:"
make_pods misplaced "grafana-0=app-0" "prom-0=o11y-0" "${_helpers_all[@]}"
run_case misplaced
check "misplaced:exit-nonzero" "$([ "${RC}" != "0" ] && echo 1 || echo 0)" "rc=${RC}"
check "misplaced:names the pod" "$(grep -q 'FAIL grafana-0: expected an o11y node (pool=app)' "${ERR}" && echo 1 || echo 0)" "$(cat "${ERR}")"
check "misplaced:1 failure" "$(grep -q '1 failure(s)' "${OUT}" && echo 1 || echo 0)" "$(cat "${OUT}")"

# --- helper-gap -----------------------------------------------------------------
echo "case helper-gap:"
make_pods helper-gap "grafana-0=o11y-0" \
    "alloy:alloy-a=sys-0" "alloy:alloy-c=o11y-0" \
    "${_ne}:ne-a=sys-0" "${_ne}:ne-b=app-0" "${_ne}:ne-c=o11y-0"
run_case helper-gap
check "helper-gap:exit-nonzero" "$([ "${RC}" != "0" ] && echo 1 || echo 0)" "rc=${RC}"
check "helper-gap:names the pool" "$(grep -q 'FAIL per-machine helper alloy: not running on every node pool (missing: app)' "${ERR}" && echo 1 || echo 0)" "$(cat "${ERR}")"

# --- helper-absent --------------------------------------------------------------
echo "case helper-absent:"
make_pods helper-absent "grafana-0=o11y-0" \
    "alloy:alloy-a=sys-0" "alloy:alloy-b=app-0" "alloy:alloy-c=o11y-0"
run_case helper-absent
check "helper-absent:exit-nonzero" "$([ "${RC}" != "0" ] && echo 1 || echo 0)" "rc=${RC}"
check "helper-absent:names the helper" "$(grep -q 'FAIL per-machine helper node-exporter: no pods found' "${ERR}" && echo 1 || echo 0)" "$(cat "${ERR}")"

echo ""
echo "verify-observability offline tests: ${total} checks, ${failed} failed"
[ "${failed}" = "0" ]
