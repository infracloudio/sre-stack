<!--
Sync Impact Report
- Version change: 1.1.0 → 1.2.0 (MINOR: two principles added)
- Principles added: VIII. Try It Before You Plan It ·
  IX. Plan In Steps, With the User in the Room
- Sections changed: "Verification and Evidence" — one bullet reworded to
  point planning-time live runs at principle VIII (wording only, no rule
  removed)
- Templates reviewed: plan-template.md (research.md is the Phase 0 output;
  principles VIII and IX bind how Phases 0–1 are done, no template edit
  needed)
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

### VI. Specs Without Technical Detail

`spec.md` MUST NOT contain technical material: no code, no config snippets,
no schemas, no commands, no implementation design. It says what is needed,
why, and what must keep working — in words a newcomer understands. It names
behaviour and outcomes, never the technology used to deliver them.
Implementation detail belongs in `plan.md`, `tasks.md`, and the change
itself.

*Rationale:* the spec is read for approval by people who did not write the
code, and it must survive a change of technology. If it needs technical
background to judge, it is describing the solution instead of the problem.

### VII. Plain Language Everywhere

Every document in this repository — specs, plans, task lists, rationales,
commit explanations, runbooks — MUST be written in simple everyday language
with at least one concrete example, and MUST NOT rely on unexplained jargon.
A technical term is allowed only when no plain word works, and its first use
carries a one-line explanation. The test: someone new to the project can
read the document alone and understand it without asking anyone.

*Rationale:* documents exist to hand understanding from writer to reader.
Jargon hands it only to people who already have it.

### VIII. Try It Before You Plan It

A story whose plan touches running infrastructure MUST be researched
hands-on before `plan.md` and `tasks.md` are written. During Phase 0
(research.md), the author walks the key steps with real commands, together
with a person who will review the plan:

- Before each command, the author says in one or two sentences what it does
  and what could go wrong, then waits for a go-ahead when the command costs
  money, destroys something, or needs an environment the user must provide.
- The command runs. The actual output — including every error, quirk, and
  surprise — is reported back and discussed before the next step. Issues
  found this way shape the plan; they are not discovered later by the
  builder.
- `research.md` records what was actually run and what happened, failures
  included, next to the facts it cites. "The docs say" is never a substitute
  for "we ran it and here is what happened".
- If no live run is possible (cost, risk, missing environment), research.md
  says why and what replaces it — a dry run, `helm template`, a sandbox —
  and the plan approves that substitute.

*Rationale:* a plan written only from documents inherits their silences.
The cluster story only got a workable plan because its manual run-up
surfaced issues no document mentioned. Errors found while walking the steps
with the user are cheap; the same errors found by the builder mid-task are
plan departures.

### IX. Plan In Steps, With the User in the Room

`plan.md` and `tasks.md` MUST be written in a step-by-step conversation
with a person who will review the plan — never delivered finished in one
go. After each step, the author:

- shows what was just decided or written, in plain language, together with
  the reason for it;
- pauses for questions, corrections, or disagreement before moving to the
  next step;
- carries the agreed wording forward, so the finished plan reads as a
  summary of a shared walkthrough, not a verdict handed down.

The test: the reviewer reads the finished plan and recognises every part of
it, because they saw each step as it was made. If live conversation is not
possible, the same rule applies in writing — the plan is posted and agreed
in reviewable chunks before it is finalised.

*Rationale:* approval means understanding. A plan the reviewer met only at
the end gets rubber-stamped or rejected in bulk; a plan built in steps gets
its real doubts raised while they are still cheap to fix.

## Verification and Evidence

- `make lint` runs for every change and its actual output is reported.
  "Should work" is not evidence; command output is.
- Chart changes are checked with `helm template` or `helm lint` before any
  live run. Verification-time live runs happen only when the story asks for
  them; planning-time live runs follow principle VIII.
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

**Version**: 1.2.0 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-10
