#!/usr/bin/env bash
# render-checks.sh: rendered-manifest checks for Keep 0.1.97 with infra/azure/chart-values/keep.yaml (story #123,
# task T018). Offline apart from the chart download; no cluster call; no Secret value is ever printed.
# Checks: SC-010 (rendered frontend wiring), SC-004 (every image tagged or digest-pinned, busybox and MySQL by digest),
# FR-002 (usage reporting off), FR-003 (the rendered cleanup Job uses the pinned image and is a pre-delete hook).
# Requires Helm v3.14.4 first on PATH: PATH="$HOME/.local/opt/helm-3.14.4:$PATH".
# Exit codes: 0 every check passes, 1 a check fails, 2 wrong Helm version.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
ROOT="$(cd "$DIR/../../../.." && pwd)" || exit 2
VALUES="$ROOT/infra/azure/chart-values/keep.yaml"

HELM_VERSION="$(helm version --short 2>/dev/null || true)"
case "$HELM_VERSION" in
  v3.14.4*) ;;
  *) echo "render-checks: needs Helm v3.14.4 on PATH (found: ${HELM_VERSION:-none})" >&2; exit 2 ;;
esac

W="$(mktemp -d "${TMPDIR:-/tmp}/render-checks.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
RENDER="$W/render.yaml"
helm template keep keep --repo https://keephq.github.io/helm-charts --version 0.1.97 -f "$VALUES" > "$RENDER" 2>"$W/err.txt" || {
  echo "render-checks: helm template failed:" >&2; cat "$W/err.txt" >&2; exit 1; }

PASSED=0
FAILED=0
check() { # NAME CONDITION(0 = pass) DETAIL
  if [ "$2" -eq 0 ]; then
    PASSED=$((PASSED + 1)); echo "pass   $1"
  else
    FAILED=$((FAILED + 1)); echo "FAIL   $1 ($3)"
  fi
}

# SC-010 (rendered half): the frontend reads sre-keep-ai-frontend and sre-keep-auth through envFrom, sets the two
# OpenAI settings, and has no NEXTAUTH_SECRET value.
grep -q -F 'name: sre-keep-ai-frontend' "$RENDER"; a=$?
grep -q -F 'name: sre-keep-auth' "$RENDER"; b=$?
check "SC-010 envFrom references sre-keep-ai-frontend and sre-keep-auth" $((a + b)) "missing secretRef"
grep -q -E 'value: "?https://api\.fireworks\.ai/inference/v1"?$' "$RENDER"; c=$?
grep -q -E 'value: "?accounts/fireworks/models/glm-5p3-flash"?$' "$RENDER"; d=$?
check "SC-010 OPENAI_BASE_URL and OPENAI_MODEL_NAME are set" $((c + d)) "value missing"
NA="$(grep -c -E '^\s+- name: NEXTAUTH_SECRET' "$RENDER")"
check "SC-010 no NEXTAUTH_SECRET literal in the render" "$([ "$NA" -eq 0 ] && echo 0 || echo 1)" "$NA entries"

# SC-004: every image reference in the render is tagged or digest-pinned, none is latest or untagged.
IMAGES="$W/images.txt"
sed -n 's/^[[:space:]]*-\{0,1\}[[:space:]]*image:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' "$RENDER" | sort -u > "$IMAGES"
BAD="$(grep -v -E '@sha256:[0-9a-f]{64}$|:[^:/@]+$' "$IMAGES" | grep -v -E ':latest$' || true)"
LATEST="$(grep -E ':latest$' "$IMAGES" || true)"
UNTAGGED="$(grep -E '^[^:@]+$' "$IMAGES" || true)"
check "SC-004 no latest and no untagged image in the render" \
  "$([ -z "$LATEST$UNTAGGED$BAD" ] && echo 0 || echo 1)" "latest: $LATEST untagged: $UNTAGGED other: $BAD"
grep -q -E '^busybox:1\.38\.0@sha256:[0-9a-f]{64}$' "$IMAGES"; e=$?
grep -q -E '^mysql:8\.4\.13@sha256:[0-9a-f]{64}$' "$IMAGES"; f=$?
check "SC-004 busybox and MySQL are pinned by digest" $((e + f)) "digest pins missing"

# FR-002: usage reporting off on backend and frontend, and the frontend's error reporting off.
PH="$(grep -c -E 'name: POSTHOG_DISABLED' "$RENDER")"
PHV="$(grep -A1 -E 'name: POSTHOG_DISABLED' "$RENDER" | grep -c -E 'value: "true"')"
SE="$(grep -A1 -E 'name: SENTRY_DISABLED' "$RENDER" | grep -c -E 'value: "true"')"
check "FR-002 POSTHOG_DISABLED is true on backend and frontend" "$([ "$PH" -eq 2 ] && [ "$PHV" -eq 2 ] && echo 0 || echo 1)" "entries $PH, true $PHV"
check "FR-002 SENTRY_DISABLED is true on the frontend" "$([ "$SE" -eq 1 ] && echo 0 || echo 1)" "true entries $SE"

# FR-003 (rendered half): the pre-delete cleanup Job uses the pinned alpine/k8s digest. It does not run during the
# documented uninstall because the command uses --no-hooks (the live no-hooks evidence covers that).
HOOK_BLOCK="$(awk '/^kind: Job$/{f=1} f&&/^---$/{f=0} f' "$RENDER")"
echo "$HOOK_BLOCK" | grep -q -F 'helm.sh/hook": pre-delete'; g=$?
echo "$HOOK_BLOCK" | grep -q -E 'image: "?alpine/k8s:1\.34\.11@sha256:[0-9a-f]{64}"?'; h=$?
check "FR-003 the rendered cleanup Job is the pre-delete hook with the pinned alpine/k8s digest" $((g + h)) "hook or image mismatch"

echo ""
echo "checks passed: $PASSED, checks failed: $FAILED"
if [ "$FAILED" -eq 0 ]; then exit 0; fi
exit 1
