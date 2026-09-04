#!/usr/bin/env bash
# Enforces the legacy lint allowlists as shrinking ratchets. A changed legacy
# file must be fixed and removed from its list; new list entries are forbidden.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RATCHET_BASE="${RATCHET_BASE:-}"
CHECK_STAGED="${CHECK_STAGED:-0}"

if [ $# -gt 0 ]; then
  FILES=("$@")
elif [ -n "$RATCHET_BASE" ]; then
  mapfile -t FILES < <(
    git -C "$ROOT" diff --name-only --diff-filter=ACM "$RATCHET_BASE"...HEAD
  )
else
  mapfile -t FILES < <(
    git -C "$ROOT" diff --cached --name-only --diff-filter=ACM
  )
  CHECK_STAGED=1
fi

config_has_line() {
  local config="$1" line="$2"
  if [ "$CHECK_STAGED" -eq 1 ] && git -C "$ROOT" cat-file -e ":$config" 2>/dev/null; then
    git -C "$ROOT" show ":$config" | grep -Fxq "$line"
  else
    grep -Fxq "$line" "$ROOT/$config"
  fi
}

fail=0
for file in "${FILES[@]}"; do
  if config_has_line .yamllint.yaml "  $file"; then
    echo "RATCHET: $file changed but remains in .yamllint.yaml"
    echo "  Fix its yamllint findings and remove the ignore entry."
    fail=1
  fi
  if config_has_line agent/hooks/shellcheck-allowlist.txt "$file"; then
    echo "RATCHET: $file changed but remains in agent/hooks/shellcheck-allowlist.txt"
    echo "  Fix its shellcheck warnings and remove the allowlist entry."
    fail=1
  fi
done

if [ -n "$RATCHET_BASE" ]; then
  DIFF_ARGS=("$RATCHET_BASE...HEAD")
elif [ "$CHECK_STAGED" -eq 1 ]; then
  DIFF_ARGS=(--cached HEAD)
else
  DIFF_ARGS=(HEAD)
fi

check_added_entries() {
  local config="$1" pattern="$2" added
  local base_ref="${RATCHET_BASE:-HEAD}"

  # The bootstrap commit establishes the initial debt baseline. Once the file
  # exists at the comparison point, every later change must only shrink it.
  if ! git -C "$ROOT" cat-file -e "$base_ref:$config" 2>/dev/null; then
    return 0
  fi

  added="$(git -C "$ROOT" diff --unified=0 "${DIFF_ARGS[@]}" -- "$config" \
    | sed -nE "$pattern" || true)"
  if [ -n "$added" ]; then
    echo "RATCHET: new entries were added to $config:"
    printf '  %s\n' "$added"
    fail=1
  fi
}

check_added_entries .yamllint.yaml 's/^\+  ([^#].*\.ya?ml)$/\1/p'
check_added_entries agent/hooks/shellcheck-allowlist.txt 's/^\+([^+#][^ ]*\.sh)$/\1/p'

if [ "$fail" -eq 0 ]; then
  echo "check-ratchets: clean (${#FILES[@]} changed files)"
fi
exit "$fail"
