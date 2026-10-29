# Story cost

Run `make story-cost` from the repository root and wait for completion.
For another story use `make story-cost STORY=<nnn-slug>`. The branch normally
selects the story; without a matching specs/<branch>/ folder it writes nothing
and reports skipped usage. Never edit usage.tsv or cost.md by hand.

Report the **Total** row in specs/<story>/cost.md and every Not priced or Shrunk
warning, plus stderr failures and missing-log warnings. Only Claude Code and
OpenCode collectors exist. Codex and Devin accounting is unavailable, not zero;
totals are partial collected usage, never complete cross-harness accounting.

Check retention with `jq .cleanupPeriodDays ~/.claude/settings.json` when that
file exists. If missing or null, tell the user to set cleanupPeriodDays to 3650:
Claude deletes old transcripts after 30 days by default. Never suggest 0 (it
can mean delete immediately), and never edit global settings yourself.

Running twice is safe; the current session is recorded only up to collection.
Later collection adds the rest. Prices come from agent/tools/model-prices.tsv
except nonzero stored OpenCode costs. Free/subscription usage uses list price;
price changes require review. AD-014 explains the ledger design.
