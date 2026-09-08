#!/usr/bin/env bash
# Scans changed files for credential patterns. Excludes the repo's documented
# allowlist (agent/hooks/secrets-allowlist.txt). Fails with findings listed.
#
# Modes:
#   check-secrets.sh <file>...            scan working-tree files
#   CHECK_STAGED=1 check-secrets.sh <f>.. scan the staged versions
#   check-secrets.sh                      scan staged changes (pre-commit)
#   check-secrets.sh --stdin <path>       scan proposed content for <path> from
#                                         stdin (agent pre-edit hooks; the file
#                                         may not exist yet)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOWLIST="$ROOT/agent/hooks/secrets-allowlist.txt"
CHECK_STAGED="${CHECK_STAGED:-0}"

PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'AccountKey=[A-Za-z0-9+/=]{20,}'
  '(password|passwd|secret)["'"'"']?\s*[:=]\s*["'"'"']?[A-Za-z0-9][A-Za-z0-9+/!@#$%^&*()_.=-]{4,}'
)

# Inline escape hatch for test fixtures: a line containing the marker
# `secret-check:allow` is not reported. Only permitted for fake fixture
# strings (agent/policies/security-policy.md); never for real credentials.
# New markers are ratcheted by check-ratchets.sh.
scan() {
  local label="$1" input="$2" pattern matches found=0
  for pattern in "${PATTERNS[@]}"; do
    matches=$(grep -nIE -- "$pattern" "$input" 2>/dev/null \
      | grep -v 'secret-check:allow' || true)
    if [ -n "$matches" ]; then
      echo "SECRET PATTERN in $label (pattern: $pattern):"
      echo "$matches" | sed 's/^/    /'
      found=1
    fi
  done
  return "$found"
}

if [ "${1:-}" = "--stdin" ]; then
  logical="${2:?usage: check-secrets.sh --stdin <repo-relative path>}"
  if [ -f "$ALLOWLIST" ] && grep -Fxq "$logical" "$ALLOWLIST"; then
    echo "check-secrets: $logical is allowlisted"
    exit 0
  fi
  content="$(mktemp)"
  cat > "$content"
  if scan "proposed content for $logical" "$content"; then
    echo "check-secrets: clean (proposed content for $logical)"
    rm -f "$content"
    exit 0
  fi
  rm -f "$content"
  exit 1
fi

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  mapfile -t FILES < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)
  CHECK_STAGED=1
fi

findings=0
for file in "${FILES[@]}"; do
  if [ "$CHECK_STAGED" -eq 1 ]; then
    git -C "$ROOT" cat-file -e ":$file" 2>/dev/null || continue
  else
    [ -f "$ROOT/$file" ] || continue
  fi
  if [ "$CHECK_STAGED" -eq 1 ] \
    && git -C "$ROOT" cat-file -e ":agent/hooks/secrets-allowlist.txt" 2>/dev/null; then
    if git -C "$ROOT" show :agent/hooks/secrets-allowlist.txt | grep -Fxq "$file"; then
      continue
    fi
  elif [ -f "$ALLOWLIST" ] && grep -Fxq "$file" "$ALLOWLIST"; then
    continue
  fi
  if [ "$CHECK_STAGED" -eq 1 ]; then
    staged="$(mktemp)"
    git -C "$ROOT" show ":$file" > "$staged" 2>/dev/null
    scan "$file" "$staged" || findings=1
    rm -f "$staged"
  else
    scan "$file" "$ROOT/$file" || findings=1
  fi
done

if [ "$findings" -eq 0 ]; then
  echo "check-secrets: clean (${#FILES[@]} files)"
fi
exit "$findings"
