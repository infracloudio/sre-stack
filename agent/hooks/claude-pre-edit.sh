#!/usr/bin/env bash
# Claude Code adapter: PreToolUse hook for Write|Edit. Reads the hook JSON
# from stdin and denies the edit (exit 2, reason on stderr, which the model
# sees) when:
#   - this clone has no pre-commit hook enabled (make hooks),
#   - the target is a protected path (agent/hooks/protected-paths.txt),
#   - the proposed content contains a credential pattern.
# Kept thin on purpose — the substance lives in agent/hooks/.
set -uo pipefail
exec 1>&2

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "pre-edit hook: jq is required for the repo checks (make install). Edit refused."
  exit 2
fi

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<< "$input")"
[ -n "$file_path" ] || exit 0
case "$file_path" in
  "$ROOT"/*) ;;
  *) exit 0 ;;   # outside this repo (scratch dirs): not ours to police
esac
rel="${file_path#"$ROOT"/}"

if ! bash "$ROOT/agent/hooks/check-hooks-enabled.sh"; then
  echo "pre-edit hook: edit refused until pre-commit hooks are enabled in this clone."
  exit 2
fi

if ! bash "$ROOT/agent/hooks/check-protected-paths.sh" "$rel"; then
  echo "pre-edit hook: edit refused. Ask a human to make this change; they can run the session with PROTECTED_OVERRIDE=1."
  exit 2
fi

content="$(jq -r '.tool_input.content // .tool_input.new_string // empty' <<< "$input")"
if [ -n "$content" ] \
  && ! printf '%s\n' "$content" | bash "$ROOT/agent/hooks/check-secrets.sh" --stdin "$rel"; then
  echo "pre-edit hook: edit refused. Remove the credential; secrets belong in .env or a secret store (agent/policies/security-policy.md)."
  exit 2
fi
exit 0
