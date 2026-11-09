#!/usr/bin/env bash
# watch-rules-test.sh: offline checks of the watch rules in lib-uninstall-test.sh. The positive cases are the
# raw probe output saved in fixtures/ (k3s v1.36.4, 2026-11-09). The negative cases are made from those same
# files and must be rejected. This script makes no cluster call and needs no credentials.
#
# Exit 0 when every case behaves as expected, 1 otherwise.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
if ! . "$DIR/lib-uninstall-test.sh"; then
  echo "cannot load lib-uninstall-test.sh from $DIR" >&2
  exit 2
fi
FIX="$DIR/fixtures"
W="$(mktemp -d "${TMPDIR:-/tmp}/watch-rules.XXXXXX")" || exit 2
JOB=probe-job
POD=probe-pod
PASS=0
FAILS=0

# result NAME WANT CMD...: runs CMD. "ok" means it returned 0, "bad" means it returned non-zero. Prints whether
# the outcome matches WANT, and the rule's reason when it has one.
result() {
  local name="$1" want="$2" out rc got
  shift 2
  out="$("$@" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then got=ok; else got=bad; fi
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    echo "pass   $name (want $want, got $got)"
  else
    FAILS=$((FAILS + 1))
    echo "FAIL   $name (want $want, got $got)"
  fi
  if [ -n "$out" ]; then echo "       reason: $(printf '%s' "$out" | tr '\n' ' ')"; fi
  return 0
}

# job_is FILE JOB WANT: passes when job_control_state reports WANT.
# shellcheck disable=SC2329 # invoked indirectly, through result "$@"
job_is() {
  local got
  got="$(job_control_state "$1" "$2")"
  if [ "$got" = "$3" ]; then return 0; fi
  echo "job_control_state reports $got, expected $3"
  return 1
}

# ---- positive cases: real probe output must pass ----
result "P1 configmap default table, real output" ok check_watch "$FIX/cm-default.txt" "$CM_HEADER" other
result "P2 job default table, real output, layout" ok check_watch "$FIX/job-default.txt" "$JOB_HEADER" job
result "P3 job default table, control state is OK" ok job_is "$FIX/job-default.txt" "$JOB" OK
result "P4 pod -o wide, real output, layout" ok check_watch "$FIX/pod-wide.txt" "$POD_HEADER" pod
result "P5 pod -o wide, sentinel rows" ok validate_sentinel_rows "$FIX/pod-wide.txt" "$POD"

# ---- negative cases: mutated or wrong-layout output must be rejected ----
# N0: the default-table Pod output is a different layout, and Option B does not accept it.
result "N0 pod default table (not -o wide) rejected" bad check_watch "$FIX/pod-default.txt" "$POD_HEADER" pod

# N1: a mutated header.
sed '1s/READINESS GATES/READINESS GATEZ/' "$FIX/pod-wide.txt" > "$W/n1-header.txt"
result "N1 mutated header rejected" bad check_watch "$W/n1-header.txt" "$POD_HEADER" pod

# N2: the sentinel's final DELETED row is missing.
awk -v p="$POD" '!($1 == "DELETED" && $2 == p)' "$FIX/pod-wide.txt" > "$W/n2-no-deleted.txt"
result "N2 sentinel missing DELETED row rejected" bad validate_sentinel_rows "$W/n2-no-deleted.txt" "$POD"

# N3: a sentinel row shows STATUS Running.
awk -v p="$POD" 'BEGIN { OFS = " " } $2 == p && $1 == "ADDED" { $4 = "Running" } { print }' "$FIX/pod-wide.txt" > "$W/n3-running.txt"
result "N3 sentinel row with STATUS Running rejected" bad validate_sentinel_rows "$W/n3-running.txt" "$POD"

# N4: a sentinel row shows a node name.
awk -v p="$POD" 'BEGIN { OFS = " " } $2 == p && $1 == "MODIFIED" { $8 = "k3d-keep-uninstall-test-server-0" } { print }' "$FIX/pod-wide.txt" > "$W/n4-node.txt"
result "N4 sentinel row with a node name rejected" bad validate_sentinel_rows "$W/n4-node.txt" "$POD"

# N5: a Job row shows STATUS Failed.
awk -v j="$JOB" 'BEGIN { OFS = " " } $2 == j && $1 == "MODIFIED" && $3 == "Complete" { $3 = "Failed" } { print }' "$FIX/job-default.txt" > "$W/n5-failed.txt"
result "N5 Job row with STATUS Failed fails the control" bad job_is "$W/n5-failed.txt" "$JOB" OK

# N6: a Pod row has nine fields instead of ten.
awk -v p="$POD" 'BEGIN { OFS = " " } $2 == p && $1 == "ADDED" { $9 = "" } { print }' "$FIX/pod-wide.txt" > "$W/n6-nine-fields.txt"
result "N6 Pod row with nine fields rejected" bad check_watch "$W/n6-nine-fields.txt" "$POD_HEADER" pod

# N7: the Job's completion row is removed, so the control cannot count a success.
awk -v j="$JOB" '!($1 == "MODIFIED" && $2 == j && $3 == "Complete")' "$FIX/job-default.txt" > "$W/n7-no-complete.txt"
result "N7 Job without a Complete 1/1 row is not OK" bad job_is "$W/n7-no-complete.txt" "$JOB" OK

# N8: an event type is misspelled.
sed 's/^ADDED /ADDEED /' "$FIX/pod-wide.txt" > "$W/n8-event.txt"
result "N8 misspelled event type rejected" bad check_watch "$W/n8-event.txt" "$POD_HEADER" pod

rm -rf "$W"
echo
echo "cases passed: $PASS, cases failed: $FAILS"
if [ "$FAILS" -eq 0 ]; then exit 0; fi
exit 1
