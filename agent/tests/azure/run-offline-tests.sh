#!/bin/bash
# run-offline-tests.sh — the no-cloud tests for the aks setup and cleanup
# paths (specs/001-azure-aks-setup T012/T015, contracts/azure-cli-contract.md §2).
#
# One scenario per contract §2 entry. Each run:
#   - gets a fresh directory with the fake `az` (fake-az.sh) and a fake
#     `kubectl` (fake-kubectl.sh) first on PATH,
#   - sets FAKE_AZ_LOG (the recorded call log) and FAKE_AZ_SCENARIO,
#   - runs the real setup, cleanup, or verify script (STACK_MODE=aks from
#     the tracked .env),
#   - asserts on the exit code, the log content (what was called, in what
#     order, how many times), and the refusal/report text.
#
# Prints one PASS/FAIL line per case plus details; exits non-zero when any
# check fails.

set -u

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_setup="${_repo_root}/infra/scripts/cluster/setup-cluster-aks.sh"
_cleanup="${_repo_root}/infra/scripts/cluster/cleanup-cluster.sh"
_verify="${_repo_root}/infra/scripts/cluster/verify-cluster-aks.sh"
_sandbox=$(mktemp -d "${_here}/.tmp-offline-XXXXXX")
trap 'rm -rf "${_sandbox}"' EXIT

total=0
failed=0

# One check. Usage: check <case-id> <ok:0/1> <detail>
check() {
    total=$((total + 1))
    if [ "$2" = "1" ]; then
        echo "  PASS $1 ${3:-}"
    else
        echo "  FAIL $1 ${3:-}"
        failed=$((failed + 1))
    fi
}

# grep count that never aborts on no-match
count() {
    grep -c "$1" "$2" 2>/dev/null || true
}

# --- the common env for every case -----------------------------------------
export FAKE_USER="rijo-tester@contoso.com"
export FAKE_SUB="11111111-1111-1111-1111-111111111111"

run_setup() {  # $1 <case-id>; sets RC and ERR for the case to assert on
    local _case="$1"
    local _dir="${_sandbox}/${_case}"
    mkdir -p "${_dir}/bin"
    ln -sf "${_here}/fake-az.sh" "${_dir}/bin/az"
    ln -sf "${_here}/fake-kubectl.sh" "${_dir}/bin/kubectl"
    FAKE_AZ_LOG="${_dir}/call.log"
    FAKE_AZ_SCENARIO="${_here}/scenarios/${_case}.sh"
    export FAKE_AZ_LOG FAKE_AZ_SCENARIO
    : > "${FAKE_AZ_LOG}"
    ERR="${_dir}/stderr.txt"
    PATH="${_dir}/bin:${PATH}" bash "${_setup}" 2> "${ERR}"
    RC=$?
}

run_cleanup() {  # $1 <case-id>; sets RC, OUT and ERR for the case
    local _case="$1"
    local _dir="${_sandbox}/${_case}"
    mkdir -p "${_dir}/bin"
    ln -sf "${_here}/fake-az.sh" "${_dir}/bin/az"
    FAKE_AZ_LOG="${_dir}/call.log"
    FAKE_AZ_SCENARIO="${_here}/scenarios/${_case}.sh"
    export FAKE_AZ_LOG FAKE_AZ_SCENARIO
    : > "${FAKE_AZ_LOG}"
    OUT="${_dir}/stdout.txt"
    ERR="${_dir}/stderr.txt"
    PATH="${_dir}/bin:${PATH}" bash "${_cleanup}" > "${OUT}" 2> "${ERR}"
    RC=$?
}

run_verify() {  # $1 <case-id>; sets RC, OUT and ERR for the case
    local _case="$1"
    local _dir="${_sandbox}/${_case}"
    mkdir -p "${_dir}/bin"
    ln -sf "${_here}/fake-az.sh" "${_dir}/bin/az"
    ln -sf "${_here}/fake-kubectl.sh" "${_dir}/bin/kubectl"
    FAKE_AZ_LOG="${_dir}/call.log"
    FAKE_AZ_SCENARIO="${_here}/scenarios/${_case}.sh"
    export FAKE_AZ_LOG FAKE_AZ_SCENARIO
    : > "${FAKE_AZ_LOG}"
    OUT="${_dir}/stdout.txt"
    ERR="${_dir}/stderr.txt"
    PATH="${_dir}/bin:${PATH}" bash "${_verify}" > "${OUT}" 2> "${ERR}"
    RC=$?
}

_log() { echo "${_sandbox}/$1/call.log"; }

# --- happy -------------------------------------------------------------------
echo "case happy:"
run_setup happy
check "happy:exit-0"            "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "happy:one group create"  "$([ "$(count '^az group create ' "$(_log happy)")" = "1" ] && echo 1 || echo 0)" "wanted 1"
check "happy:one cluster create" "$([ "$(count '^az aks create ' "$(_log happy)")" = "1" ] && echo 1 || echo 0)" "wanted 1"
check "happy:four adds"         "$([ "$(count '^az aks nodepool add ' "$(_log happy)")" = "4" ] && echo 1 || echo 0)" "wanted 4"
for _p in app persistent o11y loadgen; do
    check "happy:add ${_p}" "$([ "$(count "^az aks nodepool add .*--name ${_p} " "$(_log happy)")" = "1" ] && echo 1 || echo 0)"
done
check "happy:order group<cluster" "$([ "$(grep -n '^az group create ' "$(_log happy)" | head -n1 | cut -d: -f1)" -lt "$(grep -n '^az aks create ' "$(_log happy)" | head -n1 | cut -d: -f1)" ] && echo 1 || echo 0)"
check "happy:credentials"       "$([ "$(count '^az aks get-credentials ' "$(_log happy)")" = "1" ] && echo 1 || echo 0)" "wanted 1"
check "happy:storageapply"      "$([ "$(count '^kubectl apply -f .*gp2-storageclass.yaml' "$(_log happy)")" = "1" ] && echo 1 || echo 0)" "wanted 1"

# --- already-there ------------------------------------------------------------
echo "case already-there:"
run_setup already-there
check "already-there:exit-0"     "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "already-there:no group create"    "$([ "$(count '^az group create ' "$(_log already-there)")" = "0" ] && echo 1 || echo 0)"
check "already-there:no cluster create"  "$([ "$(count '^az aks create ' "$(_log already-there)")" = "0" ] && echo 1 || echo 0)"
check "already-there:no pool add"        "$([ "$(count '^az aks nodepool add ' "$(_log already-there)")" = "0" ] && echo 1 || echo 0)"
check "already-there:no storage apply"   "$([ "$(count '^kubectl apply ' "$(_log already-there)")" = "0" ] && echo 1 || echo 0)"
check "already-there:version drift warning" "$([ "$(count 'runs Kubernetes' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "already-there:no in-place upgrade" "$([ "$(count '^az aks update' "$(_log already-there)")" = "0" ] && echo 1 || echo 0)"

# --- resume -------------------------------------------------------------------
echo "case resume:"
run_setup resume
check "resume:exit-0" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "resume:no group create"  "$([ "$(count '^az group create ' "$(_log resume)")" = "0" ] && echo 1 || echo 0)"
check "resume:no cluster create" "$([ "$(count '^az aks create ' "$(_log resume)")" = "0" ] && echo 1 || echo 0)"
check "resume:app pool not re-added" "$([ "$(count '^az aks nodepool add .*--name app ' "$(_log resume)")" = "0" ] && echo 1 || echo 0)"
for _p in persistent o11y loadgen; do
    check "resume:added ${_p}" "$([ "$(count "^az aks nodepool add .*--name ${_p} " "$(_log resume)")" = "1" ] && echo 1 || echo 0)"
done
check "resume:kube credentials"       "$([ "$(count '^az aks get-credentials ' "$(_log resume)")" = "1" ] && echo 1 || echo 0)"
check "resume:storageapply"     "$([ "$(count '^kubectl apply ' "$(_log resume)")" = "1" ] && echo 1 || echo 0)"

# --- not-signed-in --------------------------------------------------------------
echo "case not-signed-in:"
run_setup not-signed-in
check "not-signed-in:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "not-signed-in:refusal text" "$([ "$(count 'az login' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "not-signed-in:no create"    "$([ "$(count '^az group create' "$(_log not-signed-in)")" = "0" ] && echo 1 || echo 0)"

# --- bad-location ---------------------------------------------------------------
echo "case bad-location:"
run_setup bad-location
check "bad-location:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "bad-location:refusal text" "$([ "$(count 'is not a real Azure location' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "bad-location:no create"    "$([ "$(count '^az group create' "$(_log bad-location)")" = "0" ] && echo 1 || echo 0)"

# --- missing-vm-size --------------------------------------------------------------
echo "case missing-vm-size:"
run_setup missing-vm-size
check "missing-vm-size:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "missing-vm-size:names F4s_v2" "$([ "$(count 'Standard_F4s_v2 is not offered' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "missing-vm-size:no group create" "$([ "$(count '^az group create' "$(_log missing-vm-size)")" = "0" ] && echo 1 || echo 0)"

# --- rbac-mg-ancestor ---------------------------------------------------------------
echo "case rbac-mg-ancestor:"
run_setup rbac-mg-ancestor
check "rbac-mg-ancestor:exit-0" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "rbac-mg-ancestor:create recorded" "$([ "$(count '^az group create ' "$(_log rbac-mg-ancestor)")" = "1" ] && echo 1 || echo 0)" "wanted 1"

# --- rbac-mg-unrelated --------------------------------------------------------------
echo "case rbac-mg-unrelated:"
run_setup rbac-mg-unrelated
check "rbac-mg-unrelated:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "rbac-mg-unrelated:refusal text" "$([ "$(count 'no permission' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "rbac-mg-unrelated:no create" "$([ "$(count '^az group create' "$(_log rbac-mg-unrelated)")" = "0" ] && echo 1 || echo 0)"

# --- spot-fits ----------------------------------------------------------------------
echo "case spot-fits:"
run_setup spot-fits
check "spot-fits:exit-0" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
for _p in app persistent o11y loadgen; do
    check "spot-fits:${_p} add with spot flags" \
        "$([ "$(count "^az aks nodepool add .*--name ${_p} .*--priority Spot" "$(_log spot-fits)")" = "1" ] && echo 1 || echo 0)"
    check "spot-fits:${_p} add eviction" \
        "$([ "$(count "^az aks nodepool add .*--name ${_p} .*--eviction-policy Delete" "$(_log spot-fits)")" = "1" ] && echo 1 || echo 0)"
done
check "spot-fits:system pool no spot flags" \
    "$([ "$(count '^az aks create .*--priority Spot' "$(_log spot-fits)")" = "0" ] && echo 1 || echo 0)"

# --- spot-short ------------------------------------------------------------------------
echo "case spot-short:"
run_setup spot-short
check "spot-short:exit-0 (regular fallback, no refusal)" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
for _p in app persistent o11y loadgen; do
    check "spot-short:${_p} add without spot flags" \
        "$([ "$(count "^az aks nodepool add .*--name ${_p} .*--priority Spot" "$(_log spot-short)")" = "0" ] && echo 1 || echo 0)"
done
check "spot-short:four adds recorded" "$([ "$(count '^az aks nodepool add ' "$(_log spot-short)")" = "4" ] && echo 1 || echo 0)"

# --- no-room ------------------------------------------------------------------------------
echo "case no-room:"
run_setup no-room
check "no-room:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "no-room:refusal names FSv2" "$([ "$(count 'FSv2' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "no-room:refusal names numbers" "$([ "$(count 'is 0' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "no-room:no group create" "$([ "$(count '^az group create' "$(_log no-room)")" = "0" ] && echo 1 || echo 0)"

# --- system-blocked ---------------------------------------------------------------------
echo "case system-blocked:"
run_setup system-blocked
check "system-blocked:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "system-blocked:refusal names DSv5" "$([ "$(count 'Standard DSv5 Family' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "system-blocked:no group create" "$([ "$(count '^az group create' "$(_log system-blocked)")" = "0" ] && echo 1 || echo 0)"

# --- partial ===========================================================================
echo "case partial:"
run_setup partial
check "partial:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "partial:report header" "$([ "$(count 'Setup stopped partway' "$ERR")" -ge 1 ] && echo 1 || echo 0)"
check "partial:names the group" "$([ "$(count 'resource group ' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "partial:names the cluster" "$([ "$(count 'cluster sre-stack' "$ERR")" -ge 1 ] && echo 1 || echo 0)"
check "partial:names app pool" "$([ "$(count 'node pool app' "$ERR")" -ge 1 ] && echo 1 || echo 0)"
check "partial:names not created" "$([ "$(count 'Not created' "$ERR")" -ge 1 ] && echo 1 || echo 0)"
check "partial:zero delete calls" "$([ "$(count '^az group delete' "$(_log partial)")" = "0" ] && echo 1 || echo 0)"
check "partial:zero deletes of pools" "$([ "$(count '^az aks nodepool delete' "$(_log partial)")" = "0" ] && echo 1 || echo 0)"

# --- cleanup-full ---------------------------------------------------------------
echo "case cleanup-full:"
run_cleanup cleanup-full
check "cleanup-full:exit-0" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "cleanup-full:exactly one delete" "$([ "$(count '^az group delete ' "$(_log cleanup-full)")" = "1" ] && echo 1 || echo 0)" "wanted 1"
check "cleanup-full:delete with --yes" "$([ "$(count '^az group delete .*--yes' "$(_log cleanup-full)")" = "1" ] && echo 1 || echo 0)"
check "cleanup-full:exact-name MC check" "$([ "$(count '^az group show --name MC_' "$(_log cleanup-full)")" = "1" ] && echo 1 || echo 0)" "wanted exactly one exact-name check"
check "cleanup-full:no broad MC search" "$([ "$(count '^az group list' "$(_log cleanup-full)")" = "0" ] && echo 1 || echo 0)"
check "cleanup-full:no create calls" "$([ "$(($(count '^az group create ' "$(_log cleanup-full)") + $(count '^az aks create ' "$(_log cleanup-full)")))" = "0" ] && echo 1 || echo 0)"
check "cleanup-full:no create probes" "$([ "$(($(count '^az role assignment list' "$(_log cleanup-full)") + $(count '^az account list-locations' "$(_log cleanup-full)") + $(count '^az vm list-usage' "$(_log cleanup-full)") + $(count '^az rest ' "$(_log cleanup-full)")))" = "0" ] && echo 1 || echo 0)" "$(grep -E '^az (role assignment list|account list-locations|vm list-usage|rest )' "$(_log cleanup-full)" || true)"

# --- cleanup-empty --------------------------------------------------------------
echo "case cleanup-empty:"
run_cleanup cleanup-empty
check "cleanup-empty:exit-0" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "cleanup-empty:nothing-to-clean text" "$([ "$(count 'Nothing to clean' "$OUT")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$OUT")"
check "cleanup-empty:zero deletes" "$([ "$(count '^az group delete' "$(_log cleanup-empty)")" = "0" ] && echo 1 || echo 0)"
check "cleanup-empty:zero MC checks" "$([ "$(count '^az group show' "$(_log cleanup-empty)")" = "0" ] && echo 1 || echo 0)"

# --- mc-lingers -----------------------------------------------------------------
echo "case mc-lingers:"
run_cleanup mc-lingers
check "mc-lingers:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "mc-lingers:warning names our MC group" "$([ "$(count 'MC_' "$ERR")" -ge 1 ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "mc-lingers:warning gives removal command" "$([ "$(count 'az group delete --name MC_' "$ERR")" -ge 1 ] && echo 1 || echo 0)"
check "mc-lingers:one delete only" "$([ "$(count '^az group delete' "$(_log mc-lingers)")" = "1" ] && echo 1 || echo 0)" "wanted 1"
check "mc-lingers:exact-name MC check only" "$([ "$(count '^az group show --name MC_' "$(_log mc-lingers)")" = "1" ] && echo 1 || echo 0)"
check "mc-lingers:no others' MC groups touched" "$([ "$(count 'MC_alice\|MC_bob' "$(_log mc-lingers)")" = "0" ] && echo 1 || echo 0)"
check "mc-lingers:no broad MC search" "$([ "$(count '^az group list' "$(_log mc-lingers)")" = "0" ] && echo 1 || echo 0)"

# --- verify-ok ----------------------------------------------------------------
echo "case verify-ok:"
run_verify verify-ok
check "verify-ok:exit-0" "$([ "${RC:-}" = "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "verify-ok:control plane tick" "$([ "$(count '✓ control plane: Succeeded / Running' "$OUT")" = "1" ] && echo 1 || echo 0)" "$(cat "$OUT")"
for _p in app persistent o11y loadgen; do
    check "verify-ok:${_p} tick" "$([ "$(count "✓ ${_p}:" "$OUT")" = "1" ] && echo 1 || echo 0)"
done
check "verify-ok:zero mismatches" "$([ "$(count 'report: 0 mismatch' "$OUT")" = "1" ] && echo 1 || echo 0)" "$(cat "$OUT")"
check "verify-ok:read-only" "$([ "$(($(count '^az .*create' "$(_log verify-ok)") + $(count '^az .*delete' "$(_log verify-ok)") + $(count '^kubectl apply' "$(_log verify-ok)")))" = "0" ] && echo 1 || echo 0)"

# --- verify-pool-mismatch -------------------------------------------------------
echo "case verify-pool-mismatch:"
run_verify verify-pool-mismatch
check "verify-pool-mismatch:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "verify-pool-mismatch:app count" "$([ "$(count '✗ app: count 99' "$ERR")" = "1" ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "verify-pool-mismatch:persistent size" "$([ "$(count '✗ persistent: size' "$ERR")" = "1" ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "verify-pool-mismatch:o11y taint" "$([ "$(count 'missing taint o11y=true:NoSchedule' "$ERR")" = "1" ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "verify-pool-mismatch:loadgen missing" "$([ "$(count '✗ loadgen: pool missing' "$ERR")" = "1" ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "verify-pool-mismatch:report counts" "$([ "$(count 'report: 4 mismatch' "$OUT")" = "1" ] && echo 1 || echo 0)" "$(cat "$OUT")"
check "verify-pool-mismatch:read-only" "$([ "$(($(count '^az .*create' "$(_log verify-pool-mismatch)") + $(count '^az .*delete' "$(_log verify-pool-mismatch)") + $(count '^kubectl apply' "$(_log verify-pool-mismatch)")))" = "0" ] && echo 1 || echo 0)"

# --- verify-namespace-extra -------------------------------------------------------
echo "case verify-namespace-extra:"
run_verify verify-namespace-extra
check "verify-namespace-extra:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "verify-namespace-extra:names team-a" "$([ "$(count '✗ namespace team-a exists' "$ERR")" = "1" ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "verify-namespace-extra:pools still pass" "$([ "$(count '✓ app:' "$OUT")" = "1" ] && echo 1 || echo 0)"
check "verify-namespace-extra:report counts" "$([ "$(count 'report: 1 mismatch' "$OUT")" = "1" ] && echo 1 || echo 0)" "$(cat "$OUT")"

# --- verify-kubectl-fails ---------------------------------------------------------
echo "case verify-kubectl-fails:"
run_verify verify-kubectl-fails
check "verify-kubectl-fails:exit-nonzero" "$([ "${RC:-}" != "0" ] && echo 1 || echo 0)" "rc=${RC:-}"
check "verify-kubectl-fails:failed read is a mismatch" "$([ "$(count '✗ namespaces: kubectl get namespaces failed' "$ERR")" = "1" ] && echo 1 || echo 0)" "$(cat "$ERR")"
check "verify-kubectl-fails:report counts" "$([ "$(count 'report: 1 mismatch' "$OUT")" = "1" ] && echo 1 || echo 0)" "$(cat "$OUT")"

echo ""
echo "offline tests: ${total} checks, ${failed} failed"
[ "${failed}" = "0" ]
