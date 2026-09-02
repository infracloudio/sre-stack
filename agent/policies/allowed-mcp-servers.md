# Allowed MCP servers

MCP servers are external tools an agent can call. This file is the allowlist;
anything not listed here is not approved for use in this repo. Adding an
entry requires a reviewed PR to this file.

## Rules

- Read-only, public, no-auth servers can be added by PR review.
- Any server that can read private data, act on external systems, or spend
  money needs an explicit approval gate (named owner, scoped credentials,
  hook blocking unreviewed use) before it goes in this list.
- Per-harness config files (e.g. `.mcp.json`) may only reference servers
  from this list.

## Approved servers

| Server | Endpoint | Access | Why approved | Added |
|--------|----------|--------|--------------|-------|
| microsoft-learn | `https://learn.microsoft.com/api/mcp` | read-only, public, no auth | Official Microsoft documentation search/fetch for Azure/AKS facts during the migration; grounded facts instead of training-data guesses. Refreshed daily by Microsoft. | 2026-09-02 |
