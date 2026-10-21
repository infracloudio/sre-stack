#!/bin/bash
# cart-oom-kill.sh — start, check and remove the Azure scenario 02 fault: the
# cart pod runs out of memory and is killed by the cluster, on AKS
# (specs/007-aks-oom-kill).
#
# Usage: cart-oom-kill.sh start|status|revert
#
# The fault is a memory allowance for the cart container that is too small to
# run in, plus one marker annotation on the cart Deployment; nothing else is
# ever changed. Exit codes: 0 done and the check agreed, 1 the check disagreed
# or the allowance was not set by this fault, 2 usage error, 3 a pre-check
# failed (nothing changed).

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_app_ns="${APP_NS:-robot-shop}"
_release="roboshop"

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
# (contracts §1).
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

    if ! k get deployment cart -n "${_app_ns}" >/dev/null 2>&1; then
        refuse "The demo shop is not installed (no cart Deployment in '${_app_ns}'); run 'make setup-robot-shop'."
    fi

    if [ -z "$(timeout 10 helm list -n "${_app_ns}" --deployed --failed --filter "^${_release}\$" -q 2>/dev/null || true)" ]; then
        refuse "The Helm release '${_release}' has no deployed or failed revision in '${_app_ns}'; run 'make setup-robot-shop'."
    fi
}

# --- readers (data-model §3) -------------------------------------------------
# live reader: the cart container's memory allowance and the fault marker as
# the Deployment holds them right now.
_live_req=""
_live_lim=""
_marker=""

read_live() {
    local base='{.spec.template.spec.containers[?(@.name=="cart")].resources'
    _live_req=$(k get deployment cart -n "${_app_ns}" -o jsonpath="${base}.requests.memory}")
    _live_lim=$(k get deployment cart -n "${_app_ns}" -o jsonpath="${base}.limits.memory}")
    _marker=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.metadata.annotations.sre-stack/oom-fault}')
}

# release reader: the memory allowance the shop is installed with, read from
# the Helm release at run time (FR-008), narrowed to the one cart Deployment
# document (research Finding 4). Refuses rather than guess.
_rel_req=""
_rel_lim=""

read_release() {
    local doc values
    doc=$(timeout 10 helm get manifest "${_release}" -n "${_app_ns}" 2>/dev/null | awk '
        function flush() { if (is_dep && is_cart) printf "%s", doc; doc = ""; is_dep = 0; is_cart = 0 }
        /^---[[:space:]]*$/ { flush(); next }
        { doc = doc $0 "\n" }
        /^kind: Deployment[[:space:]]*$/ { is_dep = 1 }
        /^  name: cart[[:space:]]*$/ { is_cart = 1 }
        END { flush() }
    ' || true)
    values=$(awk '
        /^[[:space:]]*limits:/ { part = "limits" }
        /^[[:space:]]*requests:/ { part = "requests" }
        /^[[:space:]]*memory:/ && part != "" { print part, $2; part = "" }
    ' <<<"${doc}")
    _rel_lim=$(awk '$1 == "limits" { print $2; exit }' <<<"${values}")
    _rel_req=$(awk '$1 == "requests" { print $2; exit }' <<<"${values}")
    if [ -z "${_rel_lim}" ] || [ -z "${_rel_req}" ]; then
        refuse "Could not read the cart memory allowance from the Helm release '${_release}'."
    fi
}

# classifier: marker x (live memory differs from the release) into the four
# rows of data-model §3. Sets _row to 1, 2, 3 or 4.
_row=""

classify() {
    local lowered=no
    read_live
    read_release
    if [ "${_live_req}" != "${_rel_req}" ] || [ "${_live_lim}" != "${_rel_lim}" ]; then
        lowered=yes
    fi
    case "${_marker:+marked}/${lowered}" in
        /no) _row=1 ;;
        /yes) _row=2 ;;
        marked/yes) _row=3 ;;
        marked/no) _row=4 ;;
    esac
}

# Prints the cart container's last and current terminated reason for every cart
# pod, one pod per line.
cart_reasons() {
    k get pods -n "${_app_ns}" -l service=cart -o jsonpath='{range .items[*]}{.status.containerStatuses[?(@.name=="cart")].lastState.terminated.reason}{" "}{.status.containerStatuses[?(@.name=="cart")].state.terminated.reason}{"\n"}{end}' 2>/dev/null || true
}

# Prints one line per cart pod: its name, the cart container's restart count,
# current state and last state (data-model §4).
cart_pod_fields() {
    k get pods -n "${_app_ns}" -l service=cart -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[?(@.name=="cart")].restartCount}{" state="}{.status.containerStatuses[?(@.name=="cart")].state}{" last="}{.status.containerStatuses[?(@.name=="cart")].lastState}{"\n"}{end}' 2>/dev/null || true
}

# Shows the pod fields, then returns them on one line for the RESULT line.
_seen=""

show_pods() {
    local lines
    lines=$(cart_pod_fields)
    if [ -z "${lines}" ]; then
        _seen="no cart pod found"
    else
        _seen=$(tr '\n' ';' <<<"${lines}" | sed 's/;$//; s/;/; /g')
    fi
    echo "${lines:-no cart pod found}"
}

# The pod-template-hash of the newest ReplicaSet of cart: the one whose
# deployment.kubernetes.io/revision matches the Deployment's own. Empty while
# the Deployment has not caught up with its latest change.
newest_hash() {
    local gen seen rev sets
    gen=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.metadata.generation}' 2>/dev/null || true)
    seen=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)
    if [ -z "${gen}" ] || [ "${gen}" != "${seen}" ]; then
        return 0
    fi
    rev=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || true)
    sets=$(k get replicaset -n "${_app_ns}" -l service=cart -o jsonpath='{range .items[*]}{.metadata.annotations.deployment\.kubernetes\.io/revision}{" "}{.metadata.labels.pod-template-hash}{"\n"}{end}' 2>/dev/null || true)
    awk -v rev="${rev}" '$1 == rev { print $2; exit }' <<<"${sets}"
}

# Start's wait: true once a pod of the newest ReplicaSet shows the cart
# container killed for running out of memory. Older pods are ignored so a stale
# kill cannot satisfy it (FR-009).
newest_pod_killed() {
    local hash reasons
    hash=$(newest_hash)
    [ -n "${hash}" ] || return 1
    reasons=$(k get pods -n "${_app_ns}" -l "service=cart,pod-template-hash=${hash}" \
        -o jsonpath='{range .items[*]}{.status.containerStatuses[?(@.name=="cart")].lastState.terminated.reason}{" "}{.status.containerStatuses[?(@.name=="cart")].state.terminated.reason}{"\n"}{end}' 2>/dev/null || true)
    grep -q OOMKilled <<<"${reasons}"
}

# Revert's wait: true once the rollout is finished with one ready cart pod and
# no cart pod shows an out-of-memory kill.
cart_settled() {
    local gen seen updated replicas available ready reasons
    gen=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.metadata.generation}' 2>/dev/null || true)
    seen=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)
    updated=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || true)
    replicas=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.status.replicas}' 2>/dev/null || true)
    available=$(k get deployment cart -n "${_app_ns}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
    [ -n "${gen}" ] && [ "${gen}" = "${seen}" ] || return 1
    [ "${updated}" = 1 ] && [ "${replicas}" = 1 ] && [ "${available}" = 1 ] || return 1
    ready=$(k get pods -n "${_app_ns}" -l service=cart -o jsonpath='{range .items[*]}{.status.containerStatuses[?(@.name=="cart")].ready}{"\n"}{end}' 2>/dev/null || true)
    [ -n "${ready}" ] || return 1
    if grep -qv '^true$' <<<"${ready}"; then
        return 1
    fi
    reasons=$(cart_reasons)
    if grep -q OOMKilled <<<"${reasons}"; then
        return 1
    fi
    return 0
}

# Polls "$@" every 3 s for up to 60 s (contracts §4). Returns 0 as soon as the
# check passes, 1 when the time is up.
wait_for() {
    local began=${SECONDS}
    while :; do
        if "$@"; then
            return 0
        fi
        [ $((SECONDS - began)) -ge 60 ] && return 1
        sleep 3
    done
}

cmd_start() {
    classify
    if [ "${_row}" = 3 ]; then
        echo "The fault is already in place (cart allowance ${_live_lim})."
        echo "RESULT: fault already active"
        return 0
    fi

    echo "Lowering the cart memory allowance to 24Mi (cart container only)..."
    k set resources deployment/cart -n "${_app_ns}" -c cart --requests=memory=8Mi --limits=memory=24Mi
    k annotate deployment/cart -n "${_app_ns}" sre-stack/oom-fault=active --overwrite

    echo "Waiting up to 60s for the cluster to kill the cart container for running out of memory..."
    if wait_for newest_pod_killed; then
        echo "RESULT: fault active (cart container was killed for running out of memory within 60s)"
    else
        show_pods
        echo "RESULT: the allowance is lowered but no out-of-memory kill was observed within 60s; state when last seen: ${_seen}"
        exit 1
    fi
}

cmd_status() {
    classify
    case "${_row}" in
        1)
            if grep -q OOMKilled <<<"$(cart_reasons)"; then
                echo "RESULT: fault not active (cart runs at the chart's allowance), but cart is failing for another reason — this fault is not active"
            else
                echo "RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)"
            fi
            ;;
        2)
            echo "RESULT: the cart allowance (${_live_lim:-none}) was not set by this fault — it is not active"
            exit 1
            ;;
        3)
            echo "RESULT: fault active (cart allowance ${_live_lim}, restarts currently climbing / waiting for the next restart)"
            ;;
        4)
            echo "RESULT: fault not active (the shop's allowance is correct); a leftover marker can be cleared with the revert command"
            ;;
    esac
}

cmd_revert() {
    classify
    case "${_row}" in
        1)
            echo "The fault is not in place."
            echo "RESULT: fault not active; nothing changed"
            return 0
            ;;
        4)
            echo "Only the leftover marker remains; removing it..."
            k annotate deployment/cart -n "${_app_ns}" sre-stack/oom-fault-
            echo "RESULT: fault not active; nothing changed (leftover marker cleared)"
            return 0
            ;;
    esac

    echo "Restoring the cart memory allowance the shop is installed with (requests ${_rel_req}, limits ${_rel_lim})..."
    k set resources deployment/cart -n "${_app_ns}" -c cart --requests=memory="${_rel_req}" --limits=memory="${_rel_lim}"
    k annotate deployment/cart -n "${_app_ns}" sre-stack/oom-fault-

    echo "Waiting up to 60s for cart to run cleanly..."
    if wait_for cart_settled; then
        if [ "${_row}" = 3 ]; then
            echo "RESULT: fault reverted (cart runs at the allowance the shop is installed with, no further out-of-memory kills)"
        else
            echo "RESULT: fault reverted (cart allowance restored to the shop's installed values)"
        fi
    else
        show_pods
        echo "RESULT: the allowance was restored but cart is not running cleanly within 60s; state when last seen: ${_seen}"
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
