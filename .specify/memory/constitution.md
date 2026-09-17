<!--
Sync Impact Report
- Version change: 1.3.1 → 1.4.0 (MINOR: principles VIII and IX tightened)
- Principles added: none
- Principles changed: VIII made explicit that Phase 0 research runs against
  a real cluster or subscription, that simulated or remembered output is a
  false claim rather than a weak one, and that missing access is a blocker
  the author must raise and wait on — not a licence to substitute. The
  substitute path (dry run, helm template, sandbox) now applies only after
  access was asked for and refused, must record who was asked and what it
  cannot prove, is approved by the Architect at the plan gate, and is named
  in the PR. Cheap read-only checks — chart version, chart name, make
  target, path, label, taint — never qualify for substitution.
- Principles changed: IX renamed "Plan In Steps, With the User in the Room"
  → "Author In Steps, Developer in the Loop". Scope widened from plan.md and
  tasks.md to spec.md as well. Rule restated as agent-proposes /
  developer-accepts, one section at a time, agent stopping between sections,
  with the developer barred from approving a section unread or a claim
  unchecked. Earlier wording read as reviewer sign-off; intent is the
  authoring loop between agent and developer.
- Sections changed: none beyond VIII and IX
- Templates reviewed: plan-template.md, spec-template.md, tasks-template.md
  (no edit needed; all three are structure only and carry no authoring
  cadence — plan-template.md line 7 defers execution workflow to the command
  definition)
- Propagated to: .claude/, .agents/, .devin/ skills and .opencode/ commands
  for speckit-specify, speckit-plan, speckit-tasks (Incremental Authoring
  and Phase 0 Research sections, committed with PROTECTED_OVERRIDE=1);
  docs/sdlc/framework.md step 5; AGENTS.md SDLC contract
- Deferred: none. Known gap — `specify integration upgrade --force`
  overwrites the four harness copies, and check-speckit-version.sh compares
  version metadata, not content, so a future upgrade drops the skill block
  silently. Constitution, framework.md and AGENTS.md survive it.
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
against real cluster or real subscription before `plan.md` and `tasks.md`
written. Live run is the default and the requirement, not the ideal case.
During Phase 0 (research.md), author walk key steps with real commands,
together with person who will review plan:

- Before each command, author say in one or two sentences what it do and
  what could go wrong, then wait for go-ahead when command cost money,
  destroy something, or need environment user must provide.
- Command runs against real target — the cluster, the subscription, the
  live chart repository. Actual output — every error, quirk, surprise —
  reported back and discussed before next step. Issues found this way
  shape plan; not discovered later by builder.
- `research.md` record what was actually run and what happened, failures
  included, next to facts it cite. Paste terminal output verbatim. "The
  docs say" never substitute for "we ran it and here is what happened".
  Invented, expected, or illustrative output MUST NOT appear — an output
  block labelled simulated, or written from memory, is a false claim, and
  worse than leaving question open.
- **No access is a blocker, not a licence to substitute.** Author who
  cannot reach cluster or subscription MUST stop and ask for it — name who
  they asked, what they need (subscription, role, credentials, quota), and
  wait. Story wait; agent does not proceed and fill gap from memory.
- Only when access asked for and genuinely cannot be granted in story's
  timebox does substitute apply: `--dry-run`, `helm template`, `helm
  search`, sandbox, read-only query. research.md record who was asked, what
  answer came back, which substitute used, and what it cannot prove.
  Architect approve substitute at plan gate; substitution not approved in
  advance and not decided by author alone. Limitation named in pull
  request, not buried in research.md.
- Cheap read-only checks never qualify for substitute. Chart version,
  chart name, make target, file path, label, taint are settled by one
  command against real source, and MUST be settled that way.

*Rationale:* plan written only from documents inherit their silences.
Cluster story only got workable plan because manual run-up surfaced issues
no document mentioned. Errors found while walking steps with user are
cheap; same errors found by builder mid-task are plan departures. Asking
for access feel slow and cost hours; planning on guessed output cost days
and burn reviewer trust. Blocked story is honest state — record it and ask.

### IX. Author In Steps, Developer in the Loop

`spec.md`, `plan.md` and `tasks.md` MUST be written one section at a time,
agent proposing and developer accepting — never generated whole and
committed unread. Developer instruct agent up front: produce one section,
stop, wait. Do not start next section until told.

Loop for each section:

- agent propose section — what it decided or wrote, plain language, with
  reason, and what it checked to know it true;
- developer read it, then do one of three things: ask question, give
  different instruction, or approve;
- only on approve does agent move to next section. Agreed wording carry
  forward; approved section not reopened without reason.

Agent propose, developer accept. Developer own what goes in file — cannot
approve section they have not read, and cannot approve claim they have not
checked. One-line check (`helm search`, `grep` target in makefile, `ls`
directory) beat reading it twice.

Test: developer recognise every part of finished file, because they
approved each part as it was made. Same rule apply to research, per
principle VIII: findings arrive one at a time, real output attached, before
plan built on them.

*Rationale:* whole file generated in one pass get skimmed once and
committed. Wrong version number is obvious on own line and invisible in
three hundred lines read at end. Agent write fast; developer accepting
section by section is what keep it honest. Reviewer met only at end get
rubber-stamped or rejected in bulk; file built in steps get its real doubts
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

**Version**: 1.4.0 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-17