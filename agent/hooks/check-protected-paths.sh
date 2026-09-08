#!/usr/bin/env bash
# Blocks changes to protected paths. Patterns live in
# agent/hooks/protected-paths.txt (grep -E regexes, one per line; # comments).
#
# Files checked: arguments if given; else the diff against RATCHET_BASE if
# set (CI); else the staged files (pre-commit). Agents hit this from the
# PreToolUse hook before the edit happens. A human making a reviewed change
# sets PROTECTED_OVERRIDE=1 (CI sets it when the PR carries
# gate:plan-approved, i.e. someone other than the author approved it).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$ROOT/agent/hooks/protected-paths.txt"
CHECK_STAGED="${CHECK_STAGED:-0}"
RATCHET_BASE="${RATCHET_BASE:-}"
OVERRIDE="${PROTECTED_OVERRIDE:-}"

if [ $# -gt 0 ]; then
  FILES=("$@")
elif [ -n "$RATCHET_BASE" ]; then
  mapfile -t FILES < <(
    git -C "$ROOT" diff --name-only --diff-filter=ACMDR "$RATCHET_BASE"...HEAD
  )
else
  mapfile -t FILES < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACMDR)
  CHECK_STAGED=1
fi

if [ "$CHECK_STAGED" -eq 1 ] \
  && git -C "$ROOT" cat-file -e ":agent/hooks/protected-paths.txt" 2>/dev/null; then
  mapfile -t PATTERNS < <(
    git -C "$ROOT" show :agent/hooks/protected-paths.txt \
      | grep -vE '^\s*(#|$)' || true
  )
else
  mapfile -t PATTERNS < <(grep -vE '^\s*(#|$)' "$CONFIG" 2>/dev/null || true)
fi

if [ "${#PATTERNS[@]}" -eq 0 ]; then
  echo "check-protected-paths: no protected paths configured"
  exit 0
fi

findings=0
for file in "${FILES[@]}"; do
  for pattern in "${PATTERNS[@]}"; do
    if echo "$file" | grep -qE "$pattern"; then
      echo "PROTECTED PATH: $file matches /$pattern/"
      findings=1
      break
    fi
  done
done

if [ "$findings" -eq 0 ]; then
  echo "check-protected-paths: clean (${#FILES[@]} files)"
  exit 0
fi

case "$OVERRIDE" in
  1|true|TRUE|yes)
    echo "check-protected-paths: PROTECTED_OVERRIDE set — accepted as a reviewed change"
    exit 0
    ;;
esac
echo "  Guardrail and generated paths change by a human-reviewed PR, never as a"
echo "  side effect. A human commits them with PROTECTED_OVERRIDE=1 and says why"
echo "  in the PR (see agent/hooks/protected-paths.txt)."
exit 1
