#!/bin/bash
# check-o11y-routes-offline.sh — offline tests for
# infra/scripts/cluster/setup-aks-o11y-routes.sh (specs/005 T018, FR-006).
#
# The routes step must not stop setup-aks-o11y on a cluster with no service
# mesh. Each case puts a fake `kubectl` first on PATH that records its calls,
# runs the real script, and asserts on its exit code, message and the
# `apply` calls it made:
#   - no-crd:    no VirtualService type            -> exit 0, skipped, 0 applies
#   - no-ns:     type present, no istio-system     -> exit 0, skipped, 0 applies
#   - mesh:      type and namespace both present   -> exit 0, 4 applies (one per file)
#   - kube-err:  kubectl itself fails              -> exit 1, error, 0 applies, no skip
#   - dry-run:   mesh present, --dry-run           -> exit 0, 4 client-side dry-run applies
#
# No cluster or network needed. Prints one PASS/FAIL line per check; exits
# non-zero when any check fails.

set -u

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
_script="${_repo_root}/infra/scripts/cluster/setup-aks-o11y-routes.sh"
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

# --- fake kubectl ---------------------------------------------------------------
# Records every call to $FAKE_CALLS. FAKE_HAS_CRD / FAKE_HAS_NS (1/0) decide
# whether the two existence checks print the object's name (the script asks
# with --ignore-not-found -o name, so "absent" is empty output, exit 0).
# FAKE_KUBE_FAIL=1 makes every `get` fail like an auth error or timeout.
mkdir -p "${_sandbox}/bin"
cat > "${_sandbox}/bin/kubectl" <<'SH'
#!/bin/bash
echo "$*" >> "${FAKE_CALLS}"
if [ "${FAKE_KUBE_FAIL:-0}" = "1" ] && [ "$1" = "get" ]; then
    echo "error: You must be logged in to the server (Unauthorized)" >&2
    exit 1
fi
case "$*" in
    "get crd virtualservices.networking.istio.io"*)
        [ "${FAKE_HAS_CRD}" = "1" ] && echo "customresourcedefinition.apiextensions.k8s.io/virtualservices.networking.istio.io"
        exit 0 ;;
    "get ns istio-system"*)
        [ "${FAKE_HAS_NS}" = "1" ] && echo "namespace/istio-system"
        exit 0 ;;
    apply*)                                         exit 0 ;;
    *) echo "fake-kubectl: unexpected call: $*" >&2; exit 1 ;;
esac
SH
chmod +x "${_sandbox}/bin/kubectl"

run_case() {  # run_case <case> <has-crd> <has-ns> [script args]; sets RC, OUT, ERR, CALLS
    local _case="$1" _crd="$2" _ns="$3"
    shift 3
    OUT="${_sandbox}/${_case}.out"
    ERR="${_sandbox}/${_case}.err"
    CALLS="${_sandbox}/${_case}.calls"
    : > "${CALLS}"
    FAKE_CALLS="${CALLS}" FAKE_HAS_CRD="${_crd}" FAKE_HAS_NS="${_ns}" \
    PATH="${_sandbox}/bin:${PATH}" bash "${_script}" "$@" > "${OUT}" 2> "${ERR}"
    RC=$?
    APPLIES=$(grep -c '^apply' "${CALLS}")
}

# --- no-crd ---------------------------------------------------------------------
echo "case no-crd:"
run_case no-crd 0 0
check "no-crd:exit-0" "$([ "${RC}" = "0" ] && echo 1 || echo 0)" "rc=${RC}; $(cat "${ERR}")"
check "no-crd:skip message" "$(grep -q 'service mesh is not installed' "${OUT}" && echo 1 || echo 0)" "$(cat "${OUT}")"
check "no-crd:0 applies" "$([ "${APPLIES}" = "0" ] && echo 1 || echo 0)" "applies=${APPLIES}"

# --- no-ns ----------------------------------------------------------------------
echo "case no-ns:"
run_case no-ns 1 0
check "no-ns:exit-0" "$([ "${RC}" = "0" ] && echo 1 || echo 0)" "rc=${RC}; $(cat "${ERR}")"
check "no-ns:names the namespace" "$(grep -q 'no istio-system namespace' "${OUT}" && echo 1 || echo 0)" "$(cat "${OUT}")"
check "no-ns:0 applies" "$([ "${APPLIES}" = "0" ] && echo 1 || echo 0)" "applies=${APPLIES}"

# --- mesh -----------------------------------------------------------------------
echo "case mesh:"
run_case mesh 1 1
check "mesh:exit-0" "$([ "${RC}" = "0" ] && echo 1 || echo 0)" "rc=${RC}; $(cat "${ERR}")"
check "mesh:4 applies" "$([ "${APPLIES}" = "4" ] && echo 1 || echo 0)" "applies=${APPLIES}"
for _f in grafana-vs prometheus-vs istio-podmonitor istio-servicemonitor; do
    check "mesh:applies ${_f}.yaml" "$(grep -q "^apply.* -f .*/${_f}.yaml" "${CALLS}" && echo 1 || echo 0)" "$(cat "${CALLS}")"
done
check "mesh:no skip message" "$(grep -q 'not installed' "${OUT}" && echo 0 || echo 1)" "$(cat "${OUT}")"

# --- kube-err -------------------------------------------------------------------
echo "case kube-err:"
FAKE_KUBE_FAIL=1 run_case kube-err 1 1
check "kube-err:exit-1" "$([ "${RC}" = "1" ] && echo 1 || echo 0)" "rc=${RC}"
check "kube-err:says kubectl failed" "$(grep -q 'kubectl failed' "${ERR}" && echo 1 || echo 0)" "$(cat "${ERR}")"
check "kube-err:no skip message" "$(grep -q 'not installed' "${OUT}" && echo 0 || echo 1)" "$(cat "${OUT}")"
check "kube-err:0 applies" "$([ "${APPLIES}" = "0" ] && echo 1 || echo 0)" "applies=${APPLIES}"

# --- dry-run --------------------------------------------------------------------
echo "case dry-run:"
run_case dry-run 1 1 --dry-run
check "dry-run:exit-0" "$([ "${RC}" = "0" ] && echo 1 || echo 0)" "rc=${RC}; $(cat "${ERR}")"
check "dry-run:4 applies" "$([ "${APPLIES}" = "4" ] && echo 1 || echo 0)" "applies=${APPLIES}"
check "dry-run:every apply is client-side" "$([ "$(grep -c '^apply --dry-run=client ' "${CALLS}")" = "4" ] && echo 1 || echo 0)" "$(cat "${CALLS}")"

echo ""
echo "o11y-routes offline tests: ${total} checks, ${failed} failed"
[ "${failed}" = "0" ]
