#!/usr/bin/env bash
# Claude Code adapter: PostToolUse hook for Write|Edit. Runs the lint and
# ratchet checks on the file just written and, on findings, exits 2 so the
# output reaches the model as feedback to fix before moving on. Blocking and
# secrets happen earlier, in claude-pre-edit.sh (PreToolUse).
set -uo pipefail
exec 1>&2

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
file_path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$file_path" ] || exit 0
[ -f "$file_path" ] || exit 0
case "$file_path" in "$ROOT"/*) ;; *) exit 0 ;; esac
rel="${file_path#"$ROOT"/}"

status=0
bash "$ROOT/agent/hooks/check-ratchets.sh" "$rel" || status=1
bash "$ROOT/agent/hooks/lint-changed.sh" "$rel" || status=1
if [ "$status" -ne 0 ]; then
  echo "post-edit hook: fix the findings above before continuing (make lint must pass)."
  exit 2
fi
exit 0
