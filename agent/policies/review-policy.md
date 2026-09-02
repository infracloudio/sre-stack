# Review policy

What every PR review (human or agent) checks, in order. Keep the list short;
reviewers concentrate on intent and risk when the mechanical evidence is
already attached.

## Mechanical (must be green before review starts)

- `make lint` passes: secrets scan, protected paths, shellcheck, yamllint,
  helm lint
- CI is green

## Substantive

1. **Artifact chain intact.** The PR links to or includes the governing
   `intent/` artifact; the diff does what the intent says, and nothing more.
   Scope creep is a rejection reason.
2. **Plan conformance.** If a `plan.md` exists for the change, the diff
   matches it, or `plan.md` was updated in the same commit explaining the
   departure.
3. **Conventions.** Version-pinned Helm installs, values files not `--set`
   chains, check-then-create script pattern, nodeSelector on new workloads,
   secrets sourced from `.env` (see `security-policy.md`).
4. **Idempotency.** Scripts can be re-run safely; create paths check before
   they create.
5. **Blast radius.** Default to changes that fail fast and locally
   (`make lint`, `make setup-local`) before anything that needs cloud access.

## Evidence

Contributors attach logs/screenshots of the change working (README
contribution guide). Agents attach `make lint` output and, where relevant,
`make setup-local` results. Unverified claims ("should work") do not count
as evidence.
