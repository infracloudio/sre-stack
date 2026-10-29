#!/usr/bin/env bash
# Config-aware story-cost dispatch; use existing PyYAML, never install packages.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  yaml_python="$(command -v python3)"
else
  specify_bin="$(command -v specify || true)"
  shebang=''
  if [ -n "$specify_bin" ]; then
    IFS= read -r shebang < "$specify_bin" || true
  fi
  yaml_python="${shebang#\#!}"
  if [ "$yaml_python" = "$shebang" ] || ! "$yaml_python" -c 'import yaml' >/dev/null 2>&1; then
    echo 'spec-kit: PyYAML unavailable in system Python and Specify console-script runtime; mandatory hooks not checked' >&2
    exit 2
  fi
fi
exec "$yaml_python" "$root/agent/spec-kit/posthook.py" "${1:-}"
