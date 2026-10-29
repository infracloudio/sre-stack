---
name: speckit-plan
description: Plan implementation from the approved specification.
argument-hint: "Optional guidance for the planning phase"
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
user-invocable: true
disable-model-invocation: false
---

# Speckit Plan Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for plan; actually execute mandatory
hooks and wait. No printed invocation substitutes for execution.

## Plan

Require independent spec approval and no unresolved clarification markers.
Run `.specify/scripts/bash/setup-plan.sh --json`; read FEATURE_SPEC, IMPL_PLAN,
FEATURE_DIR and research.md. Resolve plan-template through the preset stack.
Build on research already done during specification; do not replace it with a
fresh guessed research phase. Missing facts follow principle VIII and changes
to promised outcomes return for spec approval. Author one section at a time:
approach and reasons, actual changed paths, relevant technical context,
Constitution Check, dependencies, reviewer commands, risks and plan departures.
Recheck constitution after design; stop on unjustified violations. Supporting
data-model.md, contracts/ or quickstart.md are created only when needed.
Retain actual verification commands and paths. Next: /speckit-tasks
and /speckit-analyze, then independent plan approval.

Report only decisions, changed paths, checks, blockers and the next step.
