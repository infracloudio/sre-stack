# Security policy

Source of truth for what agents and contributors must not do. Hooks in
`agent/hooks/` enforce the deterministic subset; this document states the
full intent and the rationale for what the hooks cannot express.

## Secrets

- Never commit credentials, tokens, private keys, or connection strings.
  Secrets belong in `.env` (local) or the deployment platform's secret store.
- `agent/hooks/check-secrets.sh` scans changed files for credential patterns.
- Known exception: `.env` is tracked in git deliberately. It holds demo-only
  credentials for a throwaway lab stack and is the single configuration
  surface for the makefile and every script. The hook excludes it. Do not
  replace `.env` values with production secrets.
- Known debt: `scenarios/scenario-02/scripts/kill-sleep-processes.sh`
  hardcodes an RDS password and endpoint. Cleanup belongs to the database
  migration stories (`docs/sdlc/framework.md`, section 8); the hook flags
  scripts matching this pattern so new instances do not accumulate.
- `agent/hooks/secrets-allowlist.txt` may only grow together with a
  justification added to this file naming the path; `check-ratchets.sh`
  enforces that in pre-commit and CI.
- If a real secret is ever committed: rotate it immediately. Git history
  removal is secondary to rotation.

## Supply chain / external tools

- MCP servers are external tools; only servers listed in
  `agent/policies/allowed-mcp-servers.md` may be used in this repo.
- Helm charts and container images: keep the existing version pins. Do not
  bump versions as a drive-by; version changes are their own intent artifact.

## Checks are law

- Never weaken, skip, or comment out a check in `agent/hooks/` or CI to make
  a task pass. If a check is wrong, change it in its own reviewed commit with
  a stated reason.
- The paths in `agent/hooks/protected-paths.txt` (the hooks, CI workflows,
  these policies, Claude settings, and every generated Spec Kit or loom
  file) are refused to agents before the edit happens. A human commits such
  a change with `PROTECTED_OVERRIDE=1`; CI accepts it only on a PR that
  carries `gate:plan-approved`, i.e. someone other than the author approved.
- Pre-commit hooks are compulsory: `make install` enables them and
  `make lint` fails until they are.
- Sole exception: the inline marker `# secret-check:allow` suppresses a
  secrets finding on one line. It exists for fake fixture strings inside
  test/probe tooling (e.g. `agent/tests/`), never for real credentials. A
  new marker outside `agent/` or `docs/` fails the ratchet check.
