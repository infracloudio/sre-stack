#!/bin/bash
# verify-aks-observability.sh — read-only live check of the AKS observability
# stack (specs/002-azure-observability-stack T026, FR-012).
#
# Never mutates anything: reads `kubectl get pods -n monitoring -o json` and
# `kubectl get nodes -o json`, then queries Grafana's own datasource-health
# API for the Prometheus and Loki datasources. Prints one plain PASS/FAIL
# line per check:
#
#   1. Every monitoring/Kiali workload's actual node — each lands on an
#      `o11y` node, except the two per-machine helpers (the Alloy DaemonSet
#      and node-exporter), which the report instead checks for coverage of
#      every node pool (system, app, persistent, o11y, loadgen).
#   2. Both Grafana datasources' actual health
#      (/api/datasources/<id>/health for the Prometheus and Loki IDs).
#
# Mirrors the reporting style of story 001's
# infra/scripts/cluster/verify-cluster-aks.sh. Exit non-zero when anything
# fails so callers can gate on it; the report is the acceptance evidence.

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_monitoring_ns="${MONITORING_NS:-monitoring}"
failures=0

_fail() { echo "FAIL $1" >&2; failures=$((failures + 1)); }
_pass() { echo "PASS $1"; }

if ! command -v kubectl >/dev/null 2>&1; then
    echo "FAIL cannot run: kubectl not found (install it, then re-run)." >&2
    exit 1
fi

# --- cluster reachable? fail clearly, never hang (SC-006 prerequisite) ---------
if ! kubectl get nodes -o name --request-timeout=10s >/dev/null 2>&1; then
    echo "FAIL cannot run: no cluster is reachable through the current kubeconfig." >&2
    echo "Check 'kubectl config current-context' and the cluster's availability, then re-run." >&2
    exit 1
fi

# --- 1. workload placement ------------------------------------------------------
_kubectl_tmp=$(mktemp -d)
trap 'rm -rf "${_kubectl_tmp}"' EXIT
kubectl get pods -n "${_monitoring_ns}" -o json --request-timeout=30s 2>/dev/null > "${_kubectl_tmp}/pods.json" || echo '{"items": []}' > "${_kubectl_tmp}/pods.json"
kubectl get nodes -o json --request-timeout=30s 2>/dev/null > "${_kubectl_tmp}/nodes.json" || echo '{"items": []}' > "${_kubectl_tmp}/nodes.json"

# The Python block exits with its own FAIL count (0 = all placement checks
# passed), so every misplaced pod or uncovered pool counts as a failure.
VERIFY_PODS_FILE="${_kubectl_tmp}/pods.json" VERIFY_NODES_FILE="${_kubectl_tmp}/nodes.json" \
VERIFY_MONITORING_NS="${_monitoring_ns}" \
python3 <<'EOF' || failures=$((failures + $?))
import json, os, sys

try:
    pods = json.load(open(os.environ["VERIFY_PODS_FILE"])).get("items", [])
    nodes = json.load(open(os.environ["VERIFY_NODES_FILE"])).get("items", [])
except (KeyError, ValueError, OSError):
    print("FAIL workload placement: kubectl output could not be parsed", file=sys.stderr)
    sys.exit(1)

# node name -> workload label ("" when unlabeled = the AKS system pool)
pool_of = {}
for node in nodes:
    labels = (node.get("metadata") or {}).get("labels") or {}
    pool_of[node["metadata"]["name"]] = labels.get("workload", "system")

pools = sorted(set(pool_of.values()))

# Per-machine helpers run on every pool (spec Clarification 2026-10-05):
# match by owner DaemonSet name (Alloy) or the node-exporter label.
def daemonset_name(pod):
    for owner in ((pod.get("metadata") or {}).get("ownerReferences") or []):
        if owner.get("kind") == "DaemonSet":
            return owner.get("name") or ""
    return ""

helpers = {}   # helper id -> set of pools covered
others = []    # (pod name, pool, problems)
for pod in pods:
    meta = pod.get("metadata") or {}
    name = meta.get("name") or ""
    spec = pod.get("spec") or {}
    nodename = spec.get("nodeName") or ""
    pool = pool_of.get(nodename)
    ds = daemonset_name(pod)
    labels = meta.get("labels") or {}
    if ds == "alloy" or "node-exporter" in ds:
        key = ds or "per-machine helper"
        helpers.setdefault(key, set())
        helpers[key].add(pool)
        continue
    if pool == "o11y":
        others.append((name, pool, []))
    else:
        others.append((name, pool,
                       [f"expected an o11y node (pool={pool or 'unknown'})"]))

failed = 0
placed = 0
for name, pool, problems in others:
    if problems:
        for problem in problems:
            print(f"FAIL {name}: {problem}", file=sys.stderr)
            failed += 1
    else:
        print(f"PASS {name}: on o11y pool")
    placed += 1
if placed == 0:
    print("FAIL no monitoring workload pods found to check "
          "(is the stack installed in namespace "
          f"{os.environ['VERIFY_MONITORING_NS']}?)", file=sys.stderr)
    sys.exit(1)

# A helper with no pods at all is missing, not merely short of a pool.
for expected in ("alloy", "node-exporter"):
    if not any(expected in ds for ds in helpers):
        print(f"FAIL per-machine helper {expected}: no pods found", file=sys.stderr)
        failed += 1

missing_helper_pools = {}
for ds, covered in sorted(helpers.items()):
    gaps = [p for p in pools if p not in covered]
    if gaps:
        missing_helper_pools[ds] = gaps
if missing_helper_pools:
    for ds, gaps in sorted(missing_helper_pools.items()):
        print(f"FAIL per-machine helper {ds}: not running on every node pool "
              f"(missing: {', '.join(gaps)})", file=sys.stderr)
        failed += 1
else:
    for ds, covered in sorted(helpers.items()):
        print(f"PASS per-machine helper {ds}: running on every node pool "
              f"({', '.join(sorted(covered))})")

# Exit status carries the FAIL count (capped well below 256) to the wrapper.
sys.exit(min(failed, 100))
EOF

# --- 2. Grafana datasources' actual health (FR-006) ------------------------------
_lb=$(kubectl get svc istio-ingressgateway -n istio-system \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --request-timeout=10s 2>/dev/null)
if [ -z "${_lb}" ]; then
    _fail "ingress gateway: no external IP (the gateway service may still be provisioning)"
else
    _grafana_secret_name="prometheus-stack-grafana"
    _user=$(kubectl get secret "${_grafana_secret_name}" -n "${_monitoring_ns}" \
        -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    _passkey=$(kubectl get secret "${_grafana_secret_name}" -n "${_monitoring_ns}" \
        -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [ -z "${_user}" ] || [ -z "${_passkey}" ]; then
        _fail "Grafana admin credentials: could not read secret ${_grafana_secret_name} in namespace ${_monitoring_ns}"
    else
        _base="http://${_lb}/grafana"
        _list=$(curl -sS --max-time 15 -u "${_user}:${_passkey}" "${_base}/api/datasources" 2>/dev/null)
        for _ds in Prometheus loki; do
            _uid=$(printf '%s' "${_list}" | \
                python3 -c "import json,sys
try: rows=json.load(sys.stdin)
except Exception: sys.exit(1)
for r in rows if isinstance(rows, list) else []:
    if str(r.get('name','')).lower()=='${_ds}'.lower(): print(r.get('uid') or '')" 2>/dev/null)
            if [ -z "${_uid}" ]; then
                _fail "datasource ${_ds}: not found in Grafana's datasource list"
                continue
            fi
            _health=$(curl -sS --max-time 15 -u "${_user}:${_passkey}" \
                "${_base}/api/datasources/uid/${_uid}/health" 2>/dev/null)
            case "${_health}" in
                *'"status": "OK"'*|*'"status":"OK"'*)
                    _pass "datasource ${_ds}: healthy (Grafana reports OK)" ;;
                *"Not found"*)
                    # Some Grafana 10.x versions expose no /health route for
                    # the Loki plugin. Fall back to what the UI does: run a
                    # minimal query and let Loki's answer prove reachability.
                    _probe=$(curl -sS --max-time 15 -u "${_user}:${_passkey}" \
                        -H "Content-Type: application/json" \
                        -d '{"queries":[{"refId":"probe","expr":"{job=~\".+\"}","queryType":"range","limit":1,"datasource":{"type":"loki","uid":"'${_uid}'"}}],"from":"now-5m","to":"now"}' \
                        "${_base}/api/ds/query" 2>/dev/null)
                    case "${_probe}" in
                        *'"status":200'*|*'"status": 200'*)
                            _pass "datasource ${_ds}: reachable (query answered; /health route unavailable in this Grafana version)" ;;
                        *"too many unhealthy"*|"")
                            _fail "datasource ${_ds}: query probe got no usable answer (Grafana may not be reachable yet)" ;;
                        *)
                            _fail "datasource ${_ds}: query probe did not return data (${_probe})" ;;
                    esac ;;
                "")
                    _fail "datasource ${_ds}: health check returned nothing (Grafana may not be reachable yet)" ;;
                *)
                    _fail "datasource ${_ds}: health check did not report OK (${_health})" ;;
            esac
        done
    fi
fi

echo "observability verification: ${failures} failure(s)"
[ "${failures}" = "0" ]
