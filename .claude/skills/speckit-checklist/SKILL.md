---
name: speckit-checklist
description: Create a focused requirements-quality checklist.
argument-hint: "Domain or focus area for the checklist"
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
user-invocable: true
disable-model-invocation: false
---

# Speckit Checklist Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for checklist; actually execute mandatory
hooks and wait. No printed invocation substitutes for execution.

## Checklist

Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only`.
Explicitly check that FEATURE_SPEC exists; stop and request specification if
it is missing. Read the spec and plan when available; a plan is not required. Ask for checklist scope if unclear. Create a
focused checklist in FEATURE_DIR/checklists/<scope>.md; preserve existing
checklists rather than overwriting or resetting them. Use stable CHK IDs,
requirement references and clear yes/no questions about requirement quality:
completeness, clarity, consistency, measurable acceptance and agreed edges.
This checks the written requirements, not whether implementation works. Avoid
repeating requirements as generic questions. Generate unchecked `- [ ]` markers
only: checklist evaluation and checking items belong to the reviewer. Do not
evaluate, check off or reset items without an explicit reviewer request.
Report its path and open gaps.

Report only decisions, changed paths, checks, blockers and the next step.
