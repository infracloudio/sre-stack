---
harness: claude
generated: 2026-09-03
status: seeded from live conformance probes + upstream docs; re-verify on next Phase A run
---

# Spec pack: Claude Code

Source of truth harness — loom reads FROM Claude config, never writes it.

## Files (inputs to the IR)

| Kind | Path | Notes |
|------|------|-------|
| context | `AGENTS.md` + `.claude/CLAUDE.md` (`@../AGENTS.md` import) | |
| MCP | `.mcp.json` | `mcpServers` map, `type: http` + `url` |
| permissions | `.claude/settings.json` | `permissions.allow/deny/ask`, glob form |
| hooks | `.claude/settings.json` | `hooks.<Event>[]`, matcher + command, `$CLAUDE_PROJECT_DIR` |
| subagents | `.claude/agents/*.md` | frontmatter: name, description, tools |
| skills | `.claude/skills/*/SKILL.md` | frontmatter: name, description |

## Source URLs

- https://code.claude.com/docs/en/memory (CLAUDE.md, imports)
- https://code.claude.com/docs/en/settings (permissions, hooks schema)
- https://code.claude.com/docs/en/mcp

## Not supported / n/a

Nothing to record — this is the source harness.
