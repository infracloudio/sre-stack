#!/usr/bin/env bash
# Lints changed files: shellcheck for .sh, yamllint for .yaml/.yml, helm lint
# for any chart whose files changed. Tools are skipped with a warning outside
# CI; set STRICT=1 to fail when a tool is missing (used in CI).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STRICT="${STRICT:-0}"
ALLOWLIST="$ROOT/agent/hooks/shellcheck-allowlist.txt"

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  mapfile -t FILES < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)
fi

fail=0
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    if [ "$STRICT" -eq 1 ]; then
      echo "lint: STRICT mode: required tool '$1' is missing" >&2
      exit 2
    fi
    echo "lint: warning: '$1' not installed, skipping its checks"
    return 1
  fi
  return 0
}

shell_files=()
yaml_files=()
chart_dirs=()
for file in "${FILES[@]}"; do
  # .specify/ is generated and refreshed by the Specify CLI (Spec Kit);
  # upstream owns its scripts and workflow YAML, so repo lint skips them
  # (same reasoning as the loom-generated adapters, which loom checks).
  case "$file" in
    .specify/*) continue ;;
  esac
  case "$file" in
    *.sh) shell_files+=("$file") ;;
    *.yaml|*.yml) yaml_files+=("$file") ;;
  esac
  case "$file" in
    */Chart.yaml) chart_dirs+=("$(dirname "$file")") ;;
  esac
done

if [ "${#shell_files[@]}" -gt 0 ] && need shellcheck; then
  for file in "${shell_files[@]}"; do
    # Ratchet mirrors .yamllint.yaml: allowlisted legacy files run at error
    # severity only; everything else runs at warning severity. The allowlist
    # only shrinks. Never add a file to it.
    if [ -f "$ALLOWLIST" ] && grep -Fxq "$file" "$ALLOWLIST"; then
      severity=error
    else
      severity=warning
    fi
    if ! shellcheck -S "$severity" "$ROOT/$file"; then
      echo "lint: shellcheck failed ($severity): $file"
      fail=1
    fi
  done
fi

if [ "${#yaml_files[@]}" -gt 0 ] && need yamllint; then
  if ! yamllint -c "$ROOT/.yamllint.yaml" "${yaml_files[@]}"; then
    echo "lint: yamllint failed"
    fail=1
  fi
fi

if [ "${#chart_dirs[@]}" -gt 0 ] && need helm; then
  for dir in $(printf '%s\n' "${chart_dirs[@]}" | sort -u); do
    if ! helm lint "$ROOT/$dir" --strict; then
      echo "lint: helm lint failed: $dir"
      fail=1
    fi
  done
fi

if [ "$fail" -eq 0 ]; then
  echo "lint-changed: clean (sh:${#shell_files[@]} yaml:${#yaml_files[@]} charts:${#chart_dirs[@]})"
fi
exit "$fail"
