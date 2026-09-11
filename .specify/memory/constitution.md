<!--
Sync Impact Report
- Version change: 1.3.0 → 1.3.1 (PATCH: wording compressed, no rule changed)
- Principles added: X. Converge to the Agreed Scope, Then Stop
- Sections changed: all prose put in short-form wording; headings, MUST
  rules, paths, tags, numbers, and version metadata verified unchanged
- Templates reviewed: plan-template.md (no edit needed; convergence
  boundary binds converge step and task list, not plan authoring);
  tasks-template.md (no edit needed; existing checklists stay)
- Deferred: none
-->

# sre-stack Constitution

Standing rules every story here follow. Bind humans and AI agents, every
harness. Operational corrections ("agents keep getting X wrong") live in
`AGENTS.md`; rules live here.

## Core Principles

### I. Re-runnable Scripts

Every provision, deploy, teardown script MUST resolve repo root, source
`.env`, check before create or delete. Run any lifecycle command twice:
MUST be safe — second run exit 0, create nothing new. Teardown MUST leave
nothing setup made.

*Rationale:* stack made and destroyed on real clouds many times a week;
script that cannot re-run get hand-fixed under pressure.

### II. Pinned Versions

Helm charts, container images, CLI tools, Kubernetes versions MUST pin to
explicit versions, and existing pins MUST stay unless story spec call for
change. Helm installs use `*/chart-values/` files, never inline `--set`
chains, except one-off host wiring.

*Rationale:* unpinned installs make verification evidence unrepeatable,
turn every rerun into surprise upgrade.

### III. One Configuration Surface

All tunable settings live in `.env`; makefile and every script read from
it. Nothing else hand-edited to change behaviour. `.env` tracked on
purpose with demo-only values and MUST NOT be untracked. Story that add
secrets manager change where `.env` values come from, not that `.env` is
surface.

*Rationale:* one file to read tell person or agent everything a deployment
depend on.

### IV. No Secrets in Git

Real credentials MUST NOT be committed. Demo credentials allowed only in
files listed in `agent/hooks/secrets-allowlist.txt`, and every entry there
MUST carry justification in `agent/policies/security-policy.md`. Secrets
hook, git pre-commit, and CI enforce this; allowlist entry or inline bypass
marker is reviewed change, not workaround.

### V. Workload Placement Contract

Every workload select node pool with `workload=app|persistent|o11y|loadgen`
and tolerate matching taint. Persistent volumes use StorageClass named
`gp2`. Any new cluster target (EKS, k3d, AKS, later) MUST reproduce same
labels, taints, storage class alias so application, observability, scenario
manifests deploy unchanged.

*Rationale:* manifests are product; cluster providers interchangeable only
while this contract hold.

### VI. Specs Without Technical Detail

`spec.md` MUST NOT hold technical material: no code, no config snippets, no
schemas, no commands, no implementation design. It say what needed, why,
what must keep working — words newcomer understand. It name behaviour and
outcomes, never technology used to deliver them. Implementation detail
belong in `plan.md`, `tasks.md`, and change itself.

*Rationale:* spec read for approval by people who did not write code, and
must survive change of technology. If it need technical background to
judge, it describe solution instead of problem.

### VII. Plain Language Everywhere

Every document here — specs, plans, task lists, rationales, commit
explanations, runbooks — MUST use simple everyday language with at least
one concrete example, and MUST NOT lean on unexplained jargon. Technical
term allowed only when no plain word work, and first use carry one-line
explanation. Test: someone new to project read document alone and
understand without asking anyone.

*Rationale:* documents exist to hand understanding from writer to reader.
Jargon hand it only to people who already have it.

### VIII. Try It Before You Plan It

Story whose plan touch running infrastructure MUST get hands-on research
before `plan.md` and `tasks.md` written. During Phase 0 (research.md),
author walk key steps with real commands, together with person who will
review plan:

- Before each command, author say in one or two sentences what it do and
  what could go wrong, then wait for go-ahead when command cost money,
  destroy something, or need environment user must provide.
- Command runs. Actual output — every error, quirk, surprise — reported
  back and discussed before next step. Issues found this way shape plan;
  not discovered later by builder.
- `research.md` record what was actually run and what happened, failures
  included, next to facts it cite. "The docs say" never substitute for "we
  ran it and here is what happened".
- If no live run possible (cost, risk, missing environment), research.md
  say why and what replace it — dry run, `helm template`, sandbox — and
  plan approve that substitute.

*Rationale:* plan written only from documents inherit their silences.
Cluster story only got workable plan because manual run-up surfaced issues
no document mentioned. Errors found while walking steps with user are
cheap; same errors found by builder mid-task are plan departures.

### IX. Plan In Steps, With the User in the Room

`plan.md` and `tasks.md` MUST be written in step-by-step conversation with
person who will review plan — never delivered finished in one go. After
each step, author:

- show what was just decided or written, plain language, with reason;
- pause for questions, corrections, disagreement before next step;
- carry agreed wording forward, so finished plan read as summary of shared
  walkthrough, not verdict handed down.

Test: reviewer read finished plan and recognise every part, because they
saw each step as it was made. If live conversation not possible, same rule
apply in writing — plan posted and agreed in reviewable chunks before
final.

*Rationale:* approval mean understanding. Plan reviewer met only at end get
rubber-stamped or rejected in bulk; plan built in steps get its real doubts
raised while still cheap to fix.

### X. Converge to the Agreed Scope, Then Stop

Convergence — check of code against `spec.md`, `plan.md`, `tasks.md`
before review — verify what was agreed. Not open-ended hunt for more edge
cases. Exit criteria, agreed conditions for closing story:

- Convergence task MUST trace to something already agreed: functional
  requirement, success criterion, acceptance scenario, approved plan
  decision, or rule here. Work tracing to none of these is new story
  issue, never convergence task.
- `spec.md` "Edge Cases" list closed at spec approval. Convergence MUST
  NOT add handling or checks for inputs, branches, failure modes spec do
  not name; extra hardening become new story.
- Only CRITICAL and HIGH findings may become tasks. MEDIUM and LOW
  findings listed in convergence summary and filed as one follow-up story;
  they do not hold up this story's merge.
- Story get one round of convergence work: append, implement, confirm. If
  confirming run still find CRITICAL or HIGH gap, spec or story size is
  wrong — stop and open new story instead of appending second round.
- Tests sized to agreement: every requirement, acceptance scenario, named
  edge case get proving check, and convergence MUST NOT raise task for
  test coverage alone.

These rules bound new convergence work only; they do not license removing
or weakening any existing check.

*Rationale:* review with no boundary always find another way code can fail,
so "repeat until it reports Converged" never converge. First Azure story
reached seven convergence phases and roughly 200 offline checks for what
was agreed as MVP with four named edge cases. Software testing has
established answer — agreement-based exit criteria: stop on requirement
coverage and defect-severity threshold, not on rate new issues still found.
Upstream Spec Kit hit same loop from lifecycle side (issue #4269: repeated
converge runs duplicating tasks) and is adding prerequisite gate; rules
above are scope half of that boundary.

## Verification and Evidence

- `make lint` run for every change and its actual output reported. "Should
  work" is not evidence; command output is.
- Chart changes checked with `helm template` or `helm lint` before any live
  run. Verification-time live runs happen only when story ask for them;
  planning-time live runs follow principle VIII.
- Cloud and library facts grounded through MCP servers listed in
  `agent/policies/allowed-mcp-servers.md`, not from memory.
- Verification steps reviewer will run written into plan and their output
  attached to pull request (`evidence:attached`).

## Development Workflow

Process defined in `docs/sdlc/framework.md`, summarised in `AGENTS.md`.
Rules binding every story:

- Change start from accepted story (`intent:accepted`), sized to finish,
  verification included, in one or two days.
- Spec, plan, implementation each approved by named person who did not
  write them (`gate:spec-approved`, `gate:plan-approved`, human PR review).
  CI block code outside `specs/` until plan label present.
- No `[NEEDS CLARIFICATION]` marker survive into approved spec.
- Departures from plan recorded in `plan.md` in same commit that make them.
- Tests, hooks, lint allowlists, CI never weakened to make change pass.
  Lint allowlists only shrink.

## Governance

This constitution supersede any conflicting convention, comment, or habit.
Every plan include Constitution Check; violation either fixed before
implementation or justified in plan's complexity table and accepted by
Architect.

Amendments made by pull request to this file, approved by someone other
than author, versioned semantically: MAJOR for removing or redefining
principle, MINOR for adding one or materially expanding guidance, PATCH for
wording. When mistake happen twice it become rule here, checklist line, or
hook.

**Version**: 1.3.1 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-11