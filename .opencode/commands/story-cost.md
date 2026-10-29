---
description: Record the tokens and dollars this Spec Kit story has used. Use after /speckit.specify, /speckit.tasks, /speckit.analyze, /speckit.implement or /speckit.converge, or when asked what a story cost.
---

Writes `specs/<story>/usage.tsv` and `specs/<story>/cost.md` from the local
Claude Code and OpenCode logs. Decision record: AD-014.

1. Run `make story-cost` from the repo root. It uses the current branch as the
   story. To report a different story, run `make story-cost STORY=<nnn-slug>`.
   If the branch has no `specs/<branch>/` folder, it writes nothing and says so.
2. Print the `**Total**` row of `specs/<story>/cost.md` to the user, and any
   "Not priced" or "Shrunk" line. Do not edit `usage.tsv` or `cost.md` by hand.
3. Check retention: run `jq .cleanupPeriodDays ~/.claude/settings.json`. If it
   prints `null`, tell the user to add `"cleanupPeriodDays": 3650` to
   `~/.claude/settings.json`, because Claude Code deletes transcripts older
   than 30 days by default. Never suggest `0`: on some versions it means
   "delete immediately". Do not edit that file yourself.

The session that runs this hook is recorded only up to this moment; the next
run adds the rest. Running it twice changes nothing unless new usage exists.
