# Intent: loom — generate harness adapters from the Claude config

Author: Rijo John (AI platform engineer). Status: draft.

## Problem

`.claude/` is where agent config gets written and tested. Codex, Devin and
opencode each need the same rules, MCP servers, permissions and hooks in
their own schema, and today those adapters (`.codex/config.toml`,
`.devin/*.json`, `opencode.json`) are hand-maintained "in parity until loom
generates them". Hand parity drifts silently — nothing fails when someone
edits `.claude/settings.json` and forgets `.devin/config.json`.

## Proposed outcome

One canonical config (Claude Code), N generated adapters, and a drift gate
in `make lint`. `agent/tools/loom.sh` emits the adapters deterministically
(no network, no model); `loom --check` fails the build when an adapter
differs from regeneration. A dated spec pack per harness under
`agent/harness-specs/` carries the schema knowledge and a `loom` skill
drives the occasional doc-refresh pass.

## Affected users and systems

Users: repo maintainers and every harness agent session that reads the
adapters.

Systems changed: `agent/tools/loom.sh` + `agent/tools/lib/` (new),
`agent/harness-specs/` (new), `makefile` (lint target), `.claude/skills/loom/`
(new), `intent/loom.md` (this file), conformance doc + AGENTS.md one-liners.

Systems unchanged: the four adapters' *content* (the emitter must reproduce
them byte-for-byte as the golden fixture), `.mcp.json`,
`.claude/settings.json`, all hooks/policies, CI beyond the lint chain.

## Constraints

- bash + jq only, no new toolchain
- Harness set frozen at claude/codex/devin/opencode; drop-in registry so a
  fifth is one emitter file + one spec pack
- Claude Code is the source of truth; no reverse translation
- The allowlist policy (`agent/policies/allowed-mcp-servers.md`) is a hard
  gate inside loom, not a warning
- Generated files carry a loom header; hand edits to them are a lint failure

## Open questions

None — resolved in the plan (`~/claude-plans/loom.md`, decisions D1–D8).

## Decisions

| # | Question | Decision | Decided by | Date |
|---|----------|----------|------------|------|
| 1 | Artifact chain or direct implementation? | Direct (D5) | Rijo | 2026-09-03 |
| 2 | bash+jq or Python? | bash+jq (D6) | Rijo | 2026-09-03 |
| 3 | Freeze or registry? | Freeze at 4, drop-in registry (D7) | Rijo | 2026-09-03 |
| 4 | Reverse translation? | No — Claude is source of truth (D8) | Rijo | 2026-09-03 |
