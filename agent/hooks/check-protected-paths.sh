#!/usr/bin/env bash
# Blocks changes to protected paths. Patterns live in
# agent/hooks/protected-paths.txt (grep -E regexes, one per line; # comments).
# An empty pattern list means nothing is protected yet: the hook passes.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$ROOT/agent/hooks/protected-paths.txt"

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  mapfile -t FILES < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)
fi

mapfile -t PATTERNS < <(grep -vE '^\s*(#|$)' "$CONFIG" 2>/dev/null || true)

if [ "${#PATTERNS[@]}" -eq 0 ]; then
  echo "check-protected-paths: no protected paths configured"
  exit 0
fi

findings=0
for file in "${FILES[@]}"; do
  for pattern in "${PATTERNS[@]}"; do
    if echo "$file" | grep -qE "$pattern"; then
      echo "PROTECTED PATH: $file matches /$pattern/"
      echo "  Editing this path requires a separate reviewed change"
      echo "  (see agent/hooks/protected-paths.txt)."
      findings=1
    fi
  done
done

if [ "$findings" -eq 0 ]; then
  echo "check-protected-paths: clean (${#FILES[@]} files)"
fi
exit "$findings"
