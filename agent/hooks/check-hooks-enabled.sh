#!/usr/bin/env bash
# Fails unless this clone routes git hooks through .githooks/ (`make hooks`,
# also done by `make install`). Pre-commit is the wall every harness and every
# human hits; a clone without it has no wall. Skipped in CI, where
# .github/workflows/ci.yml runs the same checks.
set -uo pipefail

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "check-hooks-enabled: skipped in CI"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "check-hooks-enabled: not a git checkout — skipped"
  exit 0
fi

hooks_path="$(git -C "$ROOT" config --get core.hooksPath || true)"
if [ "$hooks_path" != ".githooks" ]; then
  echo "check-hooks-enabled: pre-commit hooks are NOT enabled in this clone."
  echo "  Run: make hooks   (make install does this as well)"
  exit 1
fi
echo "check-hooks-enabled: .githooks active"
