#!/usr/bin/env bash
# Scans changed files for credential patterns. Excludes the repo's documented
# allowlist (agent/hooks/secrets-allowlist.txt). Fails with findings listed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOWLIST="$ROOT/agent/hooks/secrets-allowlist.txt"

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  mapfile -t FILES < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)
fi

PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'AccountKey=[A-Za-z0-9+/=]{20,}'
  '(password|passwd|secret)["'"'"']?\s*[:=]\s*["'"'"']?[A-Za-z0-9][A-Za-z0-9+/!@#$%^&*()_.=-]{4,}'
)

findings=0
for file in "${FILES[@]}"; do
  [ -f "$ROOT/$file" ] || continue
  if [ -f "$ALLOWLIST" ] && grep -Fxq "$file" "$ALLOWLIST"; then
    continue
  fi
  for pattern in "${PATTERNS[@]}"; do
    # Inline escape hatch for test fixtures: a line containing the marker
    # below is not reported. Only permitted for fake fixture strings
    # (agent/policies/security-policy.md); never for real credentials.
    matches=$(grep -nIE "$pattern" "$ROOT/$file" 2>/dev/null \
      | grep -v 'secret-check:allow' || true)
    if [ -n "$matches" ]; then
      echo "SECRET PATTERN in $file (pattern: $pattern):"
      echo "$matches" | sed 's/^/    /'
      findings=1
    fi
  done
done

if [ "$findings" -eq 0 ]; then
  echo "check-secrets: clean (${#FILES[@]} files)"
fi
exit "$findings"
