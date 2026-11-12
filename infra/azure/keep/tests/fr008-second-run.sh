#!/usr/bin/env bash
# fr008-second-run.sh: FR-008 second-run test (story #123, task T016). It runs setup-keep.sh twice against an existing
# Keep release, then compares the workloads before and after the second run, following research.md, FR-008 section.
# Secrets are compared by name, UID and creation time only (D3); no Secret value is read or printed. The generated
# credential files are compared by inode and mtime. Dummy AI key only, in a temp folder; never ~/.secrets/keep.
#
# Environment:
#   KEEP_NAMESPACE   namespace of the release (default: keep)
#   EVIDENCE_ROOT    folder that receives this run's evidence (default: TMPDIR or /tmp)
#   SETUP            the setup script to run (default: infra/azure/keep/setup-keep.sh beside this test)
# Exit codes: 0 PASS, 1 FAIL, 3 INCONCLUSIVE. Requires kubectl, jq and helm on PATH.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 3
SETUP="${SETUP:-$DIR/../setup-keep.sh}"
NS="${KEEP_NAMESPACE:-keep}"
EV_ROOT="${EVIDENCE_ROOT:-${TMPDIR:-/tmp}}"
EV="$(mktemp -d "$EV_ROOT/fr008-second-run.XXXXXX")" || exit 3
T="$(mktemp -d "${TMPDIR:-/tmp}/fr008-keys.XXXXXX")" || exit 3
trap 'rm -rf "$T"' EXIT

for tool in kubectl jq helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "INCONCLUSIVE: $tool not found on PATH"; exit 3; }
done

# The dummy key is written with umask 077, so it is mode 600 as setup-keep.sh requires (the key-mode check).
( umask 077; echo "dummy-value-not-a-credential" > "$T/fireworks.key" ) || exit 3
RESULT=PASS
REASONS=""
fail() { RESULT=FAIL; REASONS="$REASONS; $1"; }
inc() { if [ "$RESULT" != FAIL ]; then RESULT=INCONCLUSIVE; fi; REASONS="$REASONS; $1"; }

file_stat() {
  if [ "$(uname -s)" = "Darwin" ]; then stat -f '%i %m %Lp' "$1"; else stat -c '%i %Y %a' "$1"; fi
}

settle() { # no arguments: every Deployment rolled out and every Pod Ready
  local d
  for d in $(kubectl get deployment -n "$NS" -l app.kubernetes.io/instance=keep -o name); do
    kubectl rollout status "$d" -n "$NS" --timeout=300s >/dev/null 2>&1 || return 1
  done
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=keep -n "$NS" --timeout=300s >/dev/null 2>&1
}

snapshot() { # RUN label: workload objects (JSON, non-Secret kinds only), Secret metadata, Pod table
  local r="$1"
  kubectl get deploy,sts,rs,pod,svc,ingress,cm,job,cronjob,pvc,sa,role,rolebinding -n "$NS" \
    -l app.kubernetes.io/instance=keep -o json > "$EV/objects-$r.json" 2>"$EV/objects-$r.err" || return 1
  jq '[.items[] | {kind, name: .metadata.name, uid: .metadata.uid, created: .metadata.creationTimestamp,
       generation: .metadata.generation, spec: .spec, restarts: [.status.containerStatuses[]?.restartCount]}]
      | sort_by(.kind, .name)' "$EV/objects-$r.json" > "$EV/normalised-$r.json" || return 1
  kubectl get secret -n "$NS" -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,CREATED:.metadata.creationTimestamp \
    2>"$EV/secrets-$r.err" | grep -E '^(NAME|sre-keep-(db|ai-env|ai-frontend|auth)) ' > "$EV/secrets-$r.txt" || return 1
  kubectl get pods -n "$NS" > "$EV/pods-$r.txt" 2>&1 || return 1
  file_stat "$T/db-password" > "$EV/credfiles-$r.txt" 2>/dev/null || return 1
  file_stat "$T/nextauth-secret" >> "$EV/credfiles-$r.txt" 2>/dev/null || return 1
}

run_setup() { # RUN: the setup script with the temp folder and the release namespace
  env KEEP_SECRETS_DIR="$T" KEEP_NAMESPACE="$NS" bash "$SETUP" > "$EV/setup-$1.out" 2>&1
}

run_setup 1
rc1=$?
if [ "$rc1" -ne 0 ]; then
  inc "first run exited $rc1 (see setup-1.out); the second run was not started"
else
  settle || inc "rollout not settled before snapshot A"
  snapshot A || inc "snapshot A query failed"

  run_setup 2
  rc2=$?
  if [ "$rc2" -ne 0 ]; then
    fail "second run exited $rc2 (see setup-2.out)"
  fi

  sleep 60
  settle || inc "rollout not settled before snapshot B"
  snapshot B || inc "snapshot B query failed"

  if [ -s "$EV/normalised-A.json" ] && [ -s "$EV/normalised-B.json" ]; then
    diff "$EV/normalised-A.json" "$EV/normalised-B.json" > "$EV/workload.diff" 2>&1 \
      || fail "workload objects, pod UIDs or restart counts changed (see workload.diff)"
    diff "$EV/secrets-A.txt" "$EV/secrets-B.txt" > "$EV/secrets.diff" 2>&1 \
      || fail "a Secret name, UID or creation time changed (see secrets.diff)"
    diff "$EV/credfiles-A.txt" "$EV/credfiles-B.txt" > "$EV/credfiles.diff" 2>&1 \
      || fail "a generated credential file changed inode or mtime (see credfiles.diff)"
  fi
fi

helm history keep -n "$NS" > "$EV/helm-history.txt" 2>&1
echo "RESULT=$RESULT$REASONS" | tee "$EV/result.txt"
echo "evidence: $EV"
case "$RESULT" in
  PASS) exit 0 ;;
  FAIL) exit 1 ;;
  *) exit 3 ;;
esac
