---
harness: devin
generated: 2026-09-03
status: seeded from live conformance probes + upstream docs; re-verify on next Phase A run
---

# Spec pack: Devin

## Files loom emits

| Kind | Path | Schema |
|------|------|--------|
| context | `AGENTS.md` | read natively |
| MCP | `.devin/mcp_config.json` | `mcpServers` map: `{url, transport: "http"}` or `{command, args}` |
| permissions | `.devin/config.json` | `permissions.allow[]`, `mcp__<server>__*` form |
| hooks | `.devin/hooks.v1.json` | Claude-like `{PostToolUse: [{matcher, hooks: [{type, command, timeout}]}]}` |
| skills | not file-configurable | |

## Verified by live probe (2026-09-03)

- Devin's Streamable HTTP client does a discovery GET and treats failure as
  fatal. Servers answering 405 to that GET (microsoft-learn, context7) go
  through the pinned `mcp-remote@0.8.3` stdio bridge — recorded as per-server
  overrides in `agent/tools/loom.config.json`, not derived from `.mcp.json`.
- `aws-knowledge` connects natively only at the bare
  `https://knowledge-mcp.global.api.aws`; the `/mcp` suffix 302-redirects to
  GitHub, killing discovery-GET clients.
- Hooks use `$DEVIN_PROJECT_DIR` (not `$CLAUDE_PROJECT_DIR`) and an **empty
  matcher** (Devin tool names differ; scripts self-filter on
  `tool_input.file_path`). Timeout is explicit (30).
- Devin also auto-imports `.claude/settings.json` hooks via
  `read_config_from.claude`; the explicit files remain the source of record.

## Source URLs

- https://docs.devin.ai/work-with-devin/devin-cli (CLI + project config)
- https://docs.devin.ai/work-with-devin/devin-guides/devin-mcp (MCP config)

## Emitter notes

- JSON files get the `"_generated_by"` first key (no comment syntax)
- Non-MCP permission entries are GAPS rows (manual CLI approval)
