---
description: Create compact tasks with stable IDs.
---


<!-- Source: sre-compact -->
## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for tasks; actually execute mandatory
hooks and wait, except story-cost after hooks: their sole dispatcher is the
runner below. Do not also invoke story-cost through generic hook dispatch.
No printed invocation substitutes for execution.

## Tasks

Run `.specify/scripts/bash/setup-tasks.sh --json`. Read FEATURE_DIR/spec.md,
plan.md, research.md and applicable supporting files. Use
TASKS_TEMPLATE_CONTENT from setup (or resolved tasks-template when absent).
Author one section at a time under principle IX. Start with Now: the next
unfinished work and its blocker. Keep checkbox tasks with stable T001-style
IDs, exact paths, requirement or acceptance references and dependencies.
Preserve all existing IDs and completion state; append without renumbering.
Cover every agreed requirement and named edge case with a proving check, and
include required lint. Mark [P] only for independent files/work; [US1] etc.
when relevant. Include just the needed implementation and verification tasks,
ordered by dependencies and user outcomes. No coverage-only or speculative
hardening tasks. Next: /speckit.analyze.

Before returning (including blocked/partial runs), invoke the config-aware
runner exactly once and wait for
`bash agent/spec-kit/posthook.sh after_tasks`. It skips missing, disabled or optional hooks and
defers nonempty conditions; malformed configuration fails visibly. Report totals,
warnings and unavailable accounting as required by the shared rules.

Report only decisions, changed paths, checks, blockers and the next step.