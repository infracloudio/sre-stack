---
title: Compact Spec Kit across every harness
type: chore
created: 2026-10-29
status: done
route: dispatch
baseline_commit: 9b7da95ca6b27db4106d80f59ab0f88b97774d88
context:
  - AGENTS.md
  - .specify/memory/constitution.md
---

<frozen-after-approval reason="User approved the proposal and actual upgrade on 2026-10-29">

## Intent

Make Spec Kit output manageable across Claude Code, Codex, OpenCode, and Devin.
Upgrade the repository to the installed, available Spec Kit 1.2.4.
Preserve story-cost posthooks and the project's existing SDLC protections.

## Boundaries and constraints

Keep current stories, their evidence, task IDs, approvals, and feature pointer unchanged.
Preserve real infrastructure research before specification (principle VIII), section-by-section authoring (IX), and bounded convergence (X).
Preserve independent approvals, required lint, protected paths, and all existing tests.
Keep BMAD, Loom emitters, infrastructure, cloud settings, and version pins outside this tooling upgrade unchanged.
Change the Spec Kit installer pin intentionally to 1.2.4; regenerate its artifacts through the CLI.
Do not deploy, run paid harnesses, create issues, commit, push, or change the global CLI installation.
This work is prepared on an isolated worktree, following the user's explicit approval.

## Acceptance criteria

- Given all four installed integrations, when refreshed, then metadata and installer pins agree on 1.2.4.
- Given any harness, when a Spec Kit command runs, then compact rules, required research, authoring approval, and convergence limits agree.
- Given a future story, when drafted, then three primary files target 400/600/600 words; research and evidence remain available when required.
- Given an existing story, when this upgrade is applied, then its files and recorded evidence stay unchanged.
- Given after_specify, after_tasks, after_analyze, after_implement, or after_converge, when the mandatory hook runs, then it executes make story-cost before command completion and reports totals and warnings.
- Given Codex or Devin, when their hooks run, then missing custom skill aliases do not prevent cost collection.
- Given unavailable Codex/Devin usage data, when a report is shown, then collection support is explicit and missing data is not represented as zero or complete accounting.
- Given a second regeneration, when checked, then project-owned instructions and all harness outputs remain consistent.
- Given offline tests and make lint, when executed, then their actual outputs and any limitations are recorded without weakening checks.

</frozen-after-approval>

## Code map

- `agent/spec-kit/`: create the project-owned compact preset, templates, shared instructions, and reproducible regeneration entry point.
- `.specify/extensions.yml`: preserve byte-for-byte; five mandatory story-cost posthooks already exist.
- `.specify/memory/constitution.md`: version 1.5.0; append compact guidance without replacing principles VIII–X.
- `AGENTS.md`, `docs/sdlc/framework.md`: update generated-source maintenance instructions and add a short compact-workflow reference.
- `agent/tools/story-cost.sh`: collector already supports Claude/OpenCode only. Preserve its parser and ledger behavior; clearly expose unavailable Codex/Devin accounting through shared instructions and reporting if necessary.
- `.claude/skills/story-cost/`, `.opencode/commands/story-cost.md`: existing entry points; preserve or regenerate from shared source; add matching Codex/Devin entry points if needed.
- `agent/tests/story-cost/run-tests.sh`: permanent fixture-based offline tests, initially 43 passing checks.
- `agent/tests/spec-kit/`: add permanent tests for resolution, all-harness parity, hook execution contract, required rules, upgrade/regeneration drift, and preserved stories.
- `makefile`: wire offline parity checks into existing make lint without dropping anything.
- `infra/scripts/dev/install-deps.sh`: SPEC_KIT_VERSION currently v1.0.4, intentionally bump to v1.2.4.
- `.specify/integration.json` and manifests: all four integrations have already been upgraded to 1.2.4 in this worktree through the CLI.
- Original instructions remain available through `git show HEAD:<path>`.

## Implementation notes

Use Spec Kit's supported preset mechanism, not manual edits to generated Spec Kit commands.
Preset install reconciles only the active integration. Activate each installed integration through the CLI to register the same preset; restore claude as the original default.
Use __SPECKIT_COMMAND_*__ placeholders for harness-native invocation syntax.
Preset registration prepends speckit- to custom skill names. Handle the existing command: story-cost hook by executing make story-cost directly through shared rules.
If creating manual story-cost entry points, generate all four from one project-owned source using a deterministic project script; keep existing behavior and retention guidance.
Treat output length as a target. Preserve acceptance criteria, required concrete examples, and real evidence. Do not truncate real command output.
Keep legacy requirement identifiers supported; do not force migration of old documents.
Plans retain reviewer-facing commands and actual paths; tasks start with Now and use stable IDs.
Prefer extending existing tooling with no new package dependencies.
All real harnesses execute LLM prompts: offline parity can verify generated content and shared hook execution, not guarantee identical model decisions. Document this limitation.

## Tasks and verification

- [x] Pin and regenerate Spec Kit 1.2.4 artifacts for every installed integration.
- [x] Create compact source prompts and templates preserving project rules and mandatory hooks.
- [x] Add a repeatable refresh/check path and permanent offline parity tests.
- [x] Preserve cost collection and expose the accounting support boundary honestly.
- [x] Update constitution and maintenance guidance; preserve current stories and unrelated skills.
- [x] Run make lint, story-cost tests, parity tests, and regeneration checks; inspect the final diff.

## Review notes

The original main checkout remains unchanged while this isolated worktree is verified.
No cloud research is required: the change affects repository tooling only.

## Review triage log

| Finding | Verdict | Evidence and route |
| --- | --- | --- |
| Blind 1: shell modes | high | Direct prerequisite execution exits 126; restore executable modes during refresh and test execution. Patch. |
| Blind 2: checklist before plan | medium | Prerequisites require plan.md although the new checklist prompt treats it as optional; use read-only path resolution and require the spec explicitly. Patch. |
| Blind 3: checklist ownership | high | New checklist prompt omits the reviewer-owned unchecked lifecycle; restore it to preserve the implementation gate. Patch. |
| Blind 4: feature-pointer cost attribution | false | AD-014 explicitly makes branch decide the story; collector and manual STORY override are unchanged. Changing attribution would violate the preserved accounting design. |
| Blind 5: hook configuration | medium | The dedicated posthook instruction is unconditional despite shared disabled/conditional rules. Make dispatch configuration-aware and test those existing states. Patch. |
| Blind 6: pointer schema | medium | Downstream get_feature_paths requires feature_directory; the compact specify prompt removed its exact example. Restore schema guidance. Patch. |
| Blind 7: analysis spec prerequisite | medium | Analysis lost --require-spec; restore the existing missing-spec gate. Patch. |
| Blind 8: analysis pointer writes | medium | get_feature_paths persists explicit directory overrides unless SPECIFY_FEATURE_NO_PERSIST=1. Set it for analysis. Patch. |
| Blind 9: refresh cleanup | medium | A failed final activation skips the preservation comparison. Use nested cleanup so both errors stay visible. Patch. |
| Blind 10: upgrade preservation test | medium | Existing tests refresh presets but never pass upgrade=True; exercise the advertised forced-upgrade route. Patch. |
| Verification 1: setup-plan failure coverage | medium | Tests do not execute empty or missing template behavior. Add permanent isolated tests for nonzero exit and no plan artifact. Patch. |
| Verification 2: shell modes | high | Independent execution reproduces permission denied; same patch as Blind 1. |
| Edge 1: shell modes | high | Same demonstrated permission failure; same patch as Blind 1. |
| Edge 2: hook configuration | medium | Same unconditional dispatch gap as Blind 5; include disabled, removed, optional and conditional hooks. |
| Edge 3: Unicode warning paths | low | Collector accepts Unicode story names; new runner's ASCII filter drops warning output. Match existing collector validation. Patch. |
| Edge 4: checklist ownership | high | Same omission as Blind 3; restore reviewer authorization and unchecked generation. |

The review patches retain the agreed scope. No existing infrastructure or accounting parser changes are required.

## Verification

Final make lint passes with 23 compact tests and all 43 existing cost checks. Four targeted template/regeneration checks pass after the final Now field expansion. All concrete review patches are applied; branch attribution is intentionally preserved under AD-014. Full evidence is in [compact-speckit-verification.md](compact-speckit-verification.md). Prepared changes remain uncommitted for human review.
