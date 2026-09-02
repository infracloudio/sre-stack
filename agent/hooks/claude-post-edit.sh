#!/usr/bin/env bash
# Claude Code adapter: PostToolUse hook. Reads the hook JSON from stdin,
# extracts the edited file path, and runs the repo checks on it.
# Kept thin on purpose — the substance lives in agent/hooks/.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
file_path=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file_path" ] || exit 0
[ -f "$file_path" ] || exit 0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rel="${file_path#"$ROOT"/}"

bash "$ROOT/agent/hooks/check-secrets.sh" "$rel"
bash "$ROOT/agent/hooks/lint-changed.sh" "$rel"
exit 0
