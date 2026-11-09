#!/usr/bin/env bash
# keep-uninstall-nohooks.sh: the documented uninstall command (story #123, plan section 7):
#   helm uninstall keep -n <namespace> --no-hooks
#
# Proves that the uninstall succeeds, the release is removed, the pre-delete hook Job is never created,
# the decoy Secrets remain, and the watchers stayed healthy.
#
# Order of checks, all before any cluster change:
#   1. SHA-256 of the three scripts matches SHA256SUMS in this folder. A mismatch is INCONCLUSIVE.
#   2. CONTROL_EVIDENCE is a genuine positive-control PASS, run with the same script hashes.
# If either fails, this script stops with INCONCLUSIVE (exit 3). It creates no decoy Secrets and runs no
# Helm command in that case.
#
# Usage, from the repository root, after keep-uninstall-control.sh has PASSED on the same cluster:
#   EXPECTED_CONTEXT=k3d-keep-uninstall-test CONTROL_EVIDENCE=<control evidence folder> \
#     bash infra/azure/keep/tests/keep-uninstall-nohooks.sh
#
# The command runs with --wait and --timeout 600s added, so the state after uninstall is deterministic.
# Those flags do not change hook behaviour.
#
# Optional environment: EVIDENCE_ROOT, KEEP_NS=1 (same meaning as in keep-uninstall-control.sh).
#
# Exit codes: 0 PASS, 1 FAIL, 2 REFUSED before any change, 3 INCONCLUSIVE.

set -u
set -C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" || { echo "REFUSED: cannot resolve the script folder" >&2; exit 2; }
if ! . "$SCRIPT_DIR/lib-uninstall-test.sh"; then
  echo "REFUSED: cannot load lib-uninstall-test.sh from $SCRIPT_DIR" >&2
  exit 2
fi

preflight keep-uninstall-test nohooks
init_evidence
install_traps
register_required_checks nohooks

# Script integrity first. This also writes this run's script-hashes.txt, which the control must match.
verify_script_hashes "$SCRIPT_DIR" || finish

# Validate the positive control before anything else that could change the cluster.
if ! validate_control_evidence "${CONTROL_EVIDENCE:-}"; then
  finish
fi
printf '%s\n' "${CONTROL_EVIDENCE:-}" > "$EV/control-evidence-path.txt" || note_inc "cannot record control evidence path"
log "positive-control evidence accepted: ${CONTROL_EVIDENCE:-}"

require_keep_installed
require_server_version || finish

create_decoys || finish
run_probe || finish
start_job_and_pod_watches || finish
establish_watch_readiness || finish
start_health_monitor
before_snapshot || finish

run_uninstall "--no-hooks"
after_state
final_snapshot
stop_watchers_after_recording

# ---- Evaluation: evaluate_nohooks (lib-uninstall-test.sh) reads this run's evidence folder. ----
evaluate_nohooks "$EV"
finish
