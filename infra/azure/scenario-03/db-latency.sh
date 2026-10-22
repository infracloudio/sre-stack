#!/bin/bash
# db-latency.sh — start, check and remove the Azure scenario 03 fault: the
# shop's database answers slowly, on AKS (specs/008-aks-db-latency-fault).
#
# Usage: db-latency.sh start|status|revert
#
# The fault is three MySQL Rewriter rules that put a fixed wait in front of the
# two shipping lookups and the ratings lookup; the answers stay identical and
# no shop data is written. Exit codes: 0 done and the check agreed, 1 the check
# disagreed, 2 usage error, 3 a pre-check failed (nothing changed).

set -euo pipefail

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi
# shellcheck disable=SC1091
source "${_repo_root}/.env"

cd "${_repo_root}"

_app_ns="${APP_NS:-robot-shop}"

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

    if [ "$(k get pod mysql-0 -n "${_app_ns}" -o jsonpath='{.status.phase}' 2>/dev/null || true)" != "Running" ]; then
        refuse "The database pod mysql-0 is not running in '${_app_ns}'; run 'make setup-robot-shop' or wait for it to start."
    fi

    if ! k exec deploy/web -n "${_app_ns}" -c web -- sh -c 'command -v curl' >/dev/null 2>&1; then
        refuse "The web pod is missing or has no curl in '${_app_ns}'; the test requests are sent from it."
    fi
}

# Runs one SQL statement as root inside mysql-0. The password is read from the
# pod's own environment, so it never appears in the repo or on our command
# line (constitution principle IV). Prints rows without headers, tab-separated.
db() {
    # shellcheck disable=SC2016
    k exec mysql-0 -n "${_app_ns}" -c mysql -- \
        sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N -B -e "$1"' sh "$1"
}

# --- state reader (data-model, Fault state) ----------------------------------
# Sets _state to Not installed, On, Off or Partial, and _rules / _enabled /
# _loaded to the rule rows, the enabled rows and Rewriter_number_loaded_rules.
# Changes nothing.
_state=""
_rules=0
_enabled=0
_loaded=""

read_state() {
    local present
    present=$(db "select count(*) from information_schema.tables where table_schema='query_rewrite' and table_name='rewrite_rules'")
    if [ "${present}" != 1 ]; then
        _state="Not installed"
        _rules=0
        _enabled=0
        _loaded=""
        return 0
    fi
    _rules=$(db "select count(*) from query_rewrite.rewrite_rules")
    _enabled=$(db "select count(*) from query_rewrite.rewrite_rules where enabled='YES'")
    _loaded=$(db "show global status like 'Rewriter_number_loaded_rules'" | awk '{ print $2 }')
    if [ "${_rules}" = 3 ] && [ "${_enabled}" = 3 ] && [ "${_loaded}" = 3 ]; then
        _state="On"
    elif [ "${_loaded}" = 0 ]; then
        _state="Off"
    else
        _state="Partial"
    fi
}

# --- test requests (data-model, Test request) -------------------------------
# One exec in the web pod sends 3 ratings lookups in parallel and 2 shipping
# lookups one after another (parallel shipping scans queue on MySQL's CPU limit
# and read as slow even with the fault off).
# Sets _verdict to slow (every answer 200, shipping over 2 s, ratings over
# 0.5 s), normal (every answer 200, shipping 2 s or less, ratings 0.5 s or
# less), mixed or bad (a missing or non-200 answer), and _detail to the text
# the RESULT line quotes: the fastest times when slow, the slowest otherwise.
_verdict=""
_detail=""
_ship=""
_rate=""
_bad=""

probe() {
    local out
    # shellcheck disable=SC2016
    out=$(k exec deploy/web -n "${_app_ns}" -c web -- sh -c '
        for i in 1 2 3; do
            curl -s --max-time 20 -o /dev/null -w "rate %{http_code} %{time_total}\n" http://ratings/api/fetch/Watson &
        done
        for i in 1 2; do
            curl -s --max-time 20 -o /dev/null -w "ship %{http_code} %{time_total}\n" http://shipping:8080/match/de/ber
        done
        wait' 2>/dev/null || true)
    eval "$(awk '
        $1 == "ship" || $1 == "rate" {
            n++
            if ($2 != 200) bad = bad " " $1 "=" $2
            t = $3 + 0
            if (!(($1, "min") in v) || t < v[$1, "min"]) v[$1, "min"] = t
            if (t > v[$1, "max"]) v[$1, "max"] = t
        }
        END {
            if (n != 5) bad = bad " got_" n "_of_5_answers"
            slow = (v["ship", "min"] > 2 && v["rate", "min"] > 0.5)
            normal = (v["ship", "max"] <= 2 && v["rate", "max"] <= 0.5)
            verdict = bad != "" ? "bad" : slow ? "slow" : normal ? "normal" : "mixed"
            s = slow ? v["ship", "min"] : v["ship", "max"]
            r = slow ? v["rate", "min"] : v["rate", "max"]
            printf "_verdict=%s\n_ship=%.1f\n_rate=%.1f\n_bad=\"%s\"\n", verdict, s, r, bad
        }' <<<"${out}")"
    if [ "${_verdict}" = bad ]; then
        _detail="unexpected answers:${_bad}"
    else
        _detail="shipping ${_ship}s, ratings ${_rate}s"
    fi
}

# Repeats probe for up to 30 s until the verdict is $1 (contracts §5).
wait_probe() {
    local began=${SECONDS}
    while :; do
        probe
        [ "${_verdict}" = "$1" ] && return 0
        [ $((SECONDS - began)) -ge 30 ] && return 1
        sleep 2
    done
}

# --- the three rules (contracts §7) ------------------------------------------
_sel='select city0_.uuid as uuid1_0_, city0_.city as city2_0_, city0_.country_code as country_3_0_, city0_.latitude as latitude4_0_, city0_.longitude as longitud5_0_, city0_.name as name6_0_, city0_.region as region7_0_ from cities city0_ where city0_.country_code=?'
_rule1="${_sel} and (city0_.city like ?)"
_rule2="${_sel}"
_rule3='select avg_rating, rating_count from ratings where sku = ?'

# Writes one rule row; $1 pattern database, $2 pattern, $3 replacement. The
# statements contain no single quote, so plain quoting is safe.
rule_sql() {
    echo "insert into query_rewrite.rewrite_rules (pattern_database, pattern, replacement, enabled) values ('$1', '$2', '$3', 'YES');"
}

install_plugin() {
    # shellcheck disable=SC2016
    k exec mysql-0 -n "${_app_ns}" -c mysql -- \
        sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot < /usr/share/mysql/install_rewriter.sql'
}

# The RESULT line of "the fault is on", shared by start and status.
report_on() {
    if [ "${_verdict}" = slow ]; then
        echo "RESULT: fault active (shipping lookup ${_ship}s, ratings lookup ${_rate}s)"
    else
        echo "RESULT: the fault is set but the lookups were not slow: ${_detail}"
        return 1
    fi
}

cmd_start() {
    read_state
    if [ "${_state}" = "On" ]; then
        echo "RESULT: fault already active"
        return 0
    fi

    if [ "${_state}" = "Not installed" ]; then
        echo "Installing the Rewriter plugin in mysql-0..."
        install_plugin
    fi

    echo "Adding the three rules and loading them..."
    db "delete from query_rewrite.rewrite_rules;
$(rule_sql cities "${_rule1}" "${_rule1/from cities city0_/from (select sleep(2.5)) as db_delay, cities city0_}")
$(rule_sql cities "${_rule2}" "${_rule2/from cities city0_/from (select sleep(2.5)) as db_delay, cities city0_}")
$(rule_sql ratings "${_rule3}" "select avg_rating, rating_count from (select sleep(0.5)) as db_delay, ratings where sku = ?")
update query_rewrite.rewrite_rules set enabled='YES';
call query_rewrite.flush_rewrite_rules();"

    echo "Waiting up to 30s for the lookups to turn slow..."
    wait_probe slow || true
    report_on
}

cmd_status() {
    read_state
    case "${_state}" in
        On)
            probe
            report_on
            ;;
        Partial)
            echo "RESULT: the fault is partly set (${_enabled} of 3 rules enabled)"
            return 1
            ;;
        *)
            probe
            if [ "${_verdict}" = normal ]; then
                echo "RESULT: fault not active"
            else
                echo "RESULT: fault not active, but the lookups are slow for another reason: ${_detail}"
                return 1
            fi
            ;;
    esac
}

cmd_revert() {
    read_state
    local changed=no
    case "${_state}" in
        On | Partial)
            changed=yes
            echo "Disabling the rules..."
            # Disable and reload; never uninstall the plugin or delete rows
            # (research Findings 10 and 12).
            db "update query_rewrite.rewrite_rules set enabled='NO'; call query_rewrite.flush_rewrite_rules();"
            ;;
    esac

    echo "Waiting up to 30s for the lookups to turn normal..."
    if wait_probe normal; then
        if [ "${changed}" = yes ]; then
            echo "RESULT: fault removed (shipping lookup ${_ship}s, ratings lookup ${_rate}s)"
        else
            echo "RESULT: fault not active, nothing changed"
        fi
    else
        echo "RESULT: the fault is removed but the lookups are still slow: ${_detail}"
        return 1
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
