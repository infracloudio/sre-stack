---
name: speckit-converge
description: Confirm the implementation meets the agreed scope once.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
user-invocable: true
disable-model-invocation: false
---

# Speckit Converge Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for converge; actually execute mandatory
hooks and wait, except story-cost after hooks: their sole dispatcher is the
runner below. Do not also invoke story-cost through generic hook dispatch.
No printed invocation substitutes for execution.

## Converge

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`.
Read spec, plan, tasks, constitution, branch diff and real verification.
Require implementation tasks complete before convergence. Apply principle X:
trace findings to agreement and keep the approved Edge Cases list closed.
Append only CRITICAL/HIGH agreed-scope tasks, using new stable IDs and recording
source, path and proving check. There is one round: append, implement through
/speckit-implement, confirm. Record the round in tasks.md so another
invocation cannot restart it. If confirmation finds CRITICAL/HIGH gaps, stop
and request a new story; do not append a second round. MEDIUM/LOW go in a
follow-up summary, with no issue creation unless authorized. Do not create
tasks for coverage alone. Preserve every existing check. Say Converged only
when agreed conditions and required verification pass; otherwise name blockers.

Before returning (including blocked/partial runs), invoke the config-aware
runner exactly once and wait for
`bash agent/spec-kit/posthook.sh after_converge`. It skips missing, disabled or optional hooks and
defers nonempty conditions; malformed configuration fails visibly. Report totals,
warnings and unavailable accounting as required by the shared rules.

Report only decisions, changed paths, checks, blockers and the next step.
