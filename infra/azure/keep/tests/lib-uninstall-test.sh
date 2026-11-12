#!/usr/bin/env bash
# lib-uninstall-test.sh: shared functions for keep-uninstall-control.sh and keep-uninstall-nohooks.sh.
# Story #123, specs/010-keep-install-aks/plan.md section 7. Draft for review. Not run against any cluster.
#
# This file is sourced by the test scripts. Do not run it directly.
#
# External commands used (all checked in preflight): bash, kubectl, helm, awk, grep, sleep, mktemp, date,
# head, cat, dirname, ps, shasum, tr. Not used: GNU timeout, xargs -r, seq, jq, sed -i, pkill, killall,
# process-name matching, and any unbounded wait.
#
# Safety:
#   - Refuses unless EXPECTED_CONTEXT is exactly k3d-keep-uninstall-test and the kubectl server for that
#     context is https://127.0.0.1:<port> or https://localhost:<port>. No environment bypass exists.
#   - Creates and deletes only the namespace named by the calling script, and resources inside it.
#   - Dummy values only. Never reads KEEP_SECRETS_DIR or any credential file.
#   - Signals only PIDs this shell started, that are still registered, and whose parent is this shell.
#     Every stop is bounded: TERM, a grace period, KILL, a bounded confirmation, then INCONCLUSIVE.
#
# Exit codes, set by the calling script: 0 PASS, 1 FAIL, 2 REFUSED before any change, 3 INCONCLUSIVE.

REQUIRED_CONTEXT="k3d-keep-uninstall-test"
REQUIRED_HELM="v3.14.4"
HOOK_JOB="delete-keep-secrets"
HOOK_POD_SELECTOR="batch.kubernetes.io/job-name=delete-keep-secrets"
PROBE_CM="keep-uninstall-watch-probe"
READINESS_IMAGE="busybox:1.38.0@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4"
SENTINEL_GATE="keep.uninstall.test/readiness"
MIN_K8S_MINOR=30
POD_FIELDS=10
CM_HEADER="EVENT NAME DATA AGE"
JOB_HEADER="EVENT NAME STATUS COMPLETIONS DURATION AGE"
POD_HEADER="EVENT NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES"
DECOY_VALUE="dummy-value-not-a-credential"
SCRIPT_FILES="lib-uninstall-test.sh keep-uninstall-control.sh keep-uninstall-nohooks.sh"
MIN_HEALTH_SAMPLES=10
HOLD_SECONDS=30
KILL_GRACE_SECONDS=10
KILL_WAIT_SECONDS=5
LOG_WAIT_SECONDS=60
LOG_RETRY_SECONDS=120
LOG_RETRY_INTERVAL=0.2

FAILS=""
INCS=""
REQUIRED_CHECKS=""
DONE_CHECKS=""
PIDS=""
HEALTH_PID=""
LOGC=""
WPID=""
CHANGED=0
FINISHING=0
RL_SEQ=0
EVIDENCE_WRITE_FAILED=0
EV=""
NS=""
SUFFIX=""
HELM_VER=""
MODE=""

log() {
  if [ -n "$EV" ]; then
    if ! printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$EV/run.log" 2>/dev/null; then
      EVIDENCE_WRITE_FAILED=1
    fi
  fi
}

note_fail() { FAILS="${FAILS}; $*"; log "FAIL: $*"; echo "FAIL: $*" >&2; }
note_inc()  { INCS="${INCS}; $*"; log "INCONCLUSIVE: $*"; echo "INCONCLUSIVE: $*" >&2; }

# evwrite FILE TEXT: writes one line to a new evidence file. A failed write is recorded and reported.
evwrite() {
  if ! printf '%s\n' "$2" > "$1" 2>/dev/null; then
    EVIDENCE_WRITE_FAILED=1
    echo "EVIDENCE WRITE FAILED: $1" >&2
    return 1
  fi
  return 0
}

# refuse MESSAGE: exits 2 before any change. When an evidence folder exists, it records VERDICT=REFUSED there.
refuse() {
  echo "REFUSED: $*" >&2
  if [ -n "$EV" ] && [ -d "$EV" ]; then
    log "REFUSED: $*"
    if ! printf 'VERDICT=REFUSED\nMODE=%s\nNAMESPACE=%s\nREASON=%s\n' "$MODE" "$NS" "$*" > "$EV/verdict.txt" 2>/dev/null; then
      echo "EVIDENCE WRITE FAILED: $EV/verdict.txt" >&2
    fi
  fi
  exit 2
}

# ---- PID registry ----

# track PID NAME: registers a child process this shell started, and records it in pids.txt.
track() {
  PIDS="$PIDS $1"
  if [ -n "$EV" ]; then
    if ! printf '%s %s\n' "$2" "$1" >> "$EV/pids.txt" 2>/dev/null; then
      EVIDENCE_WRITE_FAILED=1
    fi
  fi
}

# is_registered PID: true only while the PID is in the registry.
is_registered() {
  case " $PIDS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# unregister_pid PID: removes the PID as soon as it has been stopped and reaped.
unregister_pid() {
  local p new=""
  for p in $PIDS; do
    if [ "$p" != "$1" ]; then
      new="$new $p"
    fi
  done
  PIDS="$new"
}

# pid_alive PID: true when the process exists and is not a zombie. A zombie has exited.
pid_alive() {
  local st
  st="$(ps -o stat= -p "$1" 2>/dev/null | awk 'NR==1 {print substr($1,1,1)}')"
  [ -n "$st" ] && [ "$st" != "Z" ]
}

# pid_is_ours PID: true only when the parent of PID is this shell. Guards against PID reuse.
pid_is_ours() {
  local parent
  parent="$(ps -o ppid= -p "$1" 2>/dev/null | awk 'NR==1 {print $1}')"
  [ -n "$parent" ] && [ "$parent" = "$$" ]
}

# stop_pid PID: bounded termination of one registered child of this shell.
# Acts only if the PID is registered and is still our child. TERM, then a grace period, then KILL to the
# same PID, then a bounded confirmation. On success the PID is reaped and unregistered. If termination
# cannot be confirmed, the PID stays registered, INCONCLUSIVE is recorded, and the function returns 1.
stop_pid() {
  local p="$1" n=0
  if [ -z "$p" ]; then return 0; fi
  if ! is_registered "$p"; then return 0; fi
  if ! pid_alive "$p"; then
    wait "$p" 2>/dev/null
    unregister_pid "$p"
    return 0
  fi
  if ! pid_is_ours "$p"; then
    unregister_pid "$p"
    note_inc "refused to signal PID $p: it is not a child of this shell (PID reuse suspected)"
    return 1
  fi
  kill -TERM "$p" 2>/dev/null
  while pid_alive "$p" && [ "$n" -lt "$KILL_GRACE_SECONDS" ]; do
    sleep 1
    n=$((n + 1))
  done
  if pid_alive "$p"; then
    kill -KILL "$p" 2>/dev/null
    n=0
    while pid_alive "$p" && [ "$n" -lt "$KILL_WAIT_SECONDS" ]; do
      sleep 1
      n=$((n + 1))
    done
    if pid_alive "$p"; then
      note_inc "process $p did not terminate after KILL; termination is not confirmed"
      return 1
    fi
  fi
  wait "$p" 2>/dev/null
  unregister_pid "$p"
  return 0
}

# stop_background: stops every registered process, one PID at a time. Returns 1 if any could not be confirmed.
stop_background() {
  local p failed=0
  for p in $PIDS; do
    if ! stop_pid "$p"; then
      failed=1
    fi
  done
  if [ "$failed" -eq 1 ]; then return 1; fi
  return 0
}

# ---- Preflight and evidence ----

# preflight TARGET_NS MODE: every check runs before anything in the cluster changes.
preflight() {
  local want_ns="$1"
  MODE="$2"
  if [ -z "${BASH_VERSION:-}" ]; then refuse "run this script with bash"; fi
  local tool
  for tool in kubectl helm awk grep sleep mktemp date head cat dirname ps shasum tr; do
    if ! command -v "$tool" >/dev/null 2>&1; then refuse "missing required tool: $tool"; fi
  done
  HELM_VER="$(helm version --short 2>/dev/null)" || refuse "helm version failed"
  case "$HELM_VER" in
    "$REQUIRED_HELM"|"$REQUIRED_HELM"+*) ;;
    *) refuse "helm reports '$HELM_VER'; $REQUIRED_HELM is required on PATH" ;;
  esac
  if [ "${EXPECTED_CONTEXT:-}" != "$REQUIRED_CONTEXT" ]; then
    refuse "EXPECTED_CONTEXT must be exactly $REQUIRED_CONTEXT"
  fi
  local current
  current="$(kubectl config current-context 2>/dev/null)" || refuse "cannot read the kubectl context"
  if [ "$current" != "$REQUIRED_CONTEXT" ]; then
    refuse "current context is '$current', expected '$REQUIRED_CONTEXT'"
  fi
  local server
  server="$(kubectl config view --minify -o 'jsonpath={.clusters[0].cluster.server}' 2>/dev/null)" \
    || refuse "cannot read the cluster server address for the context"
  if ! printf '%s\n' "$server" | grep -Eq '^https://(127\.0\.0\.1|localhost):[0-9]+/?$'; then
    refuse "the cluster server for $REQUIRED_CONTEXT is not 127.0.0.1 or localhost; these tests run only on the local k3d cluster"
  fi
  NS="$want_ns"
  SUFFIX="${NS#keep-uninstall-}"
}

# init_evidence: a new folder every run. mktemp never reuses an existing folder.
init_evidence() {
  local root="${EVIDENCE_ROOT:-${TMPDIR:-/tmp}}"
  root="${root%/}"
  EV="$(mktemp -d "$root/keep-uninstall-$MODE.XXXXXX")" || refuse "cannot create an evidence folder under $root"
  evwrite "$EV/helm-version.txt" "$HELM_VER" || refuse "cannot write evidence"
  evwrite "$EV/kubectl-context.txt" "$EXPECTED_CONTEXT" || refuse "cannot write evidence"
  evwrite "$EV/namespace.txt" "$NS" || refuse "cannot write evidence"
  log "start mode=$MODE namespace=$NS context=$EXPECTED_CONTEXT helm=$HELM_VER"
}

# verify_script_hashes DIR: compares the three scripts in DIR with DIR/SHA256SUMS, and records the current
# hashes in script-hashes.txt. A missing manifest, missing entry or mismatch is INCONCLUSIVE.
verify_script_hashes() {
  local dir="$1" f actual expected bad=0
  if [ -z "$dir" ] || [ ! -r "$dir/SHA256SUMS" ]; then
    note_inc "SHA256SUMS manifest is missing or unreadable in $dir"
    return 1
  fi
  if ! : > "$EV/script-hashes.txt" 2>/dev/null; then
    note_inc "cannot write script-hashes.txt"
    return 1
  fi
  for f in $SCRIPT_FILES; do
    actual="$(shasum -a 256 "$dir/$f" 2>/dev/null | awk 'NR==1 {print $1}')"
    expected="$(awk -v f="$f" '$2==f {print $1}' "$dir/SHA256SUMS" 2>/dev/null)"
    if [ -z "$actual" ] || [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
      note_inc "script hash mismatch or missing manifest entry for $f"
      bad=1
    fi
    if [ -n "$actual" ]; then
      if ! printf '%s  %s\n' "$actual" "$f" >> "$EV/script-hashes.txt" 2>/dev/null; then
        EVIDENCE_WRITE_FAILED=1
      fi
    fi
  done
  if [ "$bad" -eq 1 ]; then return 1; fi
  return 0
}

# query NAME CMD...: stdout to $EV/NAME.txt, stderr to $EV/NAME.err. Returns the command's status.
# Foreground queries only. noclobber makes a reused NAME fail, and the caller treats that as a failure.
query() {
  local name="$1"; shift
  "$@" > "$EV/$name.txt" 2> "$EV/$name.err"
  local rc=$?
  log "query $name rc=$rc"
  return "$rc"
}

# ---- Watch output ----
# With --output-watch-events, kubectl puts the event type (ADDED, MODIFIED or DELETED) in the first column,
# and the header row starts with EVENT. The probe confirms this layout before any real watch is trusted.

# Watch rules, Option B: the default table for ConfigMaps and Jobs, and -o wide for Pods. Observed on
# k3s v1.36.4 with kubectl 1.34 on 2026-11-09. The raw probe output these rules were written against is in
# fixtures/. The header is split on whitespace. Column 1 is the event type. A Job's COMPLETIONS value is found
# by pattern, because DURATION can be blank. Pod rows must have POD_FIELDS fields, and kubectl prints <none>
# for empty cells. Repeated MODIFIED rows are normal and are never counted. AGE is never read.

# check_watch FILE HEADER KIND: 0 when the first line equals HEADER after whitespace splitting, every later
# non-blank row starts with ADDED, MODIFIED or DELETED, and the KIND check passes (job: a COMPLETIONS value on
# every row; pod: POD_FIELDS fields on every row; other: no extra check). Otherwise prints the reason, returns 1.
check_watch() {
  local file="$1" header="$2" kind="$3" got reason
  if [ ! -r "$file" ]; then echo "watch file is unreadable"; return 1; fi
  got="$(head -n 1 "$file" | awk '{ s = ""; for (i = 1; i <= NF; i++) s = s (i > 1 ? " " : "") $i; print s }')"
  if [ "$got" != "$header" ]; then echo "header is '$got', expected '$header'"; return 1; fi
  reason="$(awk 'NR > 1 && NF > 0 && $1 != "ADDED" && $1 != "MODIFIED" && $1 != "DELETED" { print "line " NR " starts with \"" $1 "\", not an event type"; exit 1 }' "$file")" || { echo "$reason"; return 1; }
  case "$kind" in
    job)
      reason="$(awk 'NR > 1 && NF > 0 { ok = 0; for (i = 4; i <= NF; i++) if ($i ~ /^[0-9]+\/[0-9]+$/) ok = 1; if (!ok) { print "line " NR " has no COMPLETIONS value"; exit 1 } }' "$file")" || { echo "$reason"; return 1; }
      ;;
    pod)
      reason="$(awk -v want="$POD_FIELDS" 'NR > 1 && NF > 0 && NF != want { print "line " NR " has " NF " fields, expected " want; exit 1 }' "$file")" || { echo "$reason"; return 1; }
      ;;
  esac
  return 0
}

# job_control_state FILE JOB: prints OK, MISSING or FAILED for the named Job. OK needs an ADDED row, then a
# non-DELETED row with STATUS Complete and COMPLETIONS 1/1, then a DELETED row. Any row with STATUS Failed or
# FailureTarget prints FAILED. A missing step prints MISSING. The count uses transitions, not MODIFIED rows.
job_control_state() {
  awk -v j="$2" '
    NR == 1 { next }
    $2 != j { next }
    $3 == "Failed" || $3 == "FailureTarget" { failed = 1 }
    {
      if ($1 == "ADDED") added = 1
      one_of_one = 0
      for (i = 4; i <= NF; i++) if ($i == "1/1") one_of_one = 1
      if (added && $1 != "DELETED" && $3 == "Complete" && one_of_one) completed = 1
      if (completed && $1 == "DELETED") deleted = 1
    }
    END {
      if (failed) print "FAILED"
      else if (added && completed && deleted) print "OK"
      else print "MISSING"
    }' "$1"
}

# wait_for_event FILE EVENT NAME SECONDS: succeeds when "EVENT NAME ..." appears in FILE.
wait_for_event() {
  local file="$1" ev="$2" name="$3" secs="$4" i=0
  while [ "$i" -lt "$secs" ]; do
    if awk -v e="$ev" -v n="$name" '$1==e && $2==n {found=1} END{exit !found}' "$file" 2>/dev/null; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

# start_watch NAME CMD...: background watcher, registered and listed in watchers.pids for health sampling.
# Sets WPID. Returns non-zero if the watcher is not running two seconds after start.
start_watch() {
  local name="$1"; shift
  "$@" > "$EV/$name.txt" 2> "$EV/$name.err" &
  WPID=$!
  track "$WPID" "$name"
  if ! printf '%s %s\n' "$name" "$WPID" >> "$EV/watchers.pids" 2>/dev/null; then
    EVIDENCE_WRITE_FAILED=1
  fi
  sleep 2
  if pid_alive "$WPID"; then
    log "watch $name running pid=$WPID"
    return 0
  fi
  log "watch $name exited at start"
  return 1
}

# run_probe: a ConfigMap watch must stream ADDED and DELETED rows, in the expected layout, before any real
# watcher is trusted. The probe is not listed in watchers.pids, so the health sampler never counts it.
run_probe() {
  kubectl get configmaps -n "$NS" --field-selector "metadata.name=$PROBE_CM" \
    -w --output-watch-events \
    > "$EV/probe.txt" 2> "$EV/probe.err" &
  local probe_pid=$!
  local r
  track "$probe_pid" probe
  sleep 2
  if ! pid_alive "$probe_pid"; then
    note_inc "probe watch did not start"
    return 1
  fi
  if ! query probe-create kubectl create configmap "$PROBE_CM" -n "$NS" --from-literal=probe=1; then
    note_inc "probe ConfigMap create failed"
    stop_pid "$probe_pid"
    return 1
  fi
  if ! wait_for_event "$EV/probe.txt" ADDED "$PROBE_CM" 20; then
    note_inc "probe watch did not stream an ADDED row in the expected layout"
  fi
  if ! query probe-delete kubectl delete configmap "$PROBE_CM" -n "$NS"; then
    note_inc "probe ConfigMap delete failed"
  fi
  if ! wait_for_event "$EV/probe.txt" DELETED "$PROBE_CM" 20; then
    note_inc "probe watch did not stream a DELETED row in the expected layout"
  fi
  if ! pid_alive "$probe_pid"; then
    note_inc "probe watch exited before the probe finished"
  fi
  if ! r="$(check_watch "$EV/probe.txt" "$CM_HEADER" other)"; then
    note_inc "probe output does not match the expected layout: $r (see probe.txt)"
  fi
  stop_pid "$probe_pid"
  if [ -n "$INCS" ]; then return 1; fi
  return 0
}

# start_job_and_pod_watches: default table for Jobs and -o wide for Pods (Option B). The Job watch covers the
# namespace, and evaluation filters rows by name, because a name field selector cannot match the readiness
# sentinel. The Pod watch uses the hook's label selector. custom-columns is not used: with --output-watch-events
# it printed no EVENT column and <none> for every object field (probe, 2026-11-09).
start_job_and_pod_watches() {
  start_watch jobwatch kubectl get jobs -n "$NS" -w --output-watch-events \
    || { note_inc "job watch did not start"; return 1; }
  start_watch podwatch kubectl get pods -n "$NS" -l "$HOOK_POD_SELECTOR" -o wide -w --output-watch-events \
    || { note_inc "pod watch did not start"; return 1; }
  return 0
}

# validate_sentinel_rows FILE POD: rules for the sentinel Pod's rows in the -o wide layout. Fields used: 1 EVENT,
# 2 NAME, 4 STATUS, 7 IP, 8 NODE. The first row must be ADDED and the last must be DELETED. Every row must have
# IP and NODE both <none>. Every row before the last two must have STATUS SchedulingGated. Of the last two, only
# a MODIFIED or DELETED row may be Terminating. A DELETED row before the last row is a violation. Any other STATUS
# (Pending, Running and so on) means the gate was removed or the Pod was processed. Prints the reason and returns
# 1 on any violation or missing row. The caller reports that as INCONCLUSIVE. A watch gap can hide transitions,
# which is a residual risk documented in establish_watch_readiness.
validate_sentinel_rows() {
  awk -v p="$2" '
    NR == 1 { next }
    $2 != p { next }
    { n++; ev[n] = $1; st[n] = $4; ip[n] = $7; nd[n] = $8 }
    END {
      if (n < 2) { print "fewer than two rows for " p; exit 1 }
      if (ev[1] != "ADDED") { print "first row is " ev[1] ", not ADDED"; exit 1 }
      if (ev[n] != "DELETED") { print "last row is " ev[n] ", not DELETED"; exit 1 }
      for (i = 1; i <= n; i++) {
        if (ip[i] != "<none>" || nd[i] != "<none>") { print "row " i " has IP " ip[i] " or NODE " nd[i] " set"; exit 1 }
        if (ev[i] == "DELETED" && i < n) { print "row " i " is DELETED before the last row"; exit 1 }
        if (st[i] == "SchedulingGated") continue
        if (st[i] == "Terminating" && i >= n - 1 && ev[i] != "ADDED") continue
        print "row " i " has STATUS " st[i] "; expected SchedulingGated"; exit 1
      }
      exit 0
    }' "$1"
}

# require_server_version: the sentinel Pod needs spec.schedulingGates and the suspended Job needs batch/v1 suspend.
# The minimum is MIN_K8S_MINOR (1.30). The server version is recorded. Failed or unparseable discovery, or a
# version below the minimum, is INCONCLUSIVE and returns 1. This runs before any cluster change in the no-hooks script.
require_server_version() {
  local major minor
  # /version returns only the server's version. kubectl version -o json also carries clientVersion, so it is not
  # used. jsonpath is not a valid output format for kubectl version.
  if ! query server-version kubectl get --raw /version; then
    note_inc "server version discovery failed (see server-version.err)"
    return 1
  fi
  major="$(awk -F'"' '$2 == "major" {print $4; exit}' "$EV/server-version.txt" 2>/dev/null)"
  minor="$(awk -F'"' '$2 == "minor" {print $4; exit}' "$EV/server-version.txt" 2>/dev/null)"
  major="${major%%[!0-9]*}"
  minor="${minor%%[!0-9]*}"
  case "$major" in
    ''|*[!0-9]*) note_inc "server major version is unparseable: '$major'"; return 1 ;;
  esac
  case "$minor" in
    ''|*[!0-9]*) note_inc "server minor version is unparseable: '$minor'"; return 1 ;;
  esac
  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt "$MIN_K8S_MINOR" ]; }; then
    note_inc "server version $major.$minor is below 1.$MIN_K8S_MINOR; schedulingGates behaviour is not established"
    return 1
  fi
  log "server version $major.$minor accepted"
  return 0
}

# final_snapshot: supplementary evidence, taken after the uninstall and before namespace cleanup. It records
# the Jobs and Pods that remain. It never sets a PASS, and a clean snapshot never replaces watcher evidence.
# A failed snapshot is INCONCLUSIVE, because the evidence it should record is missing.
final_snapshot() {
  if ! query final-jobs kubectl get jobs -n "$NS" -o name; then
    note_inc "final Jobs snapshot failed (see final-jobs.err)"
    return 1
  fi
  if ! query final-pods kubectl get pods -n "$NS" -o name; then
    note_inc "final Pods snapshot failed (see final-pods.err)"
    return 1
  fi
  return 0
}

# establish_watch_readiness: proves that the real Job and Pod watchers deliver events before Helm runs.
# Empty watch output is never read as proof that the hook did not run. Two sentinel objects pass through the
# same watchers: a suspended Job, and a Pod with exactly one test-owned scheduling gate (SENTINEL_GATE) and a
# spec.schedulerName unique to this run. The gate stops the scheduler from considering the Pod. The unique name
# is a second layer. An unbound Pod is never run by a kubelet, so no image is pulled. The gate is read back after
# creation, and every watch row for the Pod is validated through its DELETED row, which carries the final state.
# Residual risks, not eliminated by this code: the guarantee depends on the API server honoring
# spec.schedulingGates and spec.schedulerName; a watch gap can hide a transition, because kubectl does not replay
# events and the health monitor detects only dead processes; and a principal with authority to patch this Pod in
# this namespace could remove the gate. The namespace is created for this test and deleted afterwards.
# Their names contain keep-uninstall-readiness, so they cannot match the hook's Job or Pod names. The Pod
# carries the hook's label, so the Pod watch must see it. Both sentinels must appear as ADDED and as DELETED.
# Any missing event, malformed or unexpected row, or dead watcher returns 1, and the caller stops with
# INCONCLUSIVE. Deletion uses no force flags. A failed deletion is INCONCLUSIVE, never a readiness pass.
establish_watch_readiness() {
  local job="keep-uninstall-readiness-$SUFFIX" pod="keep-uninstall-readiness-pod-$SUFFIX" wname wpid
  while read -r wname wpid; do
    if ! pid_alive "$wpid"; then
      note_inc "watcher $wname is not running at the readiness check"
      return 1
    fi
  done < "$EV/watchers.pids"
  local sched r
  sched="keep-uninstall-readiness-$(printf '%s' "${EV##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$sched" in
    keep-uninstall-readiness-|*[!a-z0-9-]*)
      note_inc "cannot derive a valid schedulerName from the evidence folder suffix"
      return 1
      ;;
  esac
  cat > "$EV/readiness-job.yaml" <<EOF || { note_inc "cannot write readiness-job.yaml"; return 1; }
apiVersion: batch/v1
kind: Job
metadata:
  name: $job
spec:
  suspend: true
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: readiness
        image: $READINESS_IMAGE
EOF
  cat > "$EV/readiness-pod.yaml" <<EOF || { note_inc "cannot write readiness-pod.yaml"; return 1; }
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  labels:
    batch.kubernetes.io/job-name: $HOOK_JOB
spec:
  restartPolicy: Never
  schedulerName: $sched
  schedulingGates:
  - name: $SENTINEL_GATE
  containers:
  - name: readiness
    image: $READINESS_IMAGE
EOF
  if ! query create-readiness-job kubectl create -n "$NS" -f "$EV/readiness-job.yaml"; then
    note_inc "readiness Job could not be created (see create-readiness-job.err)"
    return 1
  fi
  if ! query create-readiness-pod kubectl create -n "$NS" -f "$EV/readiness-pod.yaml"; then
    note_inc "readiness Pod could not be created (see create-readiness-pod.err)"
    return 1
  fi
  if ! wait_for_event "$EV/jobwatch.txt" ADDED "$job" 20; then
    note_inc "job watch did not deliver ADDED for the readiness Job; the Job watcher is not proven"
    return 1
  fi
  if ! wait_for_event "$EV/podwatch.txt" ADDED "$pod" 20; then
    note_inc "pod watch did not deliver ADDED for the readiness Pod; the Pod watcher is not proven"
    return 1
  fi
  # The sentinel must stay unbound and unstarted. Every state query must succeed.
  if ! query readiness-pod-state kubectl get pod "$pod" -n "$NS" -o json; then
    note_inc "readiness Pod state could not be read (see readiness-pod-state.err); readiness not established"
    return 1
  fi
  if ! query readiness-pod-phase kubectl get pod "$pod" -n "$NS" -o jsonpath='{.status.phase}'; then
    note_inc "readiness Pod phase could not be read (see readiness-pod-phase.err)"
    return 1
  fi
  if ! query readiness-pod-node kubectl get pod "$pod" -n "$NS" -o jsonpath='{.spec.nodeName}'; then
    note_inc "readiness Pod nodeName could not be read (see readiness-pod-node.err)"
    return 1
  fi
  if ! query readiness-pod-containers kubectl get pod "$pod" -n "$NS" -o jsonpath='{.status.containerStatuses}'; then
    note_inc "readiness Pod containerStatuses could not be read (see readiness-pod-containers.err)"
    return 1
  fi
  if ! query readiness-pod-gates kubectl get pod "$pod" -n "$NS" -o jsonpath='{.spec.schedulingGates[*].name}'; then
    note_inc "readiness Pod scheduling gates could not be read (see readiness-pod-gates.err)"
    return 1
  fi
  if [ "$(cat "$EV/readiness-pod-gates.txt")" != "$SENTINEL_GATE" ]; then
    note_inc "readiness Pod does not carry exactly the expected scheduling gate (see readiness-pod-gates.txt)"
    return 1
  fi
  if ! query readiness-pod-scheduler kubectl get pod "$pod" -n "$NS" -o jsonpath='{.spec.schedulerName}'; then
    note_inc "readiness Pod schedulerName could not be read (see readiness-pod-scheduler.err)"
    return 1
  fi
  if [ "$(cat "$EV/readiness-pod-scheduler.txt")" != "$sched" ]; then
    note_inc "readiness Pod schedulerName does not match the per-run name"
    return 1
  fi
  if [ "$(cat "$EV/readiness-pod-phase.txt")" != "Pending" ]; then
    note_inc "readiness Pod phase is not Pending; the sentinel may have been processed (see readiness-pod-state.txt)"
    return 1
  fi
  if [ -s "$EV/readiness-pod-node.txt" ]; then
    note_inc "readiness Pod has spec.nodeName set; the sentinel was bound (see readiness-pod-state.txt)"
    return 1
  fi
  if [ -s "$EV/readiness-pod-containers.txt" ]; then
    note_inc "readiness Pod has containerStatuses; the sentinel was started (see readiness-pod-state.txt)"
    return 1
  fi
  if ! r="$(check_watch "$EV/jobwatch.txt" "$JOB_HEADER" job)"; then
    note_inc "readiness: job watch: $r"
    return 1
  fi
  if ! r="$(check_watch "$EV/podwatch.txt" "$POD_HEADER" pod)"; then
    note_inc "readiness: pod watch: $r"
    return 1
  fi
  if ! query delete-readiness kubectl delete -n "$NS" "job/$job" "pod/$pod" --wait=true --timeout=60s; then
    note_inc "readiness objects could not be deleted (see delete-readiness.err)"
    return 1
  fi
  if ! wait_for_event "$EV/jobwatch.txt" DELETED "$job" 20; then
    note_inc "job watch did not deliver DELETED for the readiness Job"
    return 1
  fi
  if ! wait_for_event "$EV/podwatch.txt" DELETED "$pod" 20; then
    note_inc "pod watch did not deliver DELETED for the readiness Pod"
    return 1
  fi
  if ! r="$(validate_sentinel_rows "$EV/podwatch.txt" "$pod")"; then
    note_inc "sentinel Pod watch rows do not match the expected lifecycle: $r (see podwatch.txt)"
    return 1
  fi
  while read -r wname wpid; do
    if ! pid_alive "$wpid"; then
      note_inc "watcher $wname stopped during the readiness check"
      return 1
    fi
  done < "$EV/watchers.pids"
  log "watch readiness established for $job and $pod"
  return 0
}

# start_health_monitor: every 2 seconds, writes "OK <time>" when all listed watchers are alive, and
# "DEAD <time> <name> pid=<n>" for each dead one. Its sleep is tracked and stopped by a TERM trap.
start_health_monitor() {
  (
    hs=""
    trap 'if [ -n "$hs" ]; then kill "$hs" 2>/dev/null; fi; exit 0' TERM INT
    while :; do
      bad=0
      while read -r wname wpid; do
        if ! pid_alive "$wpid"; then
          echo "DEAD $(date -u +%H:%M:%S) $wname pid=$wpid"
          bad=1
        fi
      done < "$EV/watchers.pids" >> "$EV/watchers-health.txt"
      if [ "$bad" -eq 0 ]; then
        echo "OK $(date -u +%H:%M:%S)" >> "$EV/watchers-health.txt"
      fi
      sleep 2 &
      hs=$!
      wait "$hs"
    done
  ) &
  HEALTH_PID=$!
  track "$HEALTH_PID" health-monitor
}

# ---- Timed commands ----

# run_limited SECONDS CMD...: runs CMD with a time limit, without GNU timeout.
# The command is polled, never blocked on. A watchdog stops it by PID at the limit, after writing a marker,
# so a timeout is never mistaken for an ordinary exit. Returns the command's exit status, or:
#   124  the time limit was reached,
#   125  the exit status could not be read,
#   126  the command could not be confirmed stopped (INCONCLUSIVE).
run_limited() {
  local secs="$1"; shift
  local pid wd rc marker i max
  RL_SEQ=$((RL_SEQ + 1))
  marker="$EV/limit-$RL_SEQ.fired"
  "$@" &
  pid=$!
  track "$pid" command
  (
    sp=""
    trap 'if [ -n "$sp" ]; then kill "$sp" 2>/dev/null; fi; exit 0' TERM INT
    sleep "$secs" &
    sp=$!
    wait "$sp"
    : > "$marker" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null
    sleep "$KILL_GRACE_SECONDS" &
    sp=$!
    wait "$sp"
    kill -KILL "$pid" 2>/dev/null
  ) &
  wd=$!
  track "$wd" watchdog
  max=$((secs + KILL_GRACE_SECONDS + KILL_WAIT_SECONDS + 5))
  i=0
  while pid_alive "$pid" && [ "$i" -lt "$max" ]; do
    sleep 1
    i=$((i + 1))
  done
  if pid_alive "$pid"; then
    note_inc "command PID $pid could not be confirmed stopped"
    stop_pid "$wd"
    return 126
  fi
  stop_pid "$wd"
  wait "$pid" 2>/dev/null
  rc=$?
  unregister_pid "$pid"
  if [ -e "$marker" ]; then
    return 124
  fi
  if [ "$rc" -eq 127 ]; then
    return 125
  fi
  return "$rc"
}

# run_uninstall EXTRA: EXTRA is "" for the normal uninstall, or "--no-hooks" for the documented command.
# Records HELM_EXIT. Only exit 0 is success. 124 and other statuses are FAIL. 125 and 126 are INCONCLUSIVE.
run_uninstall() {
  local extra="$1"
  local rc
  if [ -n "$extra" ]; then
    run_limited 900 helm uninstall keep -n "$NS" "$extra" --wait --timeout 600s \
      > "$EV/helm-uninstall.out" 2> "$EV/helm-uninstall.err"
  else
    run_limited 900 helm uninstall keep -n "$NS" --wait --timeout 600s \
      > "$EV/helm-uninstall.out" 2> "$EV/helm-uninstall.err"
  fi
  rc=$?
  evwrite "$EV/helm-exit.txt" "HELM_EXIT=$rc" || note_inc "cannot write helm-exit.txt"
  log "helm uninstall rc=$rc"
  case "$rc" in
    0) ;;
    124) note_fail "helm uninstall exceeded the 900 s limit" ;;
    125) note_inc "helm uninstall exit status could not be read" ;;
    126) note_inc "helm uninstall could not be confirmed stopped" ;;
    *) note_fail "helm uninstall exited $rc" ;;
  esac
  return "$rc"
}

# require_evidence_file PATH LABEL: a missing evidence file is INCONCLUSIVE, never a pass.
require_evidence_file() {
  if [ ! -e "$1" ]; then
    note_inc "$2 is missing: $1"
    return 1
  fi
  return 0
}

# ---- Cluster steps ----

# require_keep_installed: Keep must already be installed by the operator. Any error refuses the run.
require_keep_installed() {
  if ! helm status keep -n "$NS" > "$EV/helm-status-pre.txt" 2> "$EV/helm-status-pre.err"; then
    refuse "Keep is not installed in $NS (see the install steps); see $EV/helm-status-pre.err"
  fi
  if ! query fresh-secrets kubectl get secret -n "$NS" -o name; then
    refuse "cannot list Secrets in $NS (see $EV/fresh-secrets.err)"
  fi
  if grep -Fxq "secret/keep-decoy-$SUFFIX" "$EV/fresh-secrets.txt" || grep -Fxq "secret/sre-keep-decoy-$SUFFIX" "$EV/fresh-secrets.txt"; then
    refuse "decoy Secrets already exist in $NS; use a fresh namespace"
  fi
}

# create_decoys: dummy values only. CHANGED is set first, so cleanup covers a partial run.
create_decoys() {
  CHANGED=1
  if ! query create-keep-decoy kubectl create secret generic "keep-decoy-$SUFFIX" -n "$NS" --from-literal=decoy="$DECOY_VALUE"; then
    note_inc "could not create keep-decoy-$SUFFIX"
    return 1
  fi
  if ! query create-sre-decoy kubectl create secret generic "sre-keep-decoy-$SUFFIX" -n "$NS" --from-literal=decoy="$DECOY_VALUE"; then
    note_inc "could not create sre-keep-decoy-$SUFFIX"
    return 1
  fi
  return 0
}

# before_snapshot: names only. Both decoys must exist, or no deletion can be shown.
before_snapshot() {
  if ! query before-secrets kubectl get secret -n "$NS" -o name; then
    note_inc "before-secrets query failed"
    return 1
  fi
  if [ ! -s "$EV/before-secrets.txt" ]; then
    note_inc "before-secrets.txt is empty"
    return 1
  fi
  if ! grep -Fxq "secret/keep-decoy-$SUFFIX" "$EV/before-secrets.txt"; then
    note_inc "keep-decoy-$SUFFIX is missing before uninstall"
    return 1
  fi
  if ! grep -Fxq "secret/sre-keep-decoy-$SUFFIX" "$EV/before-secrets.txt"; then
    note_inc "sre-keep-decoy-$SUFFIX is missing before uninstall"
    return 1
  fi
  if ! awk '/^secret\/keep-/' "$EV/before-secrets.txt" > "$EV/before-keep-names.txt"; then
    note_inc "cannot write before-keep-names.txt"
    return 1
  fi
  return 0
}

# validate_control_evidence FOLDER: the no-hooks run is allowed only with a genuine positive-control PASS
# recorded with the same scripts. Every check must hold. Any failure is INCONCLUSIVE and returns 1.
validate_control_evidence() {
  local d="$1" f line n
  if [ -z "$d" ]; then
    note_inc "no positive-control evidence: CONTROL_EVIDENCE is empty"
    return 1
  fi
  if [ ! -d "$d" ]; then
    note_inc "CONTROL_EVIDENCE is not a folder: $d"
    return 1
  fi
  for f in verdict.txt verdict-reasons.txt namespace.txt kubectl-context.txt helm-exit.txt \
           jobwatch.txt podwatch.txt after-secrets.txt hook-logs.txt hook-logs.status script-hashes.txt; do
    if [ ! -e "$d/$f" ]; then
      note_inc "positive-control evidence is missing $f: $d"
      return 1
    fi
  done
  if ! grep -Fxq 'VERDICT=PASS' "$d/verdict.txt" 2>/dev/null; then
    note_inc "positive-control verdict is not PASS: $d"; return 1
  fi
  if ! grep -Fxq 'MODE=control' "$d/verdict.txt" 2>/dev/null; then
    note_inc "CONTROL_EVIDENCE is not a positive-control run: $d"; return 1
  fi
  if ! grep -Fxq "NAMESPACE=keep-uninstall-control" "$d/verdict.txt" 2>/dev/null; then
    note_inc "positive-control verdict names a different namespace: $d"; return 1
  fi
  if ! grep -Fxq 'FAILS=' "$d/verdict-reasons.txt" 2>/dev/null; then
    note_inc "positive-control verdict lists failures: $d"; return 1
  fi
  if ! grep -Fxq 'INCONCLUSIVE=' "$d/verdict-reasons.txt" 2>/dev/null; then
    note_inc "positive-control verdict lists inconclusive checks: $d"; return 1
  fi
  if ! grep -Fxq 'MISSING_CHECKS=' "$d/verdict-reasons.txt" 2>/dev/null; then
    note_inc "positive-control verdict does not show that every required check ran: $d"; return 1
  fi
  if ! grep -Fxq 'HELM_EXIT=0' "$d/helm-exit.txt" 2>/dev/null; then
    note_inc "positive-control helm uninstall did not exit 0: $d"; return 1
  fi
  if ! grep -Fxq 'keep-uninstall-control' "$d/namespace.txt" 2>/dev/null; then
    note_inc "positive-control namespace.txt does not name keep-uninstall-control: $d"; return 1
  fi
  if ! grep -Fxq "$EXPECTED_CONTEXT" "$d/kubectl-context.txt" 2>/dev/null; then
    note_inc "positive-control ran on a different context: $d"; return 1
  fi
  if ! grep -Fxq 'rc=0' "$d/hook-logs.status" 2>/dev/null; then
    note_inc "positive-control hook logs were not captured cleanly: $d"; return 1
  fi
  if [ ! -s "$d/hook-logs.txt" ]; then
    note_inc "positive-control hook-logs.txt is empty: $d"; return 1
  fi
  if ! grep -Fq 'secret "keep-decoy-control" deleted' "$d/hook-logs.txt" 2>/dev/null; then
    note_inc "positive-control logs do not show the matching decoy deleted: $d"; return 1
  fi
  local r
  if ! r="$(check_watch "$d/jobwatch.txt" "$JOB_HEADER" job)"; then
    note_inc "positive-control job watch does not match the expected layout: $r: $d"; return 1
  fi
  if ! r="$(check_watch "$d/podwatch.txt" "$POD_HEADER" pod)"; then
    note_inc "positive-control pod watch does not match the expected layout: $r: $d"; return 1
  fi
  case "$(job_control_state "$d/jobwatch.txt" "$HOOK_JOB")" in
    OK) ;;
    FAILED) note_inc "positive-control hook Job reported Failed or FailureTarget: $d"; return 1 ;;
    *) note_inc "positive-control job watch lacks ADDED, then Complete 1/1, then DELETED: $d"; return 1 ;;
  esac
  if ! awk -v p="$HOOK_JOB-" '$1=="ADDED" && index($2, p)==1 {f=1} END{exit !f}' "$d/podwatch.txt" 2>/dev/null; then
    note_inc "positive-control pod watch lacks an ADDED hook Pod: $d"; return 1
  fi
  # Script integrity: the control must have run with exactly the scripts on disk now.
  n="$(grep -c '' "$d/script-hashes.txt" 2>/dev/null)" || n=0
  if [ "$n" != "3" ]; then
    note_inc "positive-control script-hashes.txt does not list three scripts: $d"; return 1
  fi
  while IFS= read -r line; do
    if ! grep -Fxq -- "$line" "$EV/script-hashes.txt" 2>/dev/null; then
      note_inc "positive-control was run with different script contents (hash mismatch): $d"
      return 1
    fi
  done < "$d/script-hashes.txt"
  return 0
}

# after_state: waits the observation window, then records release status, Secret names and hook events.
after_state() {
  sleep "$HOLD_SECONDS"
  if helm status keep -n "$NS" > "$EV/helm-status-post.txt" 2> "$EV/helm-status-post.err"; then
    note_fail "release keep is still installed in $NS after uninstall"
  elif ! grep -q 'not found' "$EV/helm-status-post.err" "$EV/helm-status-post.txt" 2>/dev/null; then
    note_inc "helm status after uninstall failed for a reason other than 'not found' (see helm-status-post.err)"
  fi
  if ! query after-secrets kubectl get secret -n "$NS" -o name; then
    note_inc "after-secrets query failed"
  fi
  if ! query events kubectl get events -n "$NS" --field-selector "involvedObject.name=$HOOK_JOB"; then
    note_inc "events query failed"
  fi
}

# stop_watchers_after_recording: stops the health sampler, records each watcher's state, then stops each
# watcher by its recorded PID.
stop_watchers_after_recording() {
  local wname wpid
  if [ -n "$HEALTH_PID" ]; then
    stop_pid "$HEALTH_PID"
  fi
  if ! : > "$EV/watchers-final.txt" 2>/dev/null; then
    note_inc "cannot write watchers-final.txt"
    return 1
  fi
  while read -r wname wpid; do
    if pid_alive "$wpid"; then
      echo "$wname alive" >> "$EV/watchers-final.txt" 2>/dev/null || EVIDENCE_WRITE_FAILED=1
    else
      echo "$wname exited" >> "$EV/watchers-final.txt" 2>/dev/null || EVIDENCE_WRITE_FAILED=1
    fi
  done < "$EV/watchers.pids"
  if grep -q 'exited' "$EV/watchers-final.txt" 2>/dev/null; then
    note_inc "a watcher exited before the end of the test (see watchers-final.txt)"
  fi
  while read -r wname wpid; do
    stop_pid "$wpid"
  done < "$EV/watchers.pids"
  return 0
}

# check_health: needs MIN_HEALTH_SAMPLES OK samples and no DEAD line. An unreadable log is INCONCLUSIVE.
check_health() {
  local ok rc
  if [ ! -s "$EV/watchers-health.txt" ]; then
    note_inc "watcher health log is missing or empty"
    return
  fi
  if grep -q '^DEAD' "$EV/watchers-health.txt"; then
    note_inc "a watcher was dead at a health sample (see watchers-health.txt)"
  fi
  grep -c '^OK' "$EV/watchers-health.txt" > "$EV/health-ok-count.txt" 2>/dev/null
  rc=$?
  if [ "$rc" -gt 1 ]; then
    note_inc "cannot count health samples (see watchers-health.txt)"
    return
  fi
  ok="$(cat "$EV/health-ok-count.txt" 2>/dev/null)"
  case "$ok" in
    ''|*[!0-9]*) note_inc "health sample count is unreadable"; return ;;
  esac
  if [ "$ok" -lt "$MIN_HEALTH_SAMPLES" ]; then
    note_inc "only $ok watcher health samples; at least $MIN_HEALTH_SAMPLES are needed"
  fi
}

# start_hook_log_capture: positive control only. The hook uses hook-succeeded,hook-failed, so its Pod is removed
# after the hook ends. This tracked subshell finds the Pod, then calls plain kubectl logs (no --follow) every
# LOG_RETRY_INTERVAL seconds. It stops when a call succeeds with non-empty output, when the Pod is gone
# (NotFound), or when LOG_RETRY_SECONDS have passed. A call that succeeds with empty output is not a success,
# so the loop continues until the bound. Every attempt writes its own files, hook-logs-attempt-N.txt and
# hook-logs-attempt-N.err, and appends one line to hook-logs.attempts as it happens (attempt, exit code, first
# line of the error), so a stop still leaves a record. The first non-empty success is copied once to
# hook-logs.txt. No file name is written twice, so noclobber (set -C) never blocks a retry. hook-logs.status
# is rc=0 only for a non-empty success; finish_hook_log_capture reads it.
start_hook_log_capture() {
  (
    pod=""
    i=0
    while [ "$i" -lt 600 ]; do
      pod="$(kubectl get pods -n "$NS" -l "$HOOK_POD_SELECTOR" -o name 2>/dev/null | head -n 1)"
      if [ -n "$pod" ]; then break; fi
      sleep 0.5
      i=$((i + 1))
    done
    if [ -z "$pod" ]; then
      echo "no hook pod was seen" > "$EV/hook-logs.status"
      exit 0
    fi
    attempts=0
    result=""
    start=$SECONDS
    while :; do
      attempts=$((attempts + 1))
      attempt_out="$EV/hook-logs-attempt-$attempts.txt"
      attempt_err="$EV/hook-logs-attempt-$attempts.err"
      kubectl logs -n "$NS" "$pod" > "$attempt_out" 2> "$attempt_err"
      rc=$?
      first_line="$(head -n 1 "$attempt_err" 2>/dev/null)"
      if [ "$rc" -eq 0 ] && [ ! -s "$attempt_out" ]; then
        first_line="(call succeeded with empty output)"
      fi
      printf 'attempt=%s exit=%s error=%s\n' "$attempts" "$rc" "$first_line" >> "$EV/hook-logs.attempts"
      if [ "$rc" -eq 0 ] && [ -s "$attempt_out" ]; then
        cat "$attempt_out" > "$EV/hook-logs.txt"
        result=ok
        break
      fi
      if ! kubectl get "$pod" -n "$NS" -o name > /dev/null 2> "$EV/hook-pod-check-attempt-$attempts.err"; then
        if grep -q NotFound "$EV/hook-pod-check-attempt-$attempts.err"; then
          result=pod_gone
          break
        fi
      fi
      if [ $((SECONDS - start)) -ge "$LOG_RETRY_SECONDS" ]; then
        result=bound
        break
      fi
      sleep "$LOG_RETRY_INTERVAL"
    done
    printf 'result=%s\n' "$result" >> "$EV/hook-logs.attempts"
    if [ "$result" = ok ]; then
      echo "rc=0" > "$EV/hook-logs.status"
    else
      echo "rc=1" > "$EV/hook-logs.status"
    fi
    exit 0
  ) &
  LOGC=$!
  track "$LOGC" hook-log-capture
}

# finish_hook_log_capture: polls up to LOG_WAIT_SECONDS for the follower, then stops it by PID. Records the
# exit status only once the process has ended. Missing or empty logs are INCONCLUSIVE.
finish_hook_log_capture() {
  if [ -z "$LOGC" ]; then return 0; fi
  local i=0 rc
  while pid_alive "$LOGC" && [ "$i" -lt "$LOG_WAIT_SECONDS" ]; do
    sleep 1
    i=$((i + 1))
  done
  if pid_alive "$LOGC"; then
    note_inc "hook log capture was still running after $LOG_WAIT_SECONDS s and was stopped"
    stop_pid "$LOGC"
    if [ ! -s "$EV/hook-logs.status" ]; then
      evwrite "$EV/hook-logs.status" "rc=stopped" || note_inc "cannot write hook-logs.status"
    fi
  else
    wait "$LOGC" 2>/dev/null
    rc=$?
    unregister_pid "$LOGC"
    if [ ! -s "$EV/hook-logs.status" ]; then
      evwrite "$EV/hook-logs.status" "rc=$rc" || note_inc "cannot write hook-logs.status"
    fi
  fi
  if ! grep -Fxq "rc=0" "$EV/hook-logs.status" 2>/dev/null; then
    note_inc "hook logs were not captured cleanly (see hook-logs.status)"
  fi
  if [ ! -s "$EV/hook-logs.txt" ]; then
    note_inc "hook-logs.txt is empty or missing"
  fi
}

# expect_present NAME FILE LABEL / expect_absent NAME FILE LABEL: exact whole-line match.
# Exit 2 from grep (unreadable or missing file) is INCONCLUSIVE, never a pass.
expect_present() {
  grep -Fxq -- "$1" "$2"
  local rc=$?
  case $rc in
    0) ;;
    1) note_fail "$3: $1 is missing" ;;
    *) note_inc "$3: cannot read $2" ;;
  esac
}
expect_absent() {
  grep -Fxq -- "$1" "$2"
  local rc=$?
  case $rc in
    0) note_fail "$3: $1 still exists" ;;
    1) ;;
    *) note_inc "$3: cannot read $2" ;;
  esac
}

# cleanup_namespace: runs only after all evidence has been collected. Writes cleanup.txt.
# Returns 0 on success or retention, 1 on failure. The caller records a failure as INCONCLUSIVE.
cleanup_namespace() {
  if [ "$CHANGED" -ne 1 ]; then
    evwrite "$EV/cleanup.txt" "NAMESPACE_CLEANUP=not-needed (nothing was created)" || true
    return 0
  fi
  if [ "${KEEP_NS:-0}" = "1" ]; then
    evwrite "$EV/cleanup.txt" "NAMESPACE_CLEANUP=retained (KEEP_NS=1)" || true
    echo "namespace $NS retained because KEEP_NS=1" >&2
    return 0
  fi
  if ! query ns-delete kubectl delete namespace "$NS" --ignore-not-found --wait --timeout=300s; then
    evwrite "$EV/cleanup.txt" "NAMESPACE_CLEANUP=failed: delete command failed (see ns-delete.err)" || true
    return 1
  fi
  if ! query ns-gone kubectl get namespace "$NS" -o name --ignore-not-found; then
    evwrite "$EV/cleanup.txt" "NAMESPACE_CLEANUP=failed: could not confirm removal (see ns-gone.err)" || true
    return 1
  fi
  if [ -s "$EV/ns-gone.txt" ]; then
    evwrite "$EV/cleanup.txt" "NAMESPACE_CLEANUP=failed: namespace still present" || true
    return 1
  fi
  evwrite "$EV/cleanup.txt" "NAMESPACE_CLEANUP=deleted" || true
  return 0
}

# finish: stops background processes, deletes the namespace after evidence collection, and writes the
# verdict last. The verdict includes the cleanup and process results. A verdict that cannot be persisted
# makes the exit code 3. Nothing removes the evidence folder.
# register_required_checks MODE: the checks that must run before a PASS can be recorded for MODE. Each script calls
# this right after install_traps, before any step that can stop early. An unknown MODE registers nothing, so
# finish records INCONCLUSIVE.
register_required_checks() {
  case "$1" in
    nohooks) REQUIRED_CHECKS="nohooks_job_absent nohooks_pod_absent nohooks_events_absent nohooks_decoy_keep_present nohooks_decoy_sre_present nohooks_keep_names_present nohooks_helm_released nohooks_health" ;;
    control) REQUIRED_CHECKS="control_job_watch control_pod_watch control_decoy_keep_absent control_decoy_sre_present control_keep_names_absent control_hook_log control_health" ;;
    *) note_inc "unknown mode for required checks: $1"; REQUIRED_CHECKS="" ;;
  esac
}

# check_done NAME: records that a registered check ran. Its result is recorded separately by note_fail or note_inc.
check_done() {
  DONE_CHECKS="$DONE_CHECKS $1"
}

# evaluate_nohooks DIR: the no-hooks evaluation, reading the evidence folder DIR. Every check calls check_done when
# it runs. A missing input is INCONCLUSIVE, never a pass. A hook Job or Pod created by the --no-hooks uninstall, a
# missing decoy, a surviving keep-* Secret, or a release that still reports STATUS is a FAIL.
evaluate_nohooks() {
  local dir="$1" r name saved_ev="$EV"
  check_done nohooks_job_absent
  if require_evidence_file "$dir/jobwatch.txt" "job watch"; then
    if ! r="$(check_watch "$dir/jobwatch.txt" "$JOB_HEADER" job)"; then
      note_inc "job watch: $r (see jobwatch.txt)"
    elif awk -v j="$HOOK_JOB" '$2==j && $1=="ADDED" {f=1} END{exit !f}' "$dir/jobwatch.txt" 2>/dev/null; then
      note_fail "a $HOOK_JOB Job was created during the --no-hooks uninstall"
    fi
  fi
  check_done nohooks_pod_absent
  if require_evidence_file "$dir/podwatch.txt" "pod watch"; then
    if ! r="$(check_watch "$dir/podwatch.txt" "$POD_HEADER" pod)"; then
      note_inc "pod watch: $r (see podwatch.txt)"
    elif awk -v p="$HOOK_JOB-" '$1=="ADDED" && index($2, p)==1 {f=1} END{exit !f}' "$dir/podwatch.txt" 2>/dev/null; then
      note_fail "a Pod of $HOOK_JOB was created during the --no-hooks uninstall"
    fi
  fi
  check_done nohooks_events_absent
  if require_evidence_file "$dir/events.txt" "hook events"; then
    if [ -s "$dir/events.txt" ] && grep -Fq "$HOOK_JOB" "$dir/events.txt"; then
      note_fail "an event for $HOOK_JOB exists after the --no-hooks uninstall"
    fi
  fi
  check_done nohooks_decoy_keep_present
  check_done nohooks_decoy_sre_present
  if require_evidence_file "$dir/after-secrets.txt" "after-uninstall Secret list"; then
    expect_present "secret/keep-decoy-$SUFFIX" "$dir/after-secrets.txt" "R3 --no-hooks"
    expect_present "secret/sre-keep-decoy-$SUFFIX" "$dir/after-secrets.txt" "R3 --no-hooks"
  fi
  check_done nohooks_keep_names_present
  if require_evidence_file "$dir/before-keep-names.txt" "before-uninstall keep-* name list"; then
    if [ -e "$dir/after-secrets.txt" ]; then
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        expect_present "$name" "$dir/after-secrets.txt" "R3 --no-hooks keeps every keep-* Secret"
      done < "$dir/before-keep-names.txt"
    fi
  fi
  check_done nohooks_helm_released
  if require_evidence_file "$dir/helm-status-post.err" "helm status after uninstall (stderr)"; then
    if [ -s "$dir/helm-status-post.txt" ] && grep -q '^STATUS:' "$dir/helm-status-post.txt" 2>/dev/null; then
      note_fail "release keep is still installed after the uninstall (helm status reports a STATUS)"
    elif ! grep -q 'not found' "$dir/helm-status-post.err" "$dir/helm-status-post.txt" 2>/dev/null; then
      note_inc "helm status after uninstall failed for a reason other than 'not found' (see helm-status-post.err)"
    fi
  fi
  check_done nohooks_health
  EV="$dir"
  check_health
  EV="$saved_ev"
}

finish() {
  if [ "$FINISHING" -eq 1 ]; then
    if [ -n "$EV" ] && [ ! -e "$EV/verdict.txt" ]; then
      printf 'VERDICT=INCONCLUSIVE\nMODE=%s\nNAMESPACE=%s\n' "$MODE" "$NS" > "$EV/verdict.txt" 2>/dev/null
    fi
    exit 3
  fi
  FINISHING=1
  if stop_background; then
    evwrite "$EV/process-cleanup.txt" "PROCESS_CLEANUP=confirmed" || true
  else
    note_inc "one or more processes could not be confirmed stopped (see pids.txt)"
    evwrite "$EV/process-cleanup.txt" "PROCESS_CLEANUP=not-confirmed" || true
  fi
  if ! cleanup_namespace; then
    note_inc "namespace cleanup failed (see cleanup.txt)"
  fi
  if [ "$EVIDENCE_WRITE_FAILED" -eq 1 ]; then
    note_inc "one or more evidence files could not be written"
  fi
  # Every registered check must have run. A check that did not run makes the verdict INCONCLUSIVE, and its name
  # is written to verdict-reasons.txt. With nothing registered, no PASS is possible.
  local verdict code c missing_list=""
  if [ -z "$REQUIRED_CHECKS" ]; then
    note_inc "no required checks were registered for this run"
  fi
  for c in $REQUIRED_CHECKS; do
    case " $DONE_CHECKS " in
      *" $c "*) ;;
      *) missing_list="$missing_list $c" ;;
    esac
  done
  missing_list="${missing_list# }"
  if [ -n "$missing_list" ]; then
    note_inc "required checks did not run: $missing_list"
  fi
  if [ -n "$FAILS" ]; then
    verdict=FAIL; code=1
  elif [ -n "$INCS" ]; then
    verdict=INCONCLUSIVE; code=3
  else
    verdict=PASS; code=0
  fi
  # Reasons first, verdict last: a persisted PASS cannot exist unless its reasons file was written.
  if ! printf 'FAILS=%s\nINCONCLUSIVE=%s\nMISSING_CHECKS=%s\n' "$FAILS" "$INCS" "$missing_list" > "$EV/verdict-reasons.txt" 2>/dev/null; then
    echo "EVIDENCE WRITE FAILED: $EV/verdict-reasons.txt; exiting INCONCLUSIVE without a verdict" >&2
    exit 3
  fi
  if ! printf 'VERDICT=%s\nMODE=%s\nNAMESPACE=%s\n' "$verdict" "$MODE" "$NS" > "$EV/verdict.txt" 2>/dev/null; then
    echo "EVIDENCE WRITE FAILED: $EV/verdict.txt; exiting INCONCLUSIVE" >&2
    exit 3
  fi
  echo "$verdict  (evidence: $EV)"
  exit "$code"
}

# install_traps: EXIT stops registered processes. INT and TERM record INCONCLUSIVE, then finish.
install_traps() {
  trap 'stop_background >/dev/null 2>&1' EXIT
  trap 'note_inc "interrupted by signal"; finish' INT TERM
}
