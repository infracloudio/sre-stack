---
name: speckit-taskstoissues
description: Turn approved tasks into issues when explicitly authorized.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:sre-compact
---

# Speckit Taskstoissues Skill

## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for taskstoissues; actually execute mandatory
hooks and wait. No printed invocation substitutes for execution.

## Taskstoissues

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`.
Read tasks.md, spec.md and plan.md. Check the git remote and intended issue
repository match. Show the proposed mapping with stable task IDs, dependencies
and acceptance checks. Creating issues requires explicit user authorization;
without it stop at this reviewable proposal. Never create issues in a different
repository or duplicate existing linked issues. Preserve task IDs and record
created issue links only after successful authorized creation. Report actual
created links, failures and unchanged tasks.

Report only decisions, changed paths, checks, blockers and the next step.
