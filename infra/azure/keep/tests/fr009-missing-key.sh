#!/usr/bin/env bash
# fr009-missing-key.sh: offline test of setup-keep.sh's FR-009 behaviour (story #123, task T017). No cluster call:
# kubectl and helm are shims placed first on PATH, and every shim call is logged. Temp folders and dummy values only.
# It never reads or creates anything under ~/.secrets/keep.
#
# Cases:
#   A  missing key                              (T003; FR-009)
#   B  empty key counts as missing              (T003; edge case "The AI key file exists but is empty.")
#   C  cluster unreachable, nothing generated   (T005; edge case "The cluster is stopped or cannot be reached.")
#   D  key missing in chain mode skips, exit 0  (FR-009 skip path; the setup-aks wiring is T013)
#   E  folder missing names the key path        (FR-009)
#   F  home folder refused by the lexical guard (no filesystem access)
#   G  KEEP_SECRETS_DIR unset                   (configuration error)
#   H  /tmp refused by the lexical guard        (no filesystem access)
#   I  install fails: non-zero exit, no success (edge case "A Keep part cannot start"; T011)
#   J  kubectl error other than NotFound: stop before helm (T009)
#   K  key empty after newline strip: stop before any Secret (T009)
#   L  leading ~/ expands to HOME (temp HOME); M bare ~ and N literal $HOME refused; O chain mode with unset folder skips
#   P  key mode not 600: stop with the chmod 600 message before any call, also in chain mode (mode check)
#   Every fixture key file is set to mode 600 unless the case tests the mode itself.
#
# Exit 0 when every case behaves as expected, 1 otherwise. There are no skipped cases.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
SCRIPT="$DIR/../setup-keep.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/fr009-test.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

SHIM="$W/shim"
mkdir -p "$SHIM"
# shellcheck disable=SC2016 # the single quotes keep $1 and $* for the shim script, which is written to disk
printf '#!/bin/sh\nif [ "$1" = version ]; then echo v3.14.4+shim; exit 0; fi\necho "helm $*" >> "%s/calls.log"\nexit 99\n' "$SHIM" > "$SHIM/helm"
printf '#!/bin/sh\necho "kubectl $*" >> "%s/calls.log"\nexit 1\n' "$SHIM" > "$SHIM/kubectl"
chmod +x "$SHIM/helm" "$SHIM/kubectl"

PASSED=0
FAILED=0
SKIPPED=0

verdict() { # NAME OK(0 or 1) DETAIL
  if [ "$2" -eq 0 ]; then
    PASSED=$((PASSED + 1))
    echo "pass   $1"
  else
    FAILED=$((FAILED + 1))
    echo "FAIL   $1 ($3)"
  fi
}

run_case() { # NAME WANT_EXIT WANT_TEXT WANT_CALL [env assignments or -u VAR]
  local name="$1" want_exit="$2" want_text="$3" want_call="$4" out rc bad=0 why=""
  shift 4
  rm -f "$SHIM/calls.log"
  out="$(env "$@" PATH="$SHIM:$PATH" bash "$SCRIPT" 2>&1)"
  rc=$?
  if [ "$rc" -ne "$want_exit" ]; then bad=1; why="exit $rc, want $want_exit"; fi
  if [ -n "$want_text" ] && ! printf '%s\n' "$out" | grep -q -F "$want_text"; then
    bad=1; why="$why; text not found: $want_text"
  fi
  if [ -z "$want_call" ]; then
    if [ -s "$SHIM/calls.log" ]; then bad=1; why="$why; unexpected shim call: $(cat "$SHIM/calls.log")"; fi
  else
    if ! grep -q -F "$want_call" "$SHIM/calls.log" 2>/dev/null; then
      bad=1; why="$why; expected shim call not logged: $want_call"
    fi
  fi
  verdict "$name" "$bad" "$why"
}

D1="$W/a"; mkdir -p "$D1"
run_case "A (T003) missing key: exit 1, names the file, no kubectl or helm call" 1 \
  "AI key file missing or empty: $D1/fireworks.key" "" KEEP_SECRETS_DIR="$D1"

D2="$W/b"; mkdir -p "$D2"; : > "$D2/fireworks.key"
run_case "B (T003) empty key counts as missing: exit 1, no call" 1 \
  "AI key file missing or empty: $D2/fireworks.key" "" KEEP_SECRETS_DIR="$D2"

D3="$W/c"; mkdir -p "$D3"; echo "dummy-value-not-a-credential" > "$D3/fireworks.key"; chmod 600 "$D3/fireworks.key"
run_case "C (T005) cluster unreachable: exit 1, one read-only kubectl call" 1 \
  "cannot be reached" "kubectl get --raw /version" KEEP_SECRETS_DIR="$D3"
if [ ! -e "$D3/db-password" ] && [ ! -e "$D3/nextauth-secret" ]; then
  verdict "C (T005) cluster unreachable: no secret file created" 0 ""
else
  verdict "C (T005) cluster unreachable: no secret file created" 1 "a secret file was created"
fi

D4="$W/d"
run_case "D (FR-009 chain) key missing with KEEP_SKIP_IF_NO_KEY=1: exit 0 with skip message, no call" 0 \
  "skipped, AI key file missing or empty: $D4/fireworks.key" "" KEEP_SECRETS_DIR="$D4" KEEP_SKIP_IF_NO_KEY=1

D5="$W/e"
run_case "E (FR-009) folder missing names the key path: exit 1, no call" 1 \
  "AI key file missing or empty: $D5/fireworks.key" "" KEEP_SECRETS_DIR="$D5"

run_case "F home folder refused by the lexical guard: exit 2, no call" 2 \
  "refusing KEEP_SECRETS_DIR" "" KEEP_SECRETS_DIR="$HOME/"

run_case "G KEEP_SECRETS_DIR unset: exit 2, no call" 2 \
  "KEEP_SECRETS_DIR is not set" "" -u KEEP_SECRETS_DIR

run_case "H /tmp refused by the lexical guard: exit 2, no call" 2 \
  "refusing KEEP_SECRETS_DIR" "" KEEP_SECRETS_DIR=/tmp

# I (T011, edge case "A Keep part cannot start"): the install fails. The script must exit non-zero, must not print the
# success line, and must have reached helm. Its shims accept the cluster and Secret calls, and fail the helm install.
SHIM2="$W/shim2"
mkdir -p "$SHIM2"
# shellcheck disable=SC2016 # the single quotes keep $1 and $* for the shim script, which is written to disk
printf '#!/bin/sh\nif [ "$1" = version ]; then echo v3.14.4+shim; exit 0; fi\necho "helm $*" >> "%s/calls.log"\necho "Error: timed out waiting for the condition" >&2\nexit 1\n' "$SHIM2" > "$SHIM2/helm"
# shellcheck disable=SC2016 # the single quotes keep $* for the shim script, which is written to disk
printf '#!/bin/sh\necho "kubectl $*" >> "%s/calls.log"\ncase "$*" in\n  "get --raw /version"|"get namespace"*) exit 0 ;;\n  "get secret"*) echo "Error from server (NotFound): secrets not found" >&2; exit 1 ;;\n  *) exit 0 ;;\nesac\n' "$SHIM2" > "$SHIM2/kubectl"
chmod +x "$SHIM2/helm" "$SHIM2/kubectl"
D9="$W/i"; mkdir -p "$D9"; echo "dummy-value-not-a-credential" > "$D9/fireworks.key"; chmod 600 "$D9/fireworks.key"
rm -f "$SHIM2/calls.log"
out="$(env KEEP_SECRETS_DIR="$D9" KEEP_NAMESPACE=keep-test-shim PATH="$SHIM2:$PATH" bash "$SCRIPT" 2>&1)"
rc=$?
bad=0; why=""
if [ "$rc" -eq 0 ]; then bad=1; why="exit 0, want non-zero"; fi
if printf '%s\n' "$out" | grep -q -F "setup-keep: Keep installed"; then bad=1; why="$why; success line printed"; fi
if ! grep -q -F "helm upgrade --install" "$SHIM2/calls.log" 2>/dev/null; then bad=1; why="$why; helm install not reached"; fi
verdict "I (T011) install fails: non-zero exit, no success line, helm reached" "$bad" "$why"

# J (T009): a kubectl error other than NotFound stops the script before helm, and is reported as such.
SHIM3="$W/shim3"
mkdir -p "$SHIM3"
# shellcheck disable=SC2016 # the single quotes keep $1 and $* for the shim script, which is written to disk
printf '#!/bin/sh\nif [ "$1" = version ]; then echo v3.14.4+shim; exit 0; fi\necho "helm $*" >> "%s/calls.log"\nexit 99\n' "$SHIM3" > "$SHIM3/helm"
# shellcheck disable=SC2016 # the single quotes keep $* for the shim script, which is written to disk
printf '#!/bin/sh\necho "kubectl $*" >> "%s/calls.log"\ncase "$*" in\n  "get --raw /version"|"get namespace"*) exit 0 ;;\n  "get secret"*) echo "Unable to connect to the server: dial tcp" >&2; exit 1 ;;\n  *) exit 0 ;;\nesac\n' "$SHIM3" > "$SHIM3/kubectl"
chmod +x "$SHIM3/helm" "$SHIM3/kubectl"
D10="$W/j"; mkdir -p "$D10"; echo "dummy-value-not-a-credential" > "$D10/fireworks.key"; chmod 600 "$D10/fireworks.key"
rm -f "$SHIM3/calls.log"
out="$(env KEEP_SECRETS_DIR="$D10" KEEP_NAMESPACE=keep-test-shim PATH="$SHIM3:$PATH" bash "$SCRIPT" 2>&1)"
rc=$?
bad=0; why=""
if [ "$rc" -eq 0 ]; then bad=1; why="exit 0, want non-zero"; fi
if ! printf '%s\n' "$out" | grep -q -F "not NotFound"; then bad=1; why="$why; error not reported as a non-NotFound error"; fi
if grep -q -F "helm upgrade" "$SHIM3/calls.log" 2>/dev/null; then bad=1; why="$why; helm reached after a kubectl error"; fi
verdict "J (T009) kubectl error other than NotFound: stop before helm, reported as such" "$bad" "$why"

# K (T009): a key file that holds only a newline passes the key check, but is empty once the newline is stripped.
# The script must stop before any Secret or helm call. It uses the case I shims for the cluster and helm checks.
D11="$W/k"; mkdir -p "$D11"; printf '\n' > "$D11/fireworks.key"; chmod 600 "$D11/fireworks.key"
rm -f "$SHIM2/calls.log"
out="$(env KEEP_SECRETS_DIR="$D11" KEEP_NAMESPACE=keep-test-shim PATH="$SHIM2:$PATH" bash "$SCRIPT" 2>&1)"
rc=$?
bad=0; why=""
if [ "$rc" -eq 0 ]; then bad=1; why="exit 0, want non-zero"; fi
if ! printf '%s\n' "$out" | grep -q -F "is empty after preparation"; then bad=1; why="$why; empty-after-preparation message missing"; fi
if printf '%s\n' "$out" | grep -q -F "created Secret"; then bad=1; why="$why; a Secret was created"; fi
if grep -q -F "helm upgrade" "$SHIM2/calls.log" 2>/dev/null; then bad=1; why="$why; helm reached"; fi
verdict "K (T009) key empty after newline strip: stop before any Secret or helm call" "$bad" "$why"

# L (T014 form): a leading ~/ expands to $HOME, checked with a temp HOME so the real home folder is never used.
mkdir -p "$W/home"
run_case "L (T014) leading ~/ expands to HOME: names the expanded key path" 1 \
  "AI key file missing or empty: $W/home/keys/fireworks.key" "" "HOME=$W/home" "KEEP_SECRETS_DIR=~/keys"

# M: a bare ~ is not expanded and is refused by the lexical guard.
run_case "M bare ~ refused by the lexical guard: exit 2, no call" 2 \
  "refusing KEEP_SECRETS_DIR" "" "KEEP_SECRETS_DIR=~"

# N: a literal $HOME is not expanded and is refused by the lexical guard.
# shellcheck disable=SC2016 # the single quotes keep the literal text $HOME, which is what the case must pass
run_case "N literal \$HOME refused by the lexical guard: exit 2, no call" 2 \
  "refusing KEEP_SECRETS_DIR" "" 'KEEP_SECRETS_DIR=$HOME'

# O (chain mode): an unset KEEP_SECRETS_DIR skips Keep with a message that names the variable; stand-alone it exits 2.
run_case "O chain mode, KEEP_SECRETS_DIR unset: exit 0, skip message names the variable, no call" 0 \
  "skipped, KEEP_SECRETS_DIR is not set" "" -u KEEP_SECRETS_DIR KEEP_SKIP_IF_NO_KEY=1

# P (mode check): a key file that is not mode 600 stops before any kubectl or helm call, names the chmod 600 fix, and
# leaves the file's mode unchanged. The fixture is mode 644, the mode the default umask gives.
D12="$W/p"; mkdir -p "$D12"; echo "dummy-value-not-a-credential" > "$D12/fireworks.key"; chmod 644 "$D12/fireworks.key"
run_case "P (mode check) key mode 644: exit 1, names chmod 600, no kubectl or helm call" 1 \
  "chmod 600 $D12/fireworks.key" "" KEEP_SECRETS_DIR="$D12"
mode_after="$(stat -f '%Lp' "$D12/fireworks.key" 2>/dev/null || stat -c '%a' "$D12/fireworks.key")"
if [ "$mode_after" = "644" ]; then
  verdict "P (mode check) script left the key file mode unchanged (644)" 0 ""
else
  verdict "P (mode check) script left the key file mode unchanged (644)" 1 "mode is now $mode_after"
fi

# P2 (mode check, chain mode): the same mode problem stops with exit 1. It must not skip, because a skip would hide it.
D13="$W/q"; mkdir -p "$D13"; echo "dummy-value-not-a-credential" > "$D13/fireworks.key"; chmod 644 "$D13/fireworks.key"
run_case "P2 (mode check) key mode 644 in chain mode: exit 1, not a skip, names chmod 600" 1 \
  "chmod 600 $D13/fireworks.key" "" KEEP_SECRETS_DIR="$D13" KEEP_SKIP_IF_NO_KEY=1

echo ""
echo "cases passed: $PASSED, cases failed: $FAILED, skipped: $SKIPPED"
if [ "$FAILED" -eq 0 ]; then exit 0; fi
exit 1
