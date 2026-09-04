---
name: loom
description: Refresh the harness spec packs and regenerate adapter configs.
  Use when a harness (Codex, Devin, opencode, Claude Code) changed its agent
  config schema, when a spec pack in agent/harness-specs/ is stale (lint
  warns), when an adapter needs a new capability, or when someone says
  "refresh loom", "update harness specs", or "regenerate the adapters".
---
# Loom — Phase A: refresh harness specs

Loom is two things (see `agent/tools/loom.sh` header and
`agent/harness-specs/README.md`):

- **Phase A — refresh (you, this skill):** judgment — read docs, update a
  dated spec pack, change an emitter if the schema changed.
- **Phase B — emit (`agent/tools/loom.sh`):** deterministic — you never
  edit an adapter by hand. You edit the emitter, then re-run loom.

## Process

1. **Identify what changed.** Source: the user's report, a stale spec pack
   (lint warning), or an upstream release note. If nothing changed and the
   pack is stale, re-verify the pack's claims and refresh its `generated:`
   date only if they still hold.
2. **Fetch the current docs** in the repo's order: `context7` MCP first,
   then the official web docs (spec packs carry the URLs), then — if the
   docs are ambiguous — a live probe in the affected harness, logged like
   the conformance runs in `agent/HARNESS-CONFORMANCE.md`.
3. **Update the spec pack** (`agent/harness-specs/<harness>.md`): bump
   `generated:` to today, revise the schema table, keep every claim tied to
   a source URL or a probe reference. Note what the harness does *not*
   support — that list drives GAPS.md.
4. **Decide: emitter change or not.** The pack records reality; the emitter
   encodes it. If the schema changed, update
   `agent/tools/lib/emit-<harness>.sh` (and `loom.config.json` for
   transport overrides) **in the same PR** — the pack is the evidence for
   the emitter diff.
5. **Regenerate and verify:**
   - `agent/tools/loom.sh` (apply)
   - `agent/tools/loom.sh --check` (must be clean)
   - `make lint` (drift gate + staleness + shellcheck)
   - Re-run the affected harness's conformance probes
     (`agent/tests/run-conformance.sh` or the manual probes in
     `agent/HARNESS-CONFORMANCE.md`) if the adapter content changed beyond
     the generated header.
6. **Never touch adapter files by hand.** If `--check` fails, the answer is
   a regenerated emit or an emitter change — never a manual adapter edit.
   The only legitimate adapter diff is one produced by loom.

## Adding a fifth harness

Freeze is over only by explicit decision (D7): drop a
`lib/emit-<name>.sh` defining `emit_<name> IR OUT` into the registry, write
its spec pack, and loom picks it up with no core changes.

## Acceptance for a refresh PR

- Spec pack diff: dated, sourced, honest about gaps
- Emitter diff (if any): justified by the pack diff
- `--check` clean, `make lint` green, affected probes pass
