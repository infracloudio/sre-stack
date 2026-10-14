#!/bin/bash
# ratings-abort.sh — start, check and remove the scenario 01 HTTP abort fault
# for ratings on AKS (specs/006-aks-http-abort-fault).
#
# Usage: ratings-abort.sh start|status|revert
#
# The fault is one `fault.abort` part (HTTP 500, 100 %) on the `ratings`
# VirtualService; nothing else is ever changed. Exit codes: 0 done and the
# check agreed, 1 the check disagreed or the rule holds someone else's fault,
# 2 usage error, 3 a pre-check failed (nothing changed).

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_app_ns="${APP_NS:-robot-shop}"
_mesh_ns="${ISTIO_NAMESPACE:-istio-system}"

usage() {
    echo "Usage: $(basename "$0") start|status|revert" >&2
    exit 2
}

refuse() {
    echo "$1" >&2
    echo "Nothing was changed." >&2
    exit 3
}

# Every cluster call is capped so a hung API server cannot stall the command
# (data-model §4).
k() {
    kubectl --request-timeout=5s "$@"
}

precheck() {
    if [ "${STACK_MODE:-}" != "aks" ]; then
        refuse "This command is for Azure (STACK_MODE=aks); .env says '${STACK_MODE:-}'."
    fi

    if ! k get nodes -o name >/dev/null 2>&1; then
        refuse "Could not reach the cluster in the current kubectl context."
    fi

    if [ -z "$(k get nodes -l kubernetes.azure.com/cluster -o name 2>/dev/null)" ]; then
        refuse "The current cluster is not an Azure (AKS) cluster."
    fi

    local ready
    ready=$(k get deployment istiod -n "${_mesh_ns}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [ "${ready:-0}" -lt 1 ]; then
        refuse "The service mesh (istiod) is not running; run 'make setup-istio'."
    fi

    if ! k get namespace "${_app_ns}" >/dev/null 2>&1 \
        || ! k get virtualservice ratings -n "${_app_ns}" >/dev/null 2>&1; then
        refuse "The demo shop is not installed; run 'make setup-robot-shop'."
    fi

    # Istio injects the proxy as a native sidecar (an init container with
    # restartPolicy Always) on this cluster, so look in both lists.
    local web_pod containers
    web_pod=$(k get pods -n "${_app_ns}" -l service=web --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "${web_pod}" ]; then
        containers=$(k get pod "${web_pod}" -n "${_app_ns}" \
            -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null || true)
    fi
    if [ -z "${web_pod}" ] || ! grep -qw istio-proxy <<<"${containers:-}"; then
        refuse "The shop's web pod is not in the mesh, so the check would be meaningless."
    fi

    if ! timeout 10 kubectl exec -n "${_app_ns}" deploy/web -c web -- sh -c 'command -v curl' >/dev/null 2>&1; then
        refuse "The web container has no curl; cannot check the result."
    fi
}

# --- rule reader (data-model §1) --------------------------------------------
# Prints the fault part of the ratings rule, and sets _rule_kind to
# none (no fault), ours (abort 500 at 100 %) or other (anything else).
_our_fault='{"abort":{"httpStatus":500,"percentage":{"value":100}}}'
_rule_fault=""
_rule_kind=""

read_rule() {
    _rule_fault=$(k get virtualservice ratings -n "${_app_ns}" -o jsonpath='{.spec.http[0].fault}')
    if [ -z "${_rule_fault}" ]; then
        _rule_kind=none
    elif [ "${_rule_fault}" = "${_our_fault}" ]; then
        _rule_kind=ours
    else
        _rule_kind=other
    fi
}

# --- probe (data-model §2) --------------------------------------------------
# 10 requests from the web pod to ratings, 2 s each, stopping at the first
# one with no answer; the whole exec is cut off after 8 s. Sets _probe_codes
# (space-separated), _probe_body (first non-200 body) and _probe_kind to
# healthy (10 x 200), injected (10 x 500 "fault filter abort") or other.
# Single quotes on purpose: the variables expand inside the web pod, not here.
# shellcheck disable=SC2016
_probe_script='
seen=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  r=$(curl -s -m 2 -w "\n%{http_code}" http://ratings/_health) || true
  c=$(printf "%s" "$r" | tail -n 1)
  echo "$c"
  if [ "$c" != 200 ] && [ "$seen" = 0 ]; then
    seen=1
    echo "BODY $(printf "%s" "$r" | head -n 1 | head -c 80)"
  fi
  [ "$c" = 000 ] && break
done
'
_probe_codes=""
_probe_body=""
_probe_kind=""

probe() {
    local out
    out=$(timeout 8 kubectl exec -n "${_app_ns}" deploy/web -c web -- sh -c "${_probe_script}" 2>/dev/null || true)
    _probe_codes=$(grep -E '^[0-9]+$' <<<"${out}" | tr '\n' ' ' | sed 's/ $//' || true)
    _probe_body=$(grep -m1 '^BODY ' <<<"${out}" | sed 's/^BODY //' || true)
    if [ "${_probe_codes}" = "200 200 200 200 200 200 200 200 200 200" ]; then
        _probe_kind=healthy
    elif [ "${_probe_codes}" = "500 500 500 500 500 500 500 500 500 500" ] \
        && [ "${_probe_body}" = "fault filter abort" ]; then
        _probe_kind=injected
    else
        _probe_kind=other
    fi
}

show_probe() {
    echo "  ${_probe_codes:-no answer}"
    if [ "${_probe_kind}" = other ]; then
        echo "  first unexpected answer body: ${_probe_body:-<none>}"
    fi
}

# Re-run the probe every ~3 s until it reports kind $1 (returns 0), starting
# no new probe once 15 s have gone by (returns 1). With the 8 s probe cap the
# wait ends within about 23 s (data-model §4). Leaves the last probe in _probe_*.
wait_for() {
    local want=$1 began=${SECONDS}
    while :; do
        echo "Checking: 10 test requests from the web pod to ratings..."
        probe
        show_probe
        [ "${_probe_kind}" = "${want}" ] && return 0
        sleep 3
        [ $((SECONDS - began)) -ge 15 ] && return 1
    done
}

cmd_start() {
    read_rule
    local note="fault active"
    case "${_rule_kind}" in
        other)
            echo "The ratings rule holds this fault: ${_rule_fault}"
            echo "RESULT: ratings rule holds a fault this command did not set"
            exit 1
            ;;
        none)
            echo "Adding the fault to the ratings routing rule (every request answered with error 500)..."
            k patch virtualservice ratings -n "${_app_ns}" --type=json \
                -p '[{"op":"add","path":"/spec/http/0/fault","value":{"abort":{"httpStatus":500,"percentage":{"value":100}}}}]'
            ;;
        ours)
            echo "The fault is already in the ratings rule."
            note="fault already active"
            ;;
    esac

    if wait_for injected; then
        echo "RESULT: ${note}"
    else
        echo "RESULT: fault set but not taking effect"
        exit 1
    fi
}

cmd_status() {
    read_rule
    if [ "${_rule_kind}" = other ]; then
        echo "The ratings rule holds this fault: ${_rule_fault}"
        echo "RESULT: ratings rule holds a fault this command did not set"
        exit 1
    fi

    echo "Checking: 10 test requests from the web pod to ratings..."
    probe
    show_probe

    case "${_rule_kind}/${_probe_kind}" in
        none/healthy)
            echo "RESULT: fault not active (10 of 10 requests to ratings answered normally)"
            ;;
        none/*)
            echo "RESULT: ratings failing, not because of this fault"
            exit 1
            ;;
        ours/injected)
            echo "RESULT: fault active (10 of 10 requests to ratings answered with error 500)"
            ;;
        ours/*)
            echo "RESULT: fault set but not taking effect"
            exit 1
            ;;
    esac
}

cmd_revert() {
    read_rule
    local note="fault removed"
    case "${_rule_kind}" in
        other)
            echo "The ratings rule holds this fault: ${_rule_fault}"
            echo "RESULT: ratings rule holds a fault this command did not set"
            exit 1
            ;;
        ours)
            echo "Removing the fault from the ratings routing rule..."
            k patch virtualservice ratings -n "${_app_ns}" --type=json \
                -p '[{"op":"remove","path":"/spec/http/0/fault"}]'
            ;;
        none)
            echo "The fault is not in the ratings rule."
            note="fault was not active"
            ;;
    esac

    if wait_for healthy; then
        echo "RESULT: ${note}"
    elif [ "${_rule_kind}" = none ]; then
        echo "RESULT: ratings failing, not because of this fault"
        exit 1
    else
        echo "RESULT: ratings still failing after the fault was removed — not caused by this fault"
        exit 1
    fi
}

case "${1:-}" in
    start | status | revert) ;;
    *) usage ;;
esac

precheck

case "$1" in
    start) cmd_start ;;
    status) cmd_status ;;
    revert) cmd_revert ;;
esac
