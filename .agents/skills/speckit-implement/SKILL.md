---
name: speckit-implement
description: Implement the approved tasks and verify them.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
---

# Speckit Implement Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for implement; actually execute mandatory
hooks and wait, except story-cost after hooks: their sole dispatcher is the
runner below. Do not also invoke story-cost through generic hook dispatch.
No printed invocation substitutes for execution.

## Implement

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`.
Read spec, plan, tasks, research and applicable checklists. Confirm independent
plan approval before changes outside the story folder. Show incomplete
checklists and wait for the developer's decision before implementation.
Default to one acceptance slice (a coherent outcome plus its proving checks)
or an explicit task range per invocation. Honor a larger batch only when the
user requests it. Before editing, name the selected IDs, dependencies and
checks, and update tasks.md Now with the active range and any blocker.
Execute selected tasks in dependency order, tests first/alongside code where planned;
mark complete only with real verification. Use [P] tasks concurrently only
when allowed by repository instructions. Preserve protected paths and existing
tests. Record plan departures and reasons in plan.md with the change. Run
`make lint`, record actual output plus any failed or skipped verification in
story evidence; never invent successful output. Stop at blockers. Report done
IDs, changed paths, actual verification, blockers and updated Now with next
unfinished IDs. When tasks remain, report the next $speckit-implement
range and stop; suggest $speckit-converge only after all original
implementation tasks and required checks are complete.

Before returning (including blocked/partial runs), invoke the config-aware
runner exactly once and wait for
`bash agent/spec-kit/posthook.sh after_implement`. It skips missing, disabled or optional hooks and
defers nonempty conditions; malformed configuration fails visibly. Report totals,
warnings and unavailable accounting as required by the shared rules.

Report only decisions, changed paths, checks, blockers and the next step.
