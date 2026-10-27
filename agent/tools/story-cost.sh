#!/usr/bin/env bash
# story-cost.sh — record the tokens and dollars a Spec Kit story used.
#
# Reads Claude Code transcripts and the OpenCode database, prices each reply
# from agent/tools/model-prices.tsv, and writes specs/<story>/usage.tsv (one
# row per harness + session + model + branch) and specs/<story>/cost.md.
# See AD-014 in docs/architectural-decisions.md.
#
# Usage:
#   story-cost.sh                 story = current branch (needs specs/<branch>/)
#   story-cost.sh --story <name>  story = specs/<name>/ (exit 2 if missing)
#   story-cost.sh --check         lint warning only, always exit 0
#
# Test overrides: STORY_COST_ROOT, STORY_COST_CLAUDE_DIR (a projects folder),
# STORY_COST_OPENCODE_DB, STORY_COST_PRICES.
#
# Adding a harness: write one read_<name> function that prints one row per
# model reply in the 15-column format described above read_claude, and add
# it to the "readers" block in main.
#
# OpenCode facts (checked against OpenCode v2.1.4, 2026-10-27, AD-014):
#   - tokens.input does NOT include cache reads or writes.
#   - tokens.reasoning is billed IN ADDITION to tokens.output, at the output
#     rate (the stored cost matched this for 100% of deepseek-flash replies
#     that had reasoning), so OPENCODE_REASONING_SEPARATE=1.
set -uo pipefail

ROOT="${STORY_COST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi

PRICES="${STORY_COST_PRICES:-$ROOT/agent/tools/model-prices.tsv}"
OPENCODE_REASONING_SEPARATE=1

mode="run"
story_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode="check" ;;
    --story)
      shift
      story_arg="${1:-}"
      if [ -z "$story_arg" ]; then
        echo "story-cost: --story needs a value" >&2
        exit 2
      fi
      ;;
    -h | --help)
      sed -n '2,15p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "story-cost: unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

current_branch() {
  git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

is_story() {
  case "$1" in
    "" | . | .. | */* | HEAD) return 1 ;;
  esac
  [ -d "$ROOT/specs/$1" ]
}

if [ "$mode" = "check" ]; then
  b="$(current_branch)"
  if is_story "$b"; then
    if grep -qE '^[[:space:]]*- \[[xX]\]' "$ROOT/specs/$b/tasks.md" 2>/dev/null \
      && [ ! -f "$ROOT/specs/$b/usage.tsv" ]; then
      echo "story-cost: warning: specs/$b/usage.tsv missing; run make story-cost"
    fi
  else
    echo "story-cost: n/a (not a story branch)"
  fi
  exit 0
fi

if [ -n "$story_arg" ]; then
  if ! is_story "$story_arg"; then
    echo "story-cost: refused: specs/$story_arg/ does not exist" >&2
    exit 2
  fi
  story="$story_arg"
else
  story="$(current_branch)"
  if ! is_story "$story"; then
    echo "story-cost: branch '${story:-?}' has no specs/ folder; nothing written"
    exit 0
  fi
fi

for tool in jq python3 awk git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "story-cost: '$tool' is required but not installed" >&2
    exit 2
  fi
done
if [ ! -f "$PRICES" ]; then
  echo "story-cost: price table not found: $PRICES" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Every checkout of this repo: the main one plus each worktree.
mapfile -t CHECKOUTS < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')

# --- Claude Code reader -----------------------------------------------------
# Prints one row per deduplicated reply, 15 tab-separated columns:
#   1 harness  2 key  3 session  4 model  5 provider  6 branch  7 timestamp
#   8 input  9 output  10 cache_write  11 cache_write_1h  12 cache_read
#   13 reasoning  14 speed  15 harness_reported_cost
# input excludes all cache tokens. Claude Code logs the same reply on several
# lines (streaming), so rows with the same message.id:requestId are merged
# and the largest count of each kind is kept.
read_claude() {
  local dirs=() d enc root files
  root="${STORY_COST_CLAUDE_DIR:-}"
  if [ -n "$root" ]; then
    for d in "$root"/*/; do
      [ -d "$d" ] && dirs+=("${d%/}")
    done
  else
    for d in "${CHECKOUTS[@]}"; do
      enc="$(printf '%s' "$d" | sed 's/[\/.]/-/g')"
      [ -d "$HOME/.claude/projects/$enc" ] && dirs+=("$HOME/.claude/projects/$enc")
    done
  fi
  if [ "${#dirs[@]}" -eq 0 ]; then
    echo "claude: no transcript folders, skipped" >&2
    return 0
  fi
  files="$TMP/claude-files"
  {
    find "${dirs[@]}" -maxdepth 1 -name '*.jsonl' -type f -print0
    find "${dirs[@]}" -mindepth 3 -maxdepth 3 -path '*/subagents/*.jsonl' -type f -print0
  } >"$files"
  xargs -0 -r cat <"$files" \
    | jq -rR 'fromjson?
        | select(.type == "assistant" and .message.usage != null
                 and (.message.model // "") != "<synthetic>")
        | .message as $m | $m.usage as $u
        | [ "claude",
            (($m.id // .uuid) + ":" + (.requestId // "")),
            (.sessionId // ""),
            ($m.model // ""),
            "anthropic",
            (.gitBranch // ""),
            ((.timestamp // "") | sub("\\.[0-9]+Z$"; "Z")),
            ($u.input_tokens // 0),
            ($u.output_tokens // 0),
            ($u.cache_creation_input_tokens // 0),
            ($u.cache_creation.ephemeral_1h_input_tokens // 0),
            ($u.cache_read_input_tokens // 0),
            0,
            ($u.speed // "standard"),
            "" ]
        | @tsv' \
    | awk -F'\t' -v OFS='\t' '
        {
          k = $2
          if (!(k in seen)) {
            seen[k] = 1; order[++n] = k
            for (i = 1; i <= 15; i++) row[k, i] = $i
          } else {
            if ($7 < row[k, 7] || ($7 == row[k, 7] && $3 < row[k, 3])) {
              row[k, 3] = $3; row[k, 6] = $6; row[k, 7] = $7
            }
            for (i = 8; i <= 12; i++) if ($i + 0 > row[k, i] + 0) row[k, i] = $i
          }
        }
        END {
          for (j = 1; j <= n; j++) {
            k = order[j]
            line = row[k, 1]
            for (i = 2; i <= 15; i++) line = line OFS row[k, i]
            print line
          }
        }'
}

# --- OpenCode reader --------------------------------------------------------
# Same 15-column rows. Branch comes from the git reflog of the checkout the
# session ran in, looked up at the time of each message.
read_opencode() {
  local db="${STORY_COST_OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
  if [ ! -f "$db" ]; then
    echo "opencode: no database, skipped" >&2
    return 0
  fi
  local copy="$TMP/opencode" co exists pbranch
  mkdir -p "$copy"
  cp "$db" "$copy/opencode.db"
  [ -f "$db-wal" ] && cp "$db-wal" "$copy/opencode.db-wal"
  [ -f "$db-shm" ] && cp "$db-shm" "$copy/opencode.db-shm"

  local tl="$TMP/timeline.tsv"
  : >"$tl"
  for co in "${CHECKOUTS[@]}"; do
    exists=0
    [ -d "$co" ] && exists=1
    pbranch="$(git -C "$ROOT" worktree list --porcelain \
      | awk -v p="$co" '$1 == "worktree" { on = (substr($0, 10) == p) }
                        on && $1 == "branch" { sub("^branch refs/heads/", ""); print; exit }')"
    printf 'C\t%s\t%s\t%s\n' "$co" "$exists" "$pbranch" >>"$tl"
    if [ "$exists" = 1 ]; then
      git -C "$co" reflog --date=unix HEAD 2>/dev/null \
        | sed -nE 's/^[0-9a-f]+ HEAD@\{([0-9]+)\}: checkout: moving from (.*) to (.*)$/\1\t\2\t\3/p' \
        | awk -F'\t' -v OFS='\t' -v p="$co" '{ print "T", p, $1, $2, $3 }' >>"$tl"
    fi
  done

  python3 -I - "$copy/opencode.db" "$tl" "$OPENCODE_REASONING_SEPARATE" <<'PY'
import bisect
import datetime
import sqlite3
import sys

db_path, timeline_path, _separate = sys.argv[1], sys.argv[2], sys.argv[3]

checkouts = {}   # path -> [exists, porcelain_branch, [(epoch, from, to), ...]]
with open(timeline_path, encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if parts[0] == "C":
            checkouts[parts[1]] = [parts[2] == "1", parts[3], []]
        elif parts[0] == "T" and parts[1] in checkouts:
            checkouts[parts[1]][2].append((int(parts[2]), parts[3], parts[4]))
for info in checkouts.values():
    info[2].sort()


def clean(name):
    name = name.replace("refs/heads/", "")
    return name if name and name != "HEAD" else "unattributed"


def branch_for(path, when):
    exists, porcelain, entries = checkouts[path]
    if not exists:
        return "unattributed"
    if not entries:
        return clean(porcelain)
    idx = bisect.bisect_right([e[0] for e in entries], when)
    if idx == 0:
        return clean(entries[0][1])
    return clean(entries[idx - 1][2])


def owner(directory):
    best = None
    for path in checkouts:
        if directory == path or directory.startswith(path.rstrip("/") + "/"):
            if best is None or len(path) > len(best):
                best = path
    return best


conn = sqlite3.connect("file:" + db_path + "?mode=ro", uri=True)
query = """
SELECT m.id, m.session_id, m.time_created, s.directory,
       json_extract(m.data, '$.modelID'),
       json_extract(m.data, '$.providerID'),
       json_extract(m.data, '$.tokens.input'),
       json_extract(m.data, '$.tokens.output'),
       json_extract(m.data, '$.tokens.reasoning'),
       json_extract(m.data, '$.tokens.cache.write'),
       json_extract(m.data, '$.tokens.cache.read'),
       json_extract(m.data, '$.cost')
FROM message m JOIN session s ON s.id = m.session_id
WHERE json_extract(m.data, '$.role') = ?
ORDER BY m.time_created
"""
nulls = 0
for (mid, sid, created, directory, model, provider,
     tin, tout, treas, tcw, tcr, cost) in conn.execute(query, ("assistant",)):
    if not model:
        continue
    path = owner(directory or "")
    if path is None:
        continue
    vals = [tin, tout, treas, tcw, tcr]
    nulls += sum(1 for v in vals if v is None)
    tin, tout, treas, tcw, tcr = [int(v or 0) for v in vals]
    if tin + tout + treas + tcw + tcr == 0:
        continue
    when = int(created) // 1000
    stamp = datetime.datetime.fromtimestamp(when, datetime.timezone.utc)
    fields = [
        "opencode", mid, sid, model, provider or "*",
        branch_for(path, when), stamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
        tin, tout, tcw, 0, tcr, treas, "standard",
        "" if cost is None else repr(float(cost)),
    ]
    print("\t".join(str(f) for f in fields))
if nulls:
    print("opencode: warning: %d token fields were null and counted as 0" % nulls,
          file=sys.stderr)
PY
}

# --- pricing and grouping ---------------------------------------------------
# Reads per-reply rows on stdin; prints one row per (harness, session, model,
# branch). Each reply is priced on its own (fast mode and the Haiku 100k tier
# are per reply), then the dollars are summed.
price_and_group() {
  awk -F'\t' -v OFS='\t' -v prices="$PRICES" -v rsep="$OPENCODE_REASONING_SEPARATE" '
    function strip_date(m) { sub(/-[0-9]{8}$/, "", m); return m }
    function lookup(model, provider, variant,    ms, vs, ps, i, j, k, key) {
      ms[1] = model; ms[2] = strip_date(model)
      vs[1] = variant; vs[2] = "standard"
      ps[1] = provider; ps[2] = "*"
      for (i = 1; i <= 2; i++) for (j = 1; j <= 2; j++) for (k = 1; k <= 2; k++) {
        key = ms[i] SUBSEP ps[k] SUBSEP vs[j]
        if (key in P_in) return key
      }
      return ""
    }
    BEGIN {
      while ((getline line < prices) > 0) {
        if (line ~ /^#/ || line == "") continue
        n = split(line, f, "\t")
        if (n < 10) continue
        key = f[1] SUBSEP f[2] SUBSEP f[3]
        P_in[key] = f[4] + 0; P_out[key] = f[5] + 0
        P_cw5[key] = f[6] + 0; P_cw1[key] = f[7] + 0; P_cr[key] = f[8] + 0
      }
      close(prices)
    }
    {
      h = $1; model = $4; provider = $5; branch = $6; ts = $7
      tin = $8 + 0; tout = $9 + 0; tcw = $10 + 0; tcw1 = $11 + 0; tcr = $12 + 0
      treas = $13 + 0; speed = $14
      if (model == "" || model == "<synthetic>") next
      if (tin + tout + tcw + tcr + treas == 0) next
      g = h SUBSEP $3 SUBSEP model SUBSEP branch
      if (!(g in seen)) {
        seen[g] = 1; order[++ng] = g
        G_h[g] = h; G_s[g] = $3; G_m[g] = model; G_b[g] = branch
        G_first[g] = ts; G_last[g] = ts; G_usd[g] = 0; G_bad[g] = 0; G_src[g] = 0; G_hassrc[g] = 0
      }
      G_in[g] += tin; G_out[g] += tout; G_cw[g] += tcw; G_cw1[g] += tcw1
      G_cr[g] += tcr; G_reas[g] += treas
      if (ts < G_first[g]) G_first[g] = ts
      if (ts > G_last[g]) G_last[g] = ts
      if ($15 != "") { G_src[g] += $15; G_hassrc[g] = 1 }
      # OpenCode messages that carry their own cost use it as-is; only $0
      # messages (free models, subscriptions) fall back to list price.
      if (h == "opencode" && $15 + 0 > 0) { G_usd[g] += $15 + 0; next }
      variant = "standard"
      if (speed == "fast") variant = "fast"
      else if (model ~ /haiku/ && tin + tcw + tcr > 100000) variant = "over100k"
      key = lookup(model, provider, variant)
      if (key == "") {
        G_bad[g] = 1
        if (!(model in warned)) {
          warned[model] = 1
          print "story-cost: warning: no price for model " model " (provider " provider "), row left unpriced" > "/dev/stderr"
        }
        next
      }
      w5 = tcw - tcw1; if (w5 < 0) w5 = 0
      usd = tin * P_in[key] + tout * P_out[key] + w5 * P_cw5[key] + tcw1 * P_cw1[key] + tcr * P_cr[key]
      if (h == "opencode" && rsep == 1) usd += treas * P_out[key]
      G_usd[g] += usd / 1e6
    }
    END {
      for (j = 1; j <= ng; j++) {
        g = order[j]
        usd = G_bad[g] ? "" : sprintf("%.6f", G_usd[g])
        src = G_hassrc[g] ? sprintf("%.6f", G_src[g]) : ""
        printf "%s\t%s\t%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%s\t%s\t%s\t%s\t%s\n",
          G_h[g], G_s[g], G_m[g], G_b[g], G_in[g], G_out[g], G_cw[g], G_cw1[g], G_cr[g], G_reas[g],
          usd, src, (G_bad[g] ? "unpriced" : "ok"), G_first[g], G_last[g]
      }
    }'
}

# --- ledger upsert ----------------------------------------------------------
HEADER=$'harness\tsession_id\tmodel\tbranch\tinput\toutput\tcache_write\tcache_write_1h\tcache_read\treasoning\tusd\tsource_cost\tflag\tfirst_ts\tlast_ts'

# Merge fresh rows (file 2) into the stored ledger (file 1). Fresh rows
# replace stored rows with the same key; stored-only rows stay. A fresh row
# with fewer tokens than the stored one is a sign of deleted logs, so the
# stored row is kept and flagged "shrunk".
merge_ledger() {
  awk -F'\t' -v OFS='\t' '
    function total(a, b, c, d, e) { return a + b + c + d + e }
    FILENAME == ARGV[1] {
      if ($1 == "harness" || $1 == "") next
      k = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
      stored[k] = $0; stot[k] = total($5, $6, $7, $9, $10)
      if (!(k in seen)) { seen[k] = 1; order[++n] = k }
      next
    }
    {
      k = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
      if ((k in stored) && total($5, $6, $7, $9, $10) < stot[k]) {
        split(stored[k], s, "\t"); s[13] = "shrunk"
        line = s[1]
        for (i = 2; i <= 15; i++) line = line OFS s[i]
        stored[k] = line
        print "story-cost: warning: " $1 " session " $2 " (" $3 ") has fewer tokens than the stored row; kept the stored row, flagged shrunk" > "/dev/stderr"
      } else {
        stored[k] = $0
      }
      if (!(k in seen)) { seen[k] = 1; order[++n] = k }
    }
    END { for (j = 1; j <= n; j++) print stored[order[j]] }
  ' "$1" "$2"
}

# Write a file only when the content changed; atomic via mv.
install_if_changed() {
  local src="$1" dest="$2"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    rm -f "$src"
    return 1
  fi
  chmod 644 "$src"
  mv "$src" "$dest"
  return 0
}

render_cost_md() {
  awk -F'\t' -v story="$1" -v prices="$PRICES" '
    BEGIN {
      while ((getline line < prices) > 0) {
        if (line ~ /^#/ || line == "") continue
        n = split(line, f, "\t")
        if (n >= 10) { if (!(f[1] in chk) || f[10] < chk[f[1]]) chk[f[1]] = f[10]; if (f[10] > chkmax[f[1]]) chkmax[f[1]] = f[10] }
      }
    }
    NR == 1 { next }
    $1 == "" { next }
    {
      h = $1
      if (!(h in hs)) { hs[h] = 1; hl[++nh] = h }
      sk = h SUBSEP $2
      if (!(sk in sess)) { sess[sk] = 1; S[h]++; ST++ }
      I[h] += $5; O[h] += $6; W[h] += $7; R[h] += $9; Z[h] += $10
      II += $5; OO += $6; WW += $7; RR += $9; ZZ += $10
      if ($13 == "unpriced") { bad[h]++; badall++; if (!($3 in bm)) { bm[$3] = 1; badlist = badlist (badlist == "" ? "" : ", ") $3 } }
      else if ($11 != "") { U[h] += $11; UU += $11 }
      if ($12 != "") { X[h] += $12; XX += $12; hx[h] = 1; anyx = 1 }
      if ($13 == "shrunk") shrunk = shrunk (shrunk == "" ? "" : ", ") $1 "/" $2 "/" $3
      if ($3 in chk) { used[$3] = 1 }
    }
    function usd_cell(h2,    s) {
      if (h2 == "") { s = UU; if (badall > 0) return (s > 0 ? sprintf("$%.2f + not priced", s) : "not priced"); return sprintf("$%.2f", s) }
      s = U[h2]
      if (bad[h2] > 0) return (s > 0 ? sprintf("$%.2f + not priced", s) : "not priced")
      return sprintf("$%.2f", s)
    }
    END {
      print "# Cost: " story
      print ""
      print "Generated by `make story-cost` from `usage.tsv`; do not edit."
      print ""
      print "| Harness | Sessions | Input | Output | Cache write | Cache read | Reasoning | USD | Harness-reported USD |"
      print "|---|---|---|---|---|---|---|---|---|"
      for (i = 1; i <= nh; i++) {
        h = hl[i]
        printf "| %s | %d | %d | %d | %d | %d | %d | %s | %s |\n", h, S[h], I[h], O[h], W[h], R[h], Z[h], usd_cell(h), (h in hx ? sprintf("$%.2f", X[h]) : "-")
      }
      printf "| **Total** | %d | %d | %d | %d | %d | %d | %s | %s |\n", ST, II, OO, WW, RR, ZZ, usd_cell(""), (anyx ? sprintf("$%.2f", XX) : "-")
      print ""
      print "Dollars are list price from `agent/tools/model-prices.tsv`, except OpenCode messages that store their own non-zero cost, which use that cost. Free and subscription messages that store no cost are shown at list price."
      if (badlist != "") { print ""; print "Not priced (no rate in the price table): " badlist "." }
      if (shrunk != "") { print ""; print "Shrunk rows (logs lost tokens; stored values kept): " shrunk "." }
      lo = ""; hi = ""
      for (m in used) { if (lo == "" || chk[m] < lo) lo = chk[m]; if (hi == "" || chkmax[m] > hi) hi = chkmax[m] }
      if (lo != "") { print ""; print (lo == hi ? "Prices checked on " lo "." : "Prices checked between " lo " and " hi ".") }
    }
  ' "$2"
}

# --- main -------------------------------------------------------------------
fresh_all="$TMP/fresh-all.tsv"
{
  # readers
  read_claude
  read_opencode
} | price_and_group >"$fresh_all"

ls -1 "$ROOT/specs" >"$TMP/specs.txt" 2>/dev/null || : >"$TMP/specs.txt"

fresh="$TMP/fresh.tsv"
awk -F'\t' -v OFS='\t' -v story="$story" -v specs="$TMP/specs.txt" '
  BEGIN { while ((getline line < specs) > 0) ok[line] = 1 }
  {
    if ($4 == story) { print; next }
    if (!($4 in ok)) {
      skipped += $5 + $6 + $7 + $9 + $10
      if (!($4 in nb)) { nb[$4] = 1; nn++ }
    }
  }
  END { printf "%.0f\t%d\n", skipped, nn > "/dev/stderr" }
' "$fresh_all" >"$fresh" 2>"$TMP/skipped.txt"

IFS=$'\t' read -r skipped_tokens skipped_branches <"$TMP/skipped.txt"
human="$(awk -v n="${skipped_tokens:-0}" 'BEGIN {
  if (n >= 1e6) printf "%.1fM", n / 1e6; else if (n >= 1e3) printf "%.1fK", n / 1e3; else printf "%d", n }')"
echo "story-cost: skipped $human tokens on ${skipped_branches:-0} non-story branches"

dir="$ROOT/specs/$story"
ledger="$dir/usage.tsv"
existing="$ledger"
[ -f "$ledger" ] || existing="/dev/null"

merged="$TMP/merged.tsv"
merge_ledger "$existing" "$fresh" | LC_ALL=C sort -t$'\t' -k14,14 -k1,1 -k2,2 -k3,3 -k4,4 >"$merged"

new_ledger="$(mktemp "$dir/.usage.XXXXXX")"
{
  printf '%s\n' "$HEADER"
  cat "$merged"
} >"$new_ledger"

new_md="$(mktemp "$dir/.cost.XXXXXX")"
render_cost_md "$story" "$new_ledger" >"$new_md"

changed=0
install_if_changed "$new_ledger" "$ledger" && changed=1
install_if_changed "$new_md" "$dir/cost.md" && changed=1

rows="$(wc -l <"$merged" | tr -d ' ')"
if [ "$changed" = 1 ]; then
  echo "story-cost: $story: wrote specs/$story/usage.tsv ($rows rows) and cost.md"
else
  echo "story-cost: $story: no change ($rows rows)"
fi
sed -n '/^| \*\*Total/p' "$dir/cost.md"
exit 0
