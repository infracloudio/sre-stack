#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2209,SC2329 # state variables are read by the sourced library; test functions are invoked indirectly
# finish-test.sh: offline tests of the required-check rule in finish() (lib-uninstall-test.sh). No cluster call.
#
# finish() may record PASS only when every registered check ran. A check that did not run is INCONCLUSIVE, and
# its name is written to verdict-reasons.txt as MISSING_CHECKS=. With nothing registered, no PASS is possible.
#
# Cases:
#   A. nohooks, stop before evaluation            -> INCONCLUSIVE, all nohooks checks missing
#   B. nohooks, one check skipped                 -> INCONCLUSIVE, that check is missing
#   C. nohooks, every check ran, nothing recorded -> PASS, no missing checks
#   D. control, stop before evaluation            -> INCONCLUSIVE, all control checks missing
#   E. nothing registered                         -> INCONCLUSIVE
#   F. every check ran, one FAIL recorded         -> FAIL
#
# Each case runs finish in its own subshell, because finish exits. The library runs under set -u and set -C.
# FINISH_TEST_LIB may name another copy of the library. It is used only for the regression check, which must fail
# on the old copy (no required-check rule) and pass on the current one.
# Exit 0 when every case behaves as expected, 1 otherwise.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
LIB="${FINISH_TEST_LIB:-$DIR/lib-uninstall-test.sh}"
# shellcheck disable=SC1090 # the path is FINISH_TEST_LIB (regression check) or the library beside this file
if ! . "$LIB"; then
  echo "cannot load the library from $LIB" >&2
  exit 2
fi
W="$(mktemp -d "${TMPDIR:-/tmp}/finish-test.XXXXXX")" || exit 2
CASES_PASSED=0
CASES_FAILED=0
ALL_NOHOOKS="nohooks_job_absent nohooks_pod_absent nohooks_events_absent nohooks_decoy_keep_present nohooks_decoy_sre_present nohooks_keep_names_present nohooks_helm_released nohooks_health"
ALL_CONTROL="control_job_watch control_pod_watch control_decoy_keep_absent control_decoy_sre_present control_keep_names_absent control_hook_log control_health"

# mark_except NAME: marks every nohooks check as run, except NAME ("none" marks all).
mark_except() {
  local skip="$1" c
  for c in $ALL_NOHOOKS; do
    if [ "$c" != "$skip" ]; then check_done "$c"; fi
  done
}

# run_case NAME WANT_VERDICT WANT_MISSING STEPS
# STEPS is shell code run in the subshell before finish. On the old library the calls it names do not exist, so
# the errors are suppressed and the old finish runs with nothing registered.
run_case() {
  local name="$1" want_verdict="$2" want_missing="$3" steps="$4" d verdict missing reasons ok=yes
  d="$W/case-$(echo "$name" | tr -c 'a-z0-9' '_')"
  rm -rf "$d"
  mkdir -p "$d"
  (
    # shellcheck disable=SC2034 # EV, NS, MODE, CHANGED and SUFFIX are read by the sourced library functions
    EV="$d"
    NS=keep-uninstall-test
    MODE=nohooks
    CHANGED=0
    SUFFIX="test"
    FAILS=""
    INCS=""
    FINISHING=0
    PIDS=""
    REQUIRED_CHECKS=""
    DONE_CHECKS=""
    eval "$steps" 2>/dev/null || true
    finish
  ) > "$d/stdout.txt" 2>&1
  verdict="$(sed -n 's/^VERDICT=//p' "$d/verdict.txt" 2>/dev/null)"
  reasons="$(cat "$d/verdict-reasons.txt" 2>/dev/null)"
  missing="$(sed -n 's/^MISSING_CHECKS=//p' "$d/verdict-reasons.txt" 2>/dev/null)"
  if [ "$verdict" != "$want_verdict" ]; then ok=no; fi
  if [ "$missing" != "$want_missing" ]; then ok=no; fi
  if [ "$ok" = yes ]; then
    CASES_PASSED=$((CASES_PASSED + 1))
    echo "pass   $name (verdict=$verdict, missing=[$missing])"
  else
    CASES_FAILED=$((CASES_FAILED + 1))
    echo "FAIL   $name (want verdict=$want_verdict missing=[$want_missing]; got verdict=$verdict missing=[$missing])"
  fi
  echo "       reasons: $(echo "$reasons" | tr '\n' ' ')"
  return 0
}

echo "library under test: $LIB"
run_case "A nohooks stop before evaluation" INCONCLUSIVE "$ALL_NOHOOKS" "register_required_checks nohooks"
run_case "B nohooks one check skipped" INCONCLUSIVE "nohooks_health" "register_required_checks nohooks; mark_except nohooks_health"
run_case "C nohooks every check ran" PASS "" "register_required_checks nohooks; mark_except none"
run_case "D control stop before evaluation" INCONCLUSIVE "$ALL_CONTROL" "register_required_checks control"
run_case "E nothing registered" INCONCLUSIVE "" ""
run_case "F every check ran, one FAIL recorded" FAIL "" "register_required_checks nohooks; mark_except none; note_fail 'a required check failed'"

rm -rf "$W"
echo
echo "cases passed: $CASES_PASSED, cases failed: $CASES_FAILED"
if [ "$CASES_FAILED" -eq 0 ]; then exit 0; fi
exit 1
