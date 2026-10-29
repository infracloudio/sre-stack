---
name: speckit-analyze
description: Check agreement among specification, plan and tasks.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
---

# Speckit Analyze Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for analyze; actually execute mandatory
hooks and wait, except story-cost after hooks: their sole dispatcher is the
runner below. Do not also invoke story-cost through generic hook dispatch.
No printed invocation substitutes for execution.

## Analyze

Run `SPECIFY_FEATURE_NO_PERSIST=1 .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks`.
Read spec.md, plan.md, tasks.md, research and constitution. This is read-only:
do not rewrite artifacts, modify task state or persist the feature pointer.
The configured cost ledger posthook is the intentional separate side effect. Check requirement and acceptance
coverage, ambiguous or contradictory promises, dependencies, constitution
violations and ungrounded facts. Respect legacy requirement IDs. Report only
findings with severity, file/section, agreed source and a concrete remedy;
include a compact coverage summary and blockers to plan approval. Do not
interpret coverage gaps as permission to expand scope. Ask before any repair.
Next: independent plan approval before $speckit-implement.

Before returning (including blocked/partial runs), invoke the config-aware
runner exactly once and wait for
`bash agent/spec-kit/posthook.sh after_analyze`. It skips missing, disabled or optional hooks and
defers nonempty conditions; malformed configuration fails visibly. Report totals,
warnings and unavailable accounting as required by the shared rules.

Report only decisions, changed paths, checks, blockers and the next step.
