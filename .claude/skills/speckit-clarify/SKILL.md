---
name: speckit-clarify
description: Resolve the important open questions in an existing specification.
argument-hint: "Optional areas to clarify in the spec"
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
user-invocable: true
disable-model-invocation: false
---

# Speckit Clarify Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for clarify; actually execute mandatory
hooks and wait. No printed invocation substitutes for execution.

## Clarify

Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` and
read the current spec, research and constitution. Identify consequential gaps
in outcomes, boundaries, acceptance and assumptions. Ask one question at a
time, with a short recommendation and meaningful alternatives; at most five
questions per invocation. Wait for the developer's answer; do not invent it.
Record each agreed answer in the relevant spec section and a brief
clarification note. Changes to approved promises return to the independent
Architect for approval; authoring changes follow principle IX. No unresolved
[NEEDS CLARIFICATION] may remain at spec approval. Report remaining blockers
and readiness for /speckit-plan.

Report only decisions, changed paths, checks, blockers and the next step.
