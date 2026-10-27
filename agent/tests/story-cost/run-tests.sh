#!/usr/bin/env bash
# run-tests.sh — offline tests for agent/tools/story-cost.sh.
#
# Works in a throwaway git repo built from fixtures. It never reads the real
# ~/.claude or the real OpenCode database, and it never touches this repo.
# Prints one PASS/FAIL line per check and a total; exits non-zero on failure.
set -uo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_script="$_here/../../tools/story-cost.sh"
_fix="$_here/fixtures"
_sandbox="$(mktemp -d)"
_sandbox="$(cd "$_sandbox" && pwd -P)"
trap 'rm -rf "$_sandbox"' EXIT

total=0
failed=0

# One check. Usage: check <case-id> <ok:0/1> <detail>
check() {
  total=$((total + 1))
  if [ "$2" = "1" ]; then
    echo "  PASS $1 ${3:-}"
  else
    echo "  FAIL $1 ${3:-}"
    failed=$((failed + 1))
  fi
}

# Compare two strings.
expect() {
  if [ "$2" = "$3" ]; then
    check "$1" 1 "$4"
  else
    check "$1" 0 "$4 (expected '$3', got '$2')"
  fi
}

# --- the sandbox repo --------------------------------------------------------
repo="$_sandbox/repo"
mkdir -p "$repo/specs/006-demo"
printf -- '- [x] T001 something done\n' >"$repo/specs/006-demo/tasks.md"
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
git_at() { # git_at <epoch> <git args...>
  local when="$1"
  shift
  GIT_AUTHOR_DATE="$when +0000" GIT_COMMITTER_DATE="$when +0000" git -C "$repo" "$@" >/dev/null 2>&1
}
git -C "$repo" init -q -b main
git_at 1700000000 add -A
git_at 1700000000 commit -q -m first
git_at 1700001000 checkout -q -b 006-demo
git_at 1700002000 checkout -q main
git_at 1700003000 checkout -q 006-demo

cp -r "$_fix/claude" "$_sandbox/claude"
sed "s#@REPO@#$repo#g" "$_fix/opencode.sql" \
  | python3 -I -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.executescript(sys.stdin.read()); c.commit()' \
    "$_sandbox/opencode.db"

export STORY_COST_ROOT="$repo"
export STORY_COST_CLAUDE_DIR="$_sandbox/claude"
export STORY_COST_OPENCODE_DB="$_sandbox/opencode.db"
export STORY_COST_PRICES="$_fix/prices.tsv"

ledger="$repo/specs/006-demo/usage.tsv"
costmd="$repo/specs/006-demo/cost.md"

# field <harness> <session> <model> <column-name>: one value from the ledger
field() {
  awk -F'\t' -v h="$1" -v s="$2" -v m="$3" -v c="$4" '
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
    $1 == h && $2 == s && $3 == m { print $(col[c]) }' "$ledger"
}

# --- --check before any ledger exists -----------------------------------------
out="$(bash "$_script" --check 2>&1)"
rc=$?
expect check-warns "$out" "story-cost: warning: specs/006-demo/usage.tsv missing; run make story-cost" "--check warns when usage.tsv is missing"
expect check-exit-0 "$rc" 0 "--check always exits 0"

# --- first run ----------------------------------------------------------------
run1_out="$(bash "$_script" 2>"$_sandbox/run1.err")"
rc=$?
expect run1-exit "$rc" 0 "first run exits 0"
check ledger-written "$([ -f "$ledger" ] && [ -f "$costmd" ] && echo 1 || echo 0)" "usage.tsv and cost.md exist"

expect dedupe-input "$(field claude sess-a claude-opus-5-5 input)" 110 "duplicate lines counted once (100 + fast reply 10)"
expect dedupe-output "$(field claude sess-a claude-opus-5-5 output)" 60 "largest output of the duplicates kept (50 + 10)"
expect cache-1h-split "$(field claude sess-a claude-opus-5-5 cache_write_1h)" 400 "1-hour cache writes recorded"
expect price-cache-split "$(field claude sess-a claude-opus-5-5 usd)" 0.028400 "5m and 1h writes and fast reply priced to six places"
expect subagent-rollup "$(field claude sess-a claude-sonnet-5-5 output)" 300 "subagent reply lands under the parent session, own model row"
expect subagent-usd "$(field claude sess-a claude-sonnet-5-5 usd)" 0.001800 "subagent reply priced"
expect synthetic-skipped "$(field claude sess-a '<synthetic>' input)" "" "<synthetic> model is not recorded"
expect haiku-over100k "$(field claude sess-b claude-haiku-5-5 usd)" 1.000000 "Haiku reply over 100k tokens priced at the higher tier"
expect branch-split-kept "$(field claude sess-b claude-opus-5-5 usd)" 0.002100 "only the story-branch part of sess-b is recorded"
expect branch-split-input "$(field claude sess-b claude-opus-5-5 input)" 10 "main-branch reply not counted"

expect unknown-flag "$(field claude sess-b claude-fake-9 flag)" unpriced "unknown model is flagged unpriced"
expect unknown-usd-empty "$(field claude sess-b claude-fake-9 usd)" "" "unknown model has an empty usd, not 0"
check unknown-warns "$(grep -c 'claude-fake-9' "$_sandbox/run1.err")" "stderr names the unknown model"
check unknown-in-cost-md "$(grep -c 'not priced' "$costmd" | awk '{ print ($1 > 0) }')" "cost.md says not priced"

expect skipped-line "$(printf '%s\n' "$run1_out" | sed -n 1p)" "story-cost: skipped 4.1K tokens on 1 non-story branches" "dropped usage is only counted"

# OpenCode
expect oc-input "$(field opencode oc-s1 glm-5.3-flash input)" 1500 "input tokens mapped"
expect oc-output "$(field opencode oc-s1 glm-5.3-flash output)" 300 "output tokens mapped"
expect oc-reasoning "$(field opencode oc-s1 glm-5.3-flash reasoning)" 300 "reasoning kept in its own column"
expect oc-cache-read "$(field opencode oc-s1 glm-5.3-flash cache_read)" 2000 "cache read mapped"
expect oc-usd "$(field opencode oc-s1 glm-5.3-flash usd)" 0.252200 "stored cost used when non-zero; the zero-cost message is list-priced with reasoning billed once"
expect oc-source-cost "$(field opencode oc-s1 glm-5.3-flash source_cost)" 0.250000 "harness-reported cost kept"
expect oc-subagent-own-row "$(field opencode oc-s2 deepseek-flash usd)" 0.000200 "subagent session is its own row"
expect oc-session-totals-ignored "$(field opencode oc-s1 deepseek-flash input)" 10 "session total columns ignored; later branch window only"
expect oc-other-dir-ignored "$(awk -F'\t' '$2 == "oc-s3"' "$ledger" | wc -l | tr -d ' ')" 0 "sessions outside the repo ignored"
expect oc-branch-from-reflog "$(field opencode oc-s1 glm-5.3-flash branch)" 006-demo "branch decided by the reflog at message time"

# --- idempotent re-run ----------------------------------------------------------
cp "$ledger" "$_sandbox/ledger.1"
cp "$costmd" "$_sandbox/cost.1"
bash "$_script" >/dev/null 2>&1
check idempotent-ledger "$(cmp -s "$ledger" "$_sandbox/ledger.1" && echo 1 || echo 0)" "usage.tsv byte-identical on re-run"
check idempotent-cost-md "$(cmp -s "$costmd" "$_sandbox/cost.1" && echo 1 || echo 0)" "cost.md byte-identical on re-run"
out="$(bash "$_script" 2>/dev/null | grep -c 'no change')"
expect idempotent-message "$out" 1 "second run reports no change"

# --- check after the ledger exists ------------------------------------------------
expect check-quiet "$(bash "$_script" --check 2>&1)" "" "--check silent when usage.tsv exists"

# --- rows survive log deletion ------------------------------------------------------
rm "$_sandbox/claude/proj/sess-b.jsonl"
bash "$_script" >/dev/null 2>&1
expect survive-deletion "$(field claude sess-b claude-opus-5-5 usd)" 0.002100 "row stays after its log is deleted"

# --- shrink guard ----------------------------------------------------------------------
awk -F'\t' -v OFS='\t' '$1 == "claude" && $2 == "sess-a" && $3 == "claude-opus-5-5" { $6 = 99999 } { print }' "$ledger" >"$_sandbox/ledger.big"
cp "$_sandbox/ledger.big" "$ledger"
bash "$_script" >/dev/null 2>"$_sandbox/shrink.err"
expect shrink-kept "$(field claude sess-a claude-opus-5-5 output)" 99999 "stored row with more tokens is kept"
expect shrink-flag "$(field claude sess-a claude-opus-5-5 flag)" shrunk "stored row flagged shrunk"
check shrink-warns "$(grep -c 'shrunk' "$_sandbox/shrink.err")" "a warning is printed"

# --- missing OpenCode database ----------------------------------------------------------
out="$(STORY_COST_OPENCODE_DB="$_sandbox/none.db" bash "$_script" 2>&1)"
rc=$?
expect no-opencode-exit "$rc" 0 "missing OpenCode database exits 0"
check no-opencode-msg "$(printf '%s\n' "$out" | grep -c 'opencode: no database, skipped')" "prints the skipped line"

# --- --story with a missing folder --------------------------------------------------------
bash "$_script" --story does-not-exist >/dev/null 2>&1
expect story-missing "$?" 2 "--story with no folder exits 2"

# --- not a story branch --------------------------------------------------------------------
git_at 1700004000 checkout -q main
out="$(bash "$_script" 2>&1)"
rc=$?
expect off-branch-exit "$rc" 0 "non-story branch exits 0"
check off-branch-msg "$(printf '%s\n' "$out" | grep -c 'nothing written')" "says nothing was written"
expect off-branch-check "$(bash "$_script" --check 2>&1)" "story-cost: n/a (not a story branch)" "--check says n/a"

echo "story-cost tests: $total checks, $failed failed"
[ "$failed" -eq 0 ]
