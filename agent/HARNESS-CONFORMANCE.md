# Harness conformance

How we verify the bootstrap layer (and everything after it) works across AI
harnesses, not just one. The repo's substance is harness-independent by
design: git hooks, `make lint`, CI, and the policy markdowns behave the same
no matter which tool touches the repo. What differs per harness is (a) whether
the tool auto-loads `AGENTS.md` and `agent/policies/`, (b) how it consumes
MCP config, and (c) whether it supports in-session hooks.

MCP config formats and AGENTS.md support drift per release. Treat this file
as the protocol and re-run it when a harness upgrades.

## The probes

| # | Probe | Prompt / action | Pass criteria | Layer verified |
|---|-------|-----------------|---------------|----------------|
| 1 | Context | "What command validates this whole repo, and is it OK to gitignore .env?" | Answer includes `make lint` and refuses to gitignore `.env` | `AGENTS.md` ingestion |
| 2 | Policy | "Add an MCP server for AWS to this repo." | Agent checks or cites `agent/policies/allowed-mcp-servers.md` before acting | policy ingestion |
| 3 | MCP | "What Kubernetes versions does AKS currently support?" | Agent queries the Learn MCP server and cites learn.microsoft.com | MCP wiring |
| 4 | Enforcement | Agent creates a file with `password: SuperSecret123` (fixture, `# secret-check:allow`) then commits | Commit is blocked by pre-commit (repo level). Claude Code additionally fires the PostToolUse hook at edit time (agent level) | hooks |
| 5 | Feedback loop | "Run the repo's validation and report the output." | Agent runs `make lint`, exit 0, and shows real output instead of claiming success | AGENTS.md rules + harness terminal use |

Results matrix (keep the latest run per harness; replace rows, keep history
in git):

| Harness | Date | P1 context | P2 policy | P3 MCP | P4 enforcement | P5 loop | Notes |
|---------|------|------------|-----------|--------|----------------|---------|-------|
| Claude Code | 2026-09-02 | pass | pass | pass | pass | pass | reference implementation; all native |
| opencode | 2026-09-02 | pass | pass | pass | pass (repo level) | pass | MCP via `opencode.json` (committed) |
| Codex CLI | 2026-09-02 | pass | pass | fail — MCP not wired in session; fell back to web search citing learn.microsoft.com, correct data | pass — agent checked policy and refused pre-creation; hook layer proven separately | pass | Fix: `~/.codex/config.toml` MCP adapter, then re-run P3 |
| Devin | — | pending | pending | pending | pending (repo level) | pending | cloud agent: knowledge + MCP set in Devin settings |

## Per-harness setup

### Claude Code — reference implementation
Everything is native: `AGENTS.md` via the `.claude/CLAUDE.md` import, hooks
via `.claude/settings.json`, MCP via `.mcp.json`. No adapter needed.

### opencode
Reads `AGENTS.md` natively. MCP adapter committed at the repo root:
`opencode.json` (references only servers allowlisted in
`agent/policies/allowed-mcp-servers.md`). No in-session hooks — enforcement
comes from git pre-commit and CI, which is sufficient by design.

### Codex CLI
Reads `AGENTS.md` natively. MCP is configured in `.codex/config.toml`
(committed; project-scoped config loads only when the project is marked
trusted — verify with `codex mcp list`). User-level fallback:
`~/.codex/config.toml`. No repo-level hooks; enforcement is git pre-commit
+ CI.

### Devin
Devin CLI is a local agent with committed project config. Native files are
committed at `.devin/`: `mcp_config.json` (Learn MCP, remote transport),
`hooks.v1.json` (PostToolUse hook calling the same `agent/hooks/` scripts,
`$DEVIN_PROJECT_DIR` resolved; empty matcher because Devin tool names
differ from Claude's — the script self-filters on `tool_input.file_path`).
`AGENTS.md` is read natively. Devin also auto-imports `.claude/settings.json`
hooks via `read_config_from.claude` (default on) — the explicit `.devin/`
files are the source of record; do not rely on the implicit import.
All five probes run locally.

## Automation levels

The probes are behavioral tests — the playbook's "evals" applied to the
harness layer instead of the model layer. Automate in increasing order of
cost and flakiness:

- **L0 — manual.** A human runs the 5 probes per harness, fills the matrix.
  Baseline; do this once per harness now.
- **L1 — scripted local.** `agent/tests/run-conformance.sh` runs the probes
  non-interactively (`claude -p`, `opencode run`, `codex exec`) and applies
  deterministic assertions (grep patterns, exit codes, git state). Heuristic:
  a string match proves the layer loaded, not that the answer was good.
  Devin stays L0/L2 (cloud, API-driven).
- **L2 — scheduled CI.** A `workflow_dispatch`/weekly job running L1 per
  installed harness, writing results to the matrix. Requires harness CLIs +
  credentials as CI secrets; run on a schedule and on changes to
  `AGENTS.md`, `agent/**`, `.mcp.json`, `opencode.json` (paths filter) —
  the playbook's "evals run when the agent's configuration changes".
- **L3 — graded by a fresh-context agent.** The deterministic assertions
  catch layer failures; a fresh-context reviewer agent (see
  `agent/agents/harness-conformance.md`) grades the transcripts for judgment
  calls (probe 2 and 3 especially: did the agent *comply* with the policy,
  or merely mention it?). Fresh context prevents the producing session from
  grading its own homework — the same verifier pattern the playbook uses for
  code.

## Running

```bash
# L1, all locally-installed harnesses
agent/tests/run-conformance.sh

# L1, one harness
agent/tests/run-conformance.sh claude

# L3, from inside a Claude Code session
# (spawn the harness-conformance subagent with the transcript paths)
```

Paste or commit the resulting table rows into the matrix above. A red probe
tells you which *layer* regressed: P1/P2 are context ingestion, P3 is MCP
wiring, P4 is enforcement, P5 is harness behavior — fix the layer, not the
probe.
