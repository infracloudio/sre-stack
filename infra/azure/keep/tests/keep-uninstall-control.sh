#!/usr/bin/env bash
# keep-uninstall-control.sh: positive control for the uninstall hook (story #123, plan section 7).
#
# Proves that the watchers and the log capture see the pre-delete hook run, that the hook Job succeeds,
# and that the hook deletes keep-decoy-* and nothing else. Run this BEFORE keep-uninstall-nohooks.sh.
# Its PASS is the reliability evidence that the no-hooks run requires.
#
# Before any cluster change, the three scripts are checked against SHA256SUMS in this folder. A mismatch
# is INCONCLUSIVE. The hashes are written to script-hashes.txt, and the no-hooks run compares them.
#
# Usage, from the repository root, after Keep is installed in keep-uninstall-control (see the plan):
#   EXPECTED_CONTEXT=k3d-keep-uninstall-test bash infra/azure/keep/tests/keep-uninstall-control.sh
#
# Optional environment:
#   EVIDENCE_ROOT   folder that receives the evidence folder (default: TMPDIR, then /tmp)
#   KEEP_NS=1       keep the namespace after the run, for inspection
#
# Exit codes: 0 PASS, 1 FAIL, 2 REFUSED before any change, 3 INCONCLUSIVE.

set -u
set -C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" || { echo "REFUSED: cannot resolve the script folder" >&2; exit 2; }
if ! . "$SCRIPT_DIR/lib-uninstall-test.sh"; then
  echo "REFUSED: cannot load lib-uninstall-test.sh from $SCRIPT_DIR" >&2
  exit 2
fi

preflight keep-uninstall-control control
init_evidence
install_traps
register_required_checks control

# Script integrity first: no cluster change happens if the scripts differ from the manifest.
verify_script_hashes "$SCRIPT_DIR" || finish

require_keep_installed

create_decoys || finish
run_probe || finish
start_job_and_pod_watches || finish
start_health_monitor
before_snapshot || finish
start_hook_log_capture

run_uninstall ""
after_state
final_snapshot
stop_watchers_after_recording
finish_hook_log_capture

# ---- Evaluation: every input must exist; a missing input or a malformed row is INCONCLUSIVE ----

check_done control_job_watch
if require_evidence_file "$EV/jobwatch.txt" "job watch"; then
  if ! r="$(check_watch "$EV/jobwatch.txt" "$JOB_HEADER" job)"; then
    note_inc "job watch: $r (see jobwatch.txt)"
  else
    case "$(job_control_state "$EV/jobwatch.txt" "$HOOK_JOB")" in
      OK) ;;
      FAILED) note_fail "hook Job $HOOK_JOB reported Failed or FailureTarget" ;;
      *) note_inc "job watch lacks ADDED, then Complete 1/1, then DELETED for $HOOK_JOB (the watch may have missed it)" ;;
    esac
  fi
fi

check_done control_pod_watch
if require_evidence_file "$EV/podwatch.txt" "pod watch"; then
  if ! r="$(check_watch "$EV/podwatch.txt" "$POD_HEADER" pod)"; then
    note_inc "pod watch: $r (see podwatch.txt)"
  elif ! awk -v p="$HOOK_JOB-" '$1=="ADDED" && index($2, p)==1 {f=1} END{exit !f}' "$EV/podwatch.txt" 2>/dev/null; then
    note_inc "pod watch lacks an ADDED Pod for $HOOK_JOB (the watch may have missed the hook Pod)"
  fi
fi

check_done control_decoy_keep_absent
check_done control_decoy_sre_present
if require_evidence_file "$EV/after-secrets.txt" "after-uninstall Secret list"; then
  expect_absent "secret/keep-decoy-$SUFFIX" "$EV/after-secrets.txt" "R3 normal uninstall"
  expect_present "secret/sre-keep-decoy-$SUFFIX" "$EV/after-secrets.txt" "R3 normal uninstall"
fi

check_done control_keep_names_absent
if require_evidence_file "$EV/before-keep-names.txt" "before-uninstall keep-* name list"; then
  if [ -e "$EV/after-secrets.txt" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      expect_absent "$name" "$EV/after-secrets.txt" "R3 hook deletes every keep-* Secret"
    done < "$EV/before-keep-names.txt"
  fi
fi

check_done control_hook_log
if require_evidence_file "$EV/hook-logs.txt" "hook log"; then
  if [ ! -s "$EV/hook-logs.txt" ]; then
    note_inc "hook-logs.txt is empty; the deletion of the matching decoy cannot be shown"
  else
    if ! grep -Fq "secret \"keep-decoy-$SUFFIX\" deleted" "$EV/hook-logs.txt"; then
      note_inc "hook log does not show: secret \"keep-decoy-$SUFFIX\" deleted"
    fi
    if grep -Fq "sre-keep-decoy-$SUFFIX" "$EV/hook-logs.txt"; then
      note_fail "hook log names sre-keep-decoy-$SUFFIX"
    fi
    if grep -Fq "$DECOY_VALUE" "$EV/hook-logs.txt"; then
      note_fail "hook log prints a decoy value"
    fi
  fi
fi

check_done control_health
check_health
finish
