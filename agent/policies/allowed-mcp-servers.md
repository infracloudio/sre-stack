# Allowed MCP servers

MCP servers are external tools an agent can call. This file is the allowlist;
anything not listed here is not approved for use in this repo. Adding an
entry requires a reviewed PR to this file.

## Rules

- Read-only, public, no-auth servers can be added by PR review. Once
  approved, they are pre-approved for use ("allowed by default") in every
  harness permission config — no per-call confirmation. See the per-harness
  adapter files for those entries.
- Any server that can read private data, act on external systems, or spend
  money needs an explicit approval gate (named owner, scoped credentials,
  hook blocking unreviewed use) before it goes in this list — and is never
  auto-allowed.
- Per-harness config files (e.g. `.mcp.json`) may only reference servers
  from this list.

## Approved servers

| Server | Endpoint | Access | Why approved | Added |
|--------|----------|--------|--------------|-------|
| microsoft-learn | `https://learn.microsoft.com/api/mcp` | read-only, public, no auth | Official Microsoft documentation search/fetch for Azure/AKS facts during the migration; grounded facts instead of training-data guesses. Refreshed daily by Microsoft. | 2026-09-02 |
| aws-knowledge | `https://knowledge-mcp.global.api.aws` | read-only, public, no auth | Official AWS knowledge/documentation search (`search_documentation`, `read_documentation`, `list_regions`, `get_regional_availability`); no mutation tools, no AWS credentials involved, works without an AWS account. The repo is adding Azure alongside AWS (not replacing it), so grounded AWS facts stay needed for the EKS path and the migration itself. Approved by repo owner in PR #94. Use the bare URL: the `/mcp` suffix 302-redirects to GitHub and breaks clients that open a discovery GET stream. | 2026-09-02 |
