---
name: story-cost
description: Record the tokens and dollars this Spec Kit story has used. Use after
  /speckit-implement or /speckit-converge (the hooks in .specify/extensions.yml
  call it), or when someone asks "what did this story cost", "story cost", or
  "update the usage ledger".
---
# Story cost

Writes `specs/<story>/usage.tsv` and `specs/<story>/cost.md` from the local
Claude Code and OpenCode logs. Decision record: AD-014.

## Steps

1. Run `make story-cost` from the repo root. It uses the current branch as the
   story. To report a different story, run `make story-cost STORY=<nnn-slug>`.
   If the branch has no `specs/<branch>/` folder, it writes nothing and says so.
2. Print the `**Total**` row of `specs/<story>/cost.md` to the user, and any
   "Not priced" or "Shrunk" line. Do not edit `usage.tsv` or `cost.md` by hand.
3. Check retention: run `jq .cleanupPeriodDays ~/.claude/settings.json`. If it
   prints `null`, tell the user to add `"cleanupPeriodDays": 3650` to
   `~/.claude/settings.json`, because Claude Code deletes transcripts older
   than 30 days by default and the ledger can only record what still exists.
   Never suggest `0`: on some versions it means "delete immediately". Do not
   edit that file yourself.

## Notes

- The session that runs this hook is recorded only up to this moment. The next
  run adds the rest.
- Running it twice changes nothing unless new usage exists.
- Usage on branches without a `specs/<branch>/` folder is not recorded; the
  command prints how many tokens it skipped.
- Dollars are list price from `agent/tools/model-prices.tsv`, except OpenCode
  messages that store their own non-zero cost, which use that cost. Free and
  subscription messages are shown at list price. Update the price file in a
  reviewed PR when prices change.
