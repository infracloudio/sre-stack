---
harness: opencode
generated: 2026-09-03
status: seeded from live conformance probes + upstream docs; re-verify on next Phase A run
---

# Spec pack: opencode

## Files loom emits

| Kind | Path | Schema |
|------|------|--------|
| context | `AGENTS.md` | read natively |
| MCP | `opencode.json` | `mcp` map: `{type: "remote", url}` |
| permissions | not emitted | docs servers allowed by default; no glob allowlist (non-MCP entries → GAPS.md) |
| hooks | **not supported in config** | plugin API only — compensating control: pre-commit + CI (GAPS.md) |
| skills | `agent/`, `command/` dirs | not wired from Claude today |

## Verified by live probe (2026-09-03)

- `AGENTS.md` read natively; `opencode run` for non-interactive use
- `mcp.*` entries with `type: remote` connect natively to all three approved
  servers (no transport quirks)
- No hook mechanism in the config schema

## Source URLs

- https://opencode.ai/docs/config (schema `$schema: https://opencode.ai/config.json`)
- https://opencode.ai/docs/mcp-servers

## Emitter notes

- **No generated marker possible**: opencode's config schema rejects unknown
  keys — `_generated_by` made the harness fail to parse the file (found by
  live probe, 2026-09-03). `loom --check` drift gate is the marker here.
- `$schema` key is required and first.
