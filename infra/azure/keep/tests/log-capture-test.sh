#!/usr/bin/env bash
# log-capture-test.sh: offline tests of start_hook_log_capture and finish_hook_log_capture in
# lib-uninstall-test.sh, with a stub kubectl first on PATH. No cluster call and no credentials.
#
# The library is sourced with set -u and set -C, like the real test scripts. Noclobber matters: the
# first version of the capture loop reused one file name on every retry and failed after the first attempt.
#
# Cases:
#   1. two BadRequests, then success with output     -> not INCONCLUSIVE, hook-logs.txt written, 3 attempts
#   2. never succeeds (BadRequest every time)        -> INCONCLUSIVE, bound reached
#   3. Pod disappears (NotFound) after the first try -> INCONCLUSIVE, pod_gone after 1 attempt
#   4. success with empty output every time          -> INCONCLUSIVE, bound reached
#
# Each case checks the verdict-level outcome, the result line, the attempt count, and that the attempts file
# has one line per attempt file. The bound is shortened to 3 seconds after the library is sourced.
#
# LOG_CAPTURE_LIB may name another copy of the library. It is used only for the regression check, which must
# fail on the old copy and pass on the current one.
# Exit 0 when every case behaves as expected, 1 otherwise.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
LIB="${LOG_CAPTURE_LIB:-$DIR/lib-uninstall-test.sh}"
# shellcheck disable=SC1090 # the path is LOG_CAPTURE_LIB (regression check) or the library beside this file
if ! . "$LIB"; then
  echo "cannot load the library from $LIB" >&2
  exit 2
fi
W="$(mktemp -d "${TMPDIR:-/tmp}/log-capture.XXXXXX")" || exit 2
STUB="$W/bin"
mkdir -p "$STUB"
CASES_PASSED=0
CASES_FAILED=0

cat > "$STUB/kubectl" <<'SH'
#!/usr/bin/env bash
# Stub kubectl. STUB_MODE selects the behaviour of "kubectl logs". Every call is recorded in STUB_DIR.
echo "$*" >> "$STUB_DIR/calls.log"
case "$1" in
  get)
    if [ "$2" = pods ]; then
      echo "pod/keep-stub-hook"
      exit 0
    fi
    # "get pod/NAME": NotFound once the stub has logged, in the pod_gone mode.
    if [ "$STUB_MODE" = pod_gone ] && [ -e "$STUB_DIR/logs-called" ]; then
      echo 'Error from server (NotFound): pods "keep-stub-hook" not found' >&2
      exit 1
    fi
    echo "pod/keep-stub-hook"
    exit 0
    ;;
  logs)
    touch "$STUB_DIR/logs-called"
    n="$(cat "$STUB_DIR/logs-count" 2>/dev/null || echo 0)"
    n=$((n + 1))
    echo "$n" > "$STUB_DIR/logs-count"
    bad='Error from server (BadRequest): container "delete-secrets-container" in pod "keep-stub-hook" is waiting to start: ContainerCreating'
    case "$STUB_MODE" in
      bad_then_ok)
        if [ "$n" -le 2 ]; then
          echo "$bad" >&2
          exit 1
        fi
        echo 'secret "keep-decoy-control" deleted'
        exit 0
        ;;
      never)
        echo "$bad" >&2
        exit 1
        ;;
      pod_gone)
        echo "$bad" >&2
        exit 1
        ;;
      empty)
        exit 0
        ;;
    esac
    ;;
esac
echo "stub: unexpected call: $*" >&2
exit 9
SH
chmod +x "$STUB/kubectl"

# run_case NAME MODE WANT_INCONCLUSIVE(yes|no) WANT_RESULT(ok|pod_gone|bound) WANT_ATTEMPTS(N or >=2)
# shellcheck disable=SC2034 # EV, NS and LOG_RETRY_SECONDS are read by the sourced library functions
run_case() {
  local name="$1" mode="$2" want_inc="$3" want_result="$4" want_att="$5" d got_inc result attempts files lines
  local ok=yes
  d="$W/case-$mode"
  rm -rf "$d" "$W/calls-$mode"
  mkdir -p "$d" "$W/calls-$mode"
  export STUB_MODE="$mode" STUB_DIR="$W/calls-$mode"
  EV="$d"
  NS=keep-uninstall-control
  INCS=""
  FAILS=""
  LOGC=""
  LOG_RETRY_SECONDS=3
  PATH="$STUB:$PATH" start_hook_log_capture
  wait "$LOGC" 2>/dev/null
  PATH="$STUB:$PATH" finish_hook_log_capture > "$d/finish.out" 2>&1
  if [ -n "$INCS" ]; then got_inc=yes; else got_inc=no; fi
  result="$(sed -n 's/^result=//p' "$d/hook-logs.attempts" 2>/dev/null)"
  attempts="$(grep -c '^attempt=' "$d/hook-logs.attempts" 2>/dev/null || echo 0)"
  files="$(find "$d" -maxdepth 1 -name 'hook-logs-attempt-*.txt' | wc -l | tr -d ' ')"
  lines="$attempts"
  if [ "$want_att" = ">=2" ]; then
    if [ "$attempts" -lt 2 ]; then ok=no; fi
  elif [ "$attempts" != "$want_att" ]; then
    ok=no
  fi
  if [ "$files" != "$attempts" ] || [ "$lines" != "$attempts" ]; then ok=no; fi
  if [ "$got_inc" != "$want_inc" ] || [ "$result" != "$want_result" ]; then ok=no; fi
  if [ "$want_result" = ok ]; then
    if ! grep -Fxq 'secret "keep-decoy-control" deleted' "$d/hook-logs.txt" 2>/dev/null; then ok=no; fi
  fi
  if [ "$ok" = yes ]; then
    CASES_PASSED=$((CASES_PASSED + 1))
    echo "pass   $name (inconclusive=$got_inc, result=$result, attempts=$attempts, attempt files=$files)"
  else
    CASES_FAILED=$((CASES_FAILED + 1))
    echo "FAIL   $name (want inconclusive=$want_inc result=$want_result attempts=$want_att; got inconclusive=$got_inc result=$result attempts=$attempts attempt files=$files)"
  fi
  echo "       attempts file:"
  sed 's/^/         /' "$d/hook-logs.attempts" 2>/dev/null
  echo "       status: $(cat "$d/hook-logs.status" 2>/dev/null)  kubectl logs calls: $(cat "$W/calls-$mode/logs-count" 2>/dev/null || echo 0)"
  return 0
}

echo "library under test: $LIB"
run_case "1 bad_then_ok (regression: retries under set -C)" bad_then_ok no ok 3
run_case "2 never" never yes bound ">=2"
run_case "3 pod_gone" pod_gone yes pod_gone 1
run_case "4 empty" empty yes bound ">=2"

rm -rf "$W"
echo
echo "cases passed: $CASES_PASSED, cases failed: $CASES_FAILED"
if [ "$CASES_FAILED" -eq 0 ]; then exit 0; fi
exit 1
