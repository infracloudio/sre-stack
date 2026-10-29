# Compact Spec Kit rules — every harness

Read AGENTS.md, .specify/memory/constitution.md and docs/sdlc/framework.md.
These project rules govern every Spec Kit command. Preserve independent spec,
plan and implementation approvals, protected paths, mandatory lint and all
existing tests. Never change an existing story's evidence, task IDs, approvals
or feature pointer as part of a tooling refresh. Read existing artifacts and
support their requirement identifiers; do not migrate their format.

## Research and authoring

Principle VIII: for running infrastructure, hands-on research against a real
cluster or subscription comes before any spec section. Explain each command,
obtain go-ahead for costly/destructive actions or missing environments, then
report actual output and discuss each finding. Record commands, errors and
verbatim output in research.md. Never invent or simulate output. Missing access
is a blocker: ask who can grant it and wait. Only after access was requested
and refused may an Architect approve a documented substitute at the spec gate;
name its limits and the refusal in research and the PR. Cheap read-only checks
of versions, paths, targets, labels and taints always use the real source.
Plans build on research.md. Missing facts are new findings; promises changed
by a finding return to the Architect for spec approval before planning resumes.
Tooling-only changes need no cloud research.

Principle IX: write spec.md, plan.md and tasks.md one section at a time.
Propose one section, explain decisions and checks, STOP and wait for explicit
developer approval before the next. Do not generate whole files in one pass.
Keep accepted wording unless a reason to reopen it is discussed. Independent
review approvals do not replace this authoring loop.

## Compact artifacts

For future stories target spec.md 400 words, plan.md 600 words, tasks.md 600
words. These are targets, not caps. Preserve every acceptance criterion,
required concrete example and actual evidence. Never truncate real command
output. Keep research.md and evidence when required. Create supporting design
files only when the story needs them; link rather than repeat. Remove unused
template sections. Use plain words, short lists and at least one concrete
example. Specs describe outcomes without implementation details; plans retain
actual paths, reviewer-facing verification commands, decisions and reasons.
Tasks start with Now and use stable T001-style IDs, checkbox state, exact file
paths, dependencies and requirement references. Preserve legacy identifiers.
Report only changed paths, decisions, blockers, verification and the next step;
do not repeat entire artifacts in completion messages.

## Bounded implementation

Default to one acceptance slice or task range per implement invocation, including
its proving checks. Honor larger batches explicitly requested by the user.
State selected IDs before work; keep tasks.md Now current with active/next IDs
and blockers. Report actual verification and the next implement range when work
remains. Suggest convergence only once original implementation tasks and required
checks are complete. Do not mark unverified work complete.

## Bounded convergence

Principle X: trace every finding to an agreed requirement, success criterion,
acceptance scenario, approved plan decision or constitution rule. The Edge
Cases list is closed at spec approval. Only CRITICAL/HIGH agreed-scope gaps
may become tasks. MEDIUM/LOW findings are follow-up story material and cannot
block merge. One round only: append, implement, confirm. If confirmation still
finds CRITICAL/HIGH gaps, stop and ask for a new story rather than appending a
second round. Do not create issues without authorization. Never add tasks for
coverage alone or remove or weaken existing checks.

## Hooks and accounting

Read .specify/extensions.yml for before/after hooks of the current command.
Disabled hooks do not run; empty/null conditions execute. Leave nonempty
conditions to Spec Kit's HookExecutor; report them as deferred. Offer optional
hooks; actually execute mandatory hooks and wait for results. Invalid YAML is
a visible blocker for mandatory dispatch, never silent success. Use native
command invocations for other hooks. The mandatory command `story-cost` is
special: its sole after-hook dispatcher is the config-aware runner; do not
also dispatch it generically. Invoke the runner exactly once per command:
it executes `make story-cost` directly through
`bash agent/spec-kit/posthook.sh after_<verb>` for specify, tasks, analyze,
implement and converge, before reporting completion. Never rely on a custom
skill alias being installed, and never treat printing EXECUTE_COMMAND as execution.
On partial or blocked runs still collect usage before returning to the user.
The runner skips missing, disabled and optional hooks, defers nonempty
conditions to HookExecutor and fails visibly on malformed YAML. Optional
story-cost collection runs only on explicit request. It retains branch-based
story attribution (AD-014), never attribution from the feature pointer; use an
explicit STORY override to report a different story. Analysis is read-only for
spec/plan/tasks and the feature pointer; its configured cost ledger posthook is
an explicitly allowed bookkeeping side effect.
Read agent/spec-kit/story-cost.md and report totals and warnings. A hook failure
must be reported and prevents claiming successful command completion.

Only Claude Code and OpenCode collection is supported. Codex and Devin usage
is unavailable: never report it as zero or claim complete accounting across
harnesses. Existing totals cover collected logs only. Missing logs and retained
ledger rows do not prove that all usage was collected.
