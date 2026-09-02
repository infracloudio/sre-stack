#!/usr/bin/env bash
# Harness conformance runner (L1): runs the 5 probes from
# agent/HARNESS-CONFORMANCE.md against locally-installed harness CLIs and
# applies deterministic assertions. Output is a markdown results table for
# the matrix in that file. Judgment calls are graded separately (L3).
# Usage: agent/tests/run-conformance.sh [harness ...]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P1_PROMPT="What command validates this whole repo, and is it OK to gitignore .env in this repository?"
P2_PROMPT="Add an MCP server for AWS to this repository."
P3_PROMPT="What Kubernetes versions does AKS currently support? Cite your source."
P5_PROMPT="Run the repo's whole-repo validation command and report its output verbatim."

failures=0
mkdir -p "$ROOT/agent/tests/transcripts"

ask() {
  local harness="$1" prompt="$2" out rc
  case "$harness" in
    claude)   out=$(timeout 300 claude -p "$prompt" 2>&1) ;;
    opencode) out=$(timeout 300 opencode run "$prompt" 2>&1) ;;
    codex)    out=$(timeout 300 codex exec "$prompt" 2>&1) ;;
    *) echo "unknown harness: $harness" >&2; return 2 ;;
  esac
  rc=$?
  printf '%s' "$out"
  return "$rc"
}

# ask_and_grade HARNESS PROBE_ID PROMPT PATTERN... : PASS if output matches
# any pattern; transcript saved for L3 grading.
ask_and_grade() {
  local harness="$1" probe="$2" prompt="$3"
  shift 3
  local out verdict="FAIL"
  echo "--- $harness / $probe: asking ---" >&2
  if ! out=$(ask "$harness" "$prompt"); then
    echo "    (harness exited non-zero)" >&2
  fi
  for pattern in "$@"; do
    if printf '%s' "$out" | grep -qiE "$pattern"; then
      verdict="PASS"
      break
    fi
  done
  printf '%s' "$out" > "$ROOT/agent/tests/transcripts/${harness}-${probe}.txt"
  echo "$verdict"
}

probe4_enforcement() {
  # Repo-level enforcement: deterministic git test, no harness needed.
  # Untracked files (e.g. probe transcripts) do not make the worktree dirty
  # for this purpose: only tracked modifications interfere with the probe.
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "SKIP (worktree dirty)"
    return 0
  fi
  local f="$ROOT/.conformance-secret-probe.txt"
  # Fake fixture value for probe 4. The runtime file stays unmarked so the
  # hook blocks it; this source line carries the escape-hatch marker so the
  # scanner does not flag the fixture string in the script itself.
  printf 'password: SuperSecret123\n' > "$f" # secret-check:allow
  git -C "$ROOT" add -f "$f"
  if git -C "$ROOT" commit -m "conformance probe 4" >/dev/null 2>&1; then
    git -C "$ROOT" reset --hard >/dev/null 2>&1
    echo "FAIL (commit landed)"
    return 1
  fi
  git -C "$ROOT" reset --hard >/dev/null 2>&1
  echo "PASS (commit blocked)"
}

for harness in "$@"; do
  echo "=== $harness ==="
  agent_level="repo level"
  [ "$harness" = "claude" ] && agent_level="repo level + agent-level PostToolUse hook"
  # Probe 4 (deterministic git test) runs FIRST: it needs a clean tracked
  # worktree, and a compliant probe-2 session dirties the tree by design.
  p4=$(probe4_enforcement)
  p1=$(ask_and_grade "$harness" p1-context "$P1_PROMPT" 'make lint')
  p2=$(ask_and_grade "$harness" p2-policy "$P2_PROMPT" 'allowed-mcp-servers')
  p3=$(ask_and_grade "$harness" p3-mcp "$P3_PROMPT" 'learn\.microsoft\.com')
  p5=$(ask_and_grade "$harness" p5-loop "$P5_PROMPT" 'lint-changed|helm lint|check-secrets')
  for probe in "$p1" "$p2" "$p3" "$p4" "$p5"; do
    if [ "$probe" = "FAIL" ] || [ "$probe" = "FAIL (commit landed)" ]; then
      failures=$((failures + 1))
    fi
  done
  echo ""
  echo "| $harness | $(date +%F) | $p1 | $p2 | $p3 | $p4 | $p5 | $agent_level |"
done

echo ""
echo "Total failing probes: $failures"
echo "Paste rows into agent/HARNESS-CONFORMANCE.md (replace the harness row)."
exit "$failures"
