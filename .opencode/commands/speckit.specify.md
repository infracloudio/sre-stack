---
description: Create a compact feature specification.
---


<!-- Source: sre-compact -->
## Input and shared contract

Consider `$ARGUMENTS`. Before any action read `agent/spec-kit/rules.md` and
`agent/spec-kit/story-cost.md`, plus the constitution and AGENTS.md. Apply the
shared compact, research, section approval, convergence and hook rules in full.
Read the configured before/after hooks for specify; actually execute mandatory
hooks and wait, except story-cost after hooks: their sole dispatcher is the
runner below. Do not also invoke story-cost through generic hook dispatch.
No printed invocation substitutes for execution.

## Specify

Resolve the feature directory from explicit input, then .specify/feature.json
for an existing story; create only one new specs/<number>-<short-name>/ when
requested. Number from .specify/init-options.json (feature_numbering, with
legacy branch_numbering fallback) and existing directories. Branch creation
belongs to configured before_specify hooks, not an invented git operation.
Run research first under principle VIII, before writing any spec section.
Resolve `specify preset resolve spec-template` and use its content. Record a
new feature pointer in .specify/feature.json only when creating/selecting a
story for this command. Use the exact pointer schema, for example
`{"feature_directory":"specs/010-example"}`; replace only the example directory.
Author each section with the developer's approval.
Cover problem, outcome, out of scope, must keep working, prioritized user
scenarios with Given/When/Then acceptance examples, testable requirements,
measurable success criteria, named edge cases and assumptions. No technical
detail in spec.md. Keep at most three blocking clarification markers; do not
guess infrastructure facts. Validate quality in checklists/requirements.md;
resolve blockers through /speckit.clarify. Report readiness for
independent spec approval, never grant approval yourself.

Before returning (including blocked/partial runs), invoke the config-aware
runner exactly once and wait for
`bash agent/spec-kit/posthook.sh after_specify`. It skips missing, disabled or optional hooks and
defers nonempty conditions; malformed configuration fails visibly. Report totals,
warnings and unavailable accounting as required by the shared rules.

Report only decisions, changed paths, checks, blockers and the next step.