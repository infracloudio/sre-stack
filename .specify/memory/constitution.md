<!--
Sync Impact Report
- Version change: template → 1.0.0 (initial ratification)
- Principles added: I. Re-runnable scripts · II. Pinned versions ·
  III. One configuration surface · IV. No secrets in git ·
  V. Workload placement contract
- Sections added: Verification and Evidence · Development Workflow · Governance
- Templates reviewed: plan-template.md (Constitution Check gate reads this
  file at plan time; no edits needed) · spec-template.md · tasks-template.md
- Deferred: none
-->

# sre-stack Constitution

These are the standing rules every story in this repository follows. They
apply to humans and AI agents alike, on every harness. Operational
corrections ("agents keep getting X wrong") live in `AGENTS.md`; rules live
here.

## Core Principles

### I. Re-runnable Scripts

Every provisioning, deployment, and teardown script MUST resolve the repo
root, source `.env`, and check before it creates or deletes. Running any
lifecycle command twice in a row MUST be safe: the second run exits 0 and
creates nothing new. Teardown MUST leave nothing behind that the setup
created.

*Rationale:* the stack is created and destroyed on real clouds many times a
week; a script that cannot be re-run is a script that will be hand-fixed
under pressure.

### II. Pinned Versions

Helm charts, container images, CLI tools, and Kubernetes versions MUST be
pinned to explicit versions, and existing pins MUST be preserved unless the
story's spec calls for the change. Helm installs use `*/chart-values/`
files, never inline `--set` chains, except for one-off host wiring.

*Rationale:* unpinned installs make verification evidence unrepeatable and
turn every rerun into a surprise upgrade.

### III. One Configuration Surface

All tunable settings live in `.env`; the makefile and every script read
from it. Nothing else is hand-edited to change behaviour. `.env` is
deliberately tracked with demo-only values and MUST NOT be untracked.
A story that introduces a secrets manager changes where `.env` values come
from, not that `.env` is the surface.

*Rationale:* one file to read tells a person or an agent everything a
deployment depends on.

### IV. No Secrets in Git

Real credentials MUST NOT be committed. Demo credentials are allowed only
in files listed in `agent/hooks/secrets-allowlist.txt`, and every entry
there MUST carry a justification in `agent/policies/security-policy.md`.
The secrets hook, git pre-commit, and CI enforce this; an allowlist entry
or inline bypass marker is a reviewed change, not a workaround.

### V. Workload Placement Contract

Every workload selects its node pool with `workload=app|persistent|o11y|loadgen`
and tolerates the matching taint. Persistent volumes use the StorageClass
named `gp2`. Any new cluster target (EKS, k3d, AKS, or later) MUST
reproduce the same labels, taints, and storage class alias so that the
application, observability, and scenario manifests deploy unchanged.

*Rationale:* the manifests are the product; cluster providers are
interchangeable only while this contract holds.

## Verification and Evidence

- `make lint` runs for every change and its actual output is reported.
  "Should work" is not evidence; command output is.
- Chart changes are checked with `helm template` or `helm lint` before any
  live run. Live cluster runs happen only when the story asks for them.
- Cloud and library facts are grounded through the MCP servers listed in
  `agent/policies/allowed-mcp-servers.md`, not from memory.
- Verification steps a reviewer will run are written into the plan and
  their output is attached to the pull request (`evidence:attached`).

## Development Workflow

The process is defined in `docs/sdlc/framework.md` and summarised in
`AGENTS.md`. The rules that bind every story:

- A change starts from an accepted story (`intent:accepted`) and is sized
  to finish, including verification, in one or two days.
- Spec, plan, and implementation are each approved by a named person who
  did not write them (`gate:spec-approved`, `gate:plan-approved`, human PR
  review). CI blocks code outside `specs/` until the plan label is present.
- No `[NEEDS CLARIFICATION]` marker survives into an approved spec.
- Departures from the plan are recorded in `plan.md` in the same commit
  that makes them.
- Tests, hooks, lint allowlists, and CI are never weakened to make a change
  pass. Lint allowlists only shrink.

## Governance

This constitution supersedes any conflicting convention, comment, or
habit. Every plan includes a Constitution Check; a violation is either
fixed before implementation or justified in the plan's complexity table
and accepted by the Architect.

Amendments are made by pull request to this file, approved by someone
other than the author, and versioned semantically: MAJOR for removing or
redefining a principle, MINOR for adding one or materially expanding
guidance, PATCH for wording. When a mistake happens twice it becomes a
rule here, a checklist line, or a hook.

**Version**: 1.0.0 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-04
