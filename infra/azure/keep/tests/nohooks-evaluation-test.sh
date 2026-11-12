#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2209,SC2329 # state variables are read by the sourced library; test functions are invoked indirectly
# nohooks-evaluation-test.sh: offline tests of evaluate_nohooks (lib-uninstall-test.sh) on fixture folders. No cluster
# call and no credentials. Each case starts from a clean folder that matches a successful no-hooks run, applies one
# change, and checks the outcome and that every nohooks check ran.
#
# Cases:
#   1. clean pass                          -> pass
#   2. hook Job ADDED row                  -> fail
#   3. hook Pod row                        -> fail
#   4. missing decoy                       -> fail
#   5. helm status still deployed          -> fail
#   6. missing evidence file (jobwatch)    -> inconclusive
#
# The library runs under set -u and set -C. NOHOOKS_EVAL_LIB may name another copy of the library. The old copy has
# no evaluate_nohooks function, so every case fails there, which is the regression signal.
# Exit 0 when every case behaves as expected, 1 otherwise.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
LIB="${NOHOOKS_EVAL_LIB:-$DIR/lib-uninstall-test.sh}"
# shellcheck disable=SC1090 # the path is NOHOOKS_EVAL_LIB (regression check) or the library beside this file
if ! . "$LIB"; then
  echo "cannot load the library from $LIB" >&2
  exit 2
fi
W="$(mktemp -d "${TMPDIR:-/tmp}/nohooks-eval.XXXXXX")" || exit 2
CASES_PASSED=0
CASES_FAILED=0
ALL_NOHOOKS="nohooks_job_absent nohooks_pod_absent nohooks_events_absent nohooks_decoy_keep_present nohooks_decoy_sre_present nohooks_keep_names_present nohooks_helm_released nohooks_health"

# make_clean DIR: a folder that matches a successful no-hooks run. Helm status is "not found" (stderr), and no
# helm-status-post.txt is created, so a mutation can create it with plain redirection under noclobber.
make_clean() {
  local d="$1"
  mkdir -p "$d"
  {
    echo "$JOB_HEADER"
    echo "ADDED      keep-uninstall-readiness-test   Suspended   0/1                      0s"
    echo "MODIFIED   keep-uninstall-readiness-test   Suspended   0/1                      0s"
    echo "DELETED    keep-uninstall-readiness-test   Suspended   0/1                      1s"
  } > "$d/jobwatch.txt"
  {
    echo "$POD_HEADER"
    echo "ADDED      keep-uninstall-readiness-pod-test   0/1     SchedulingGated   0          0s    <none>   <none>   <none>           <none>"
    echo "MODIFIED   keep-uninstall-readiness-pod-test   0/1     Terminating       0          0s    <none>   <none>   <none>           <none>"
    echo "DELETED    keep-uninstall-readiness-pod-test   0/1     Terminating       0          0s    <none>   <none>   <none>           <none>"
  } > "$d/podwatch.txt"
  : > "$d/events.txt"
  {
    echo "secret/keep-decoy-test"
    echo "secret/sh.helm.release.v1.keep.v1"
    echo "secret/sre-keep-ai-env"
    echo "secret/sre-keep-ai-frontend"
    echo "secret/sre-keep-db"
    echo "secret/sre-keep-decoy-test"
  } > "$d/after-secrets.txt"
  echo "secret/keep-decoy-test" > "$d/before-keep-names.txt"
  echo "Error: release: not found" > "$d/helm-status-post.err"
  local i
  : > "$d/watchers-health.txt"
  for i in $(seq 1 12); do
    echo "OK 11:00:00 $i" >> "$d/watchers-health.txt"
  done
}

mut_none() { :; }
mut_hook_job_added() {
  echo "ADDED      delete-keep-secrets   Running   0/1                      0s" >> "$1/jobwatch.txt"
}
mut_hook_pod_added() {
  echo "ADDED      delete-keep-secrets-x7k2p   0/1     Pending   0   0s   <none>   <none>   <none>   <none>" >> "$1/podwatch.txt"
}
mut_missing_decoy() {
  grep -v -x 'secret/keep-decoy-test' "$1/after-secrets.txt" > "$1/after-secrets.tmp"
  mv "$1/after-secrets.tmp" "$1/after-secrets.txt"
}
mut_helm_still_deployed() {
  printf 'NAME: keep\nLAST DEPLOYED: Mon Nov  9 16:51:33 2026\nNAMESPACE: keep-uninstall-test\nSTATUS: deployed\nREVISION: 1\n' > "$1/helm-status-post.txt"
}
mut_missing_jobwatch() {
  rm -f "$1/jobwatch.txt"
}

# run_eval NAME WANT(pass|fail|inconclusive) MUTATION
run_eval() {
  local name="$1" want="$2" mutation="$3" d result all_done=yes c got
  d="$W/case-$(echo "$name" | tr -c 'a-z0-9' '_')"
  rm -rf "$d"
  make_clean "$d"
  "$mutation" "$d"
  # shellcheck disable=SC2034 # EV, NS and SUFFIX are read by the sourced library functions
  EV="$d"
  NS=keep-uninstall-test
  SUFFIX="test"
  FAILS=""
  INCS=""
  DONE_CHECKS=""
  evaluate_nohooks "$d" 2>/dev/null || true
  for c in $ALL_NOHOOKS; do
    case " $DONE_CHECKS " in
      *" $c "*) ;;
      *) all_done=no ;;
    esac
  done
  if [ -n "$FAILS" ]; then
    result=fail
  elif [ -n "$INCS" ]; then
    result=inconclusive
  else
    result=pass
  fi
  got="$result"
  if [ "$got" = "$want" ] && [ "$all_done" = yes ]; then
    CASES_PASSED=$((CASES_PASSED + 1))
    echo "pass   $name (want $want, got $got, every check ran)"
  else
    CASES_FAILED=$((CASES_FAILED + 1))
    echo "FAIL   $name (want $want, got $got, every check ran: $all_done)"
  fi
  if [ -n "$FAILS" ]; then echo "       fails: $FAILS"; fi
  if [ -n "$INCS" ]; then echo "       inconclusive: $INCS"; fi
  return 0
}

echo "library under test: $LIB"
run_eval "1 clean pass" pass mut_none
run_eval "2 hook Job ADDED row" fail mut_hook_job_added
run_eval "3 hook Pod row" fail mut_hook_pod_added
run_eval "4 missing decoy" fail mut_missing_decoy
run_eval "5 helm status still deployed" fail mut_helm_still_deployed
run_eval "6 missing evidence file (jobwatch)" inconclusive mut_missing_jobwatch

rm -rf "$W"
echo
echo "cases passed: $CASES_PASSED, cases failed: $CASES_FAILED"
if [ "$CASES_FAILED" -eq 0 ]; then exit 0; fi
exit 1
