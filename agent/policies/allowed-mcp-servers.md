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
| context7 | `https://mcp.context7.com/mcp` | read-only, public, no auth (optional API key for higher rate limits — user scope only, never in repo config) | Up-to-date library/API documentation for the observability stack and tooling (Prometheus, Grafana, Loki, Tempo, OpenTelemetry, Istio, KEDA, Helm, etc.) — grounds config work in current docs instead of training-data guesses. Keyless use verified live (tools/call with no Authorization header). Approved by repo owner in PR #94. | 2026-09-03 |

## Spec Kit and MCP servers

Spec Kit does not install, configure, or restrict MCP servers. Its
`speckit-*` skills are prompt files executed *by the harness*, so a
speckit session can only reach the MCP servers the harness loaded — which
this repo controls through the per-harness adapter configs (`.mcp.json`,
`.codex/config.toml`, `.devin/mcp_config.json`, `opencode.json`). This
allowlist therefore already governs Spec Kit sessions; no extra speckit
configuration exists or is needed. (Spec Kit extensions/bundles can
*declare* MCP dependencies in their manifests, but that is documentation
for installers, not enforcement — treat any extension's declared MCP as
unapproved until it is added to this list.)

Two limits to know:

- **Enforcement is harness-side.** Repo config cannot remove an MCP
  server a developer added at *user* scope in their own harness config.
  Hard enforcement needs org-managed settings or network egress rules;
  this list plus the adapter configs is the repo-level line.
- **`/speckit.taskstoissues` is out of policy.** Its prompt instructs the
  agent to use the GitHub MCP server (`list_issues`, issue creation),
  which is not on this list and is not tier-1 (authenticated, acts on an
  external system). Our workflow doesn't use the command — stories are
  already GitHub issues, created with the `gh` CLI by the `write-intent`
  skill. If task→issue conversion is ever wanted, either approve the
  GitHub MCP server through the tier-2 gate above or do it with `gh`.
