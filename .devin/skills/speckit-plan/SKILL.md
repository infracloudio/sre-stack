---
name: "speckit-plan"
description: "Execute the implementation planning workflow using the plan template to generate design artifacts."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/plan.md"
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before planning)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_plan` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Re-evaluate Constitution Check post-design

## Phase 0 Research — REQUIRED (sre-stack)

**`research.md` is written from a live run, not from memory or documentation.**

`.specify/memory/constitution.md` principle VIII: research for any story touching running infrastructure runs against the real cluster, the real subscription, or the live chart repository. That is the requirement, not the ideal case.

Rules, in order of how often they are broken:

1. **Paste terminal output verbatim.** Never write an output block from memory, from documentation, or from what you expect the command to print. Never label a block "simulated", "expected", or "illustrative". An invented output block is a false claim — it is worse than leaving the question open, because it makes a wrong answer look checked.
2. **Record failures.** Errors, quirks and surprises belong in `research.md` next to the facts they qualify. A research document with no failures in it usually means no commands were run.
3. **If you cannot reach the cluster or subscription, stop and ask for access.** Say what you need — subscription, role, credentials, quota — and who you are asking. Then wait. Do not proceed and fill the gap from memory. A blocked story is an honest state; report it.
4. **Substitutes need permission, not just a reason.** `--dry-run`, `helm template`, `helm search`, sandbox or read-only queries are allowed only after access was asked for and could not be granted in the story's timebox. Record who was asked, what came back, which substitute you used, and what it cannot prove. The Architect approves the substitute at the plan gate; it is not yours to decide alone, and the limitation goes in the pull request.
5. **Cheap checks never qualify for a substitute.** A chart version, a chart name, a make target, a file path, a label or a taint is settled by one command against the real source, and must be:

   - `helm search repo <chart> --versions` — before pinning any chart version
   - `helm show chart <repo>/<chart> --version <v>` — before naming a chart that must exist
   - `grep -n "^<target>" makefile` — before writing "modify the existing <target> target"
   - `ls <dir>` — before referencing a path
   - the story's own `data-model.md` and `docs/architectural-decisions.md` — before asserting a label, taint or placement rule

   None of these need a cluster, cost anything, or take longer than a minute. There is no acceptable reason to guess at them.

Propose research findings one at a time, same loop as the section below: propose, stop, wait for the developer to question or approve.

---

## Incremental Authoring — REQUIRED (sre-stack)

**This overrides any instruction above to produce `plan.md` in a single pass.**

`.specify/memory/constitution.md` principle IX requires that `plan.md` be written one section at a time, with the developer approving each section before the next is started.

Sections, in order: Technical Context → Constitution Check → Phase 0 research findings (one finding at a time, real command output attached, per principle VIII) → Phase 1 design outputs → files to change → verification strategy.

Before writing a version pin, a file path, or a build target into any section, verify it exists. `helm search repo <chart> --versions` for a chart version, `grep -n "^<target>" makefile` for a make target, `ls` for a directory. Paste what the command printed. If you did not run it, do not assert it.

For each section, in order:

1. **Propose it.** Write that section only. Say in one or two plain sentences what it decides and why, and name what you checked to know it is true — the command you ran, the file and line you read. An unverified claim is marked open, not written as fact.
2. **Stop.** Do not begin the next section. Do not write the rest of the file "for context". End your turn.
3. **Wait for the developer**, who will do one of three things: ask a question, give a different instruction, or approve. Only on approval do you move to the next section.

Carry approved wording forward unchanged. Do not reopen an approved section without saying why.

You are proposing; the developer is accepting. Never present a whole finished file as the output of this command.

If the developer explicitly asks for the whole file in one pass, say once that this repo's constitution asks for section-by-section, then do as they ask.

---

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_plan`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_plan` key.
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue to the Completion Report.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Mandatory hook** (`optional: false`) — **You MUST emit `EXECUTE_COMMAND:` for each mandatory hook**:
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```

## Completion Report

Command ends after Phase 1 design. Report branch, IMPL_PLAN path, and generated artifacts.

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Define interface contracts** (if project has external interfaces) → `/contracts/`:
   - Identify what interfaces the project exposes to users or other systems
   - Document the contract format appropriate for the project type
   - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
   - Skip if project is purely internal (build scripts, one-off tools, etc.)

3. **Create quickstart validation guide** → `quickstart.md`:
   - Document runnable validation scenarios that prove the feature works end-to-end
   - Include prerequisites, setup commands, test/run commands, and expected outcomes
   - Use links or references to contracts and data model details instead of duplicating them
   - Do not include full implementation code, model/service/controller bodies, migrations, or complete test suites
   - Keep this artifact as a validation/run guide; implementation details belong in `tasks.md` and the implementation phase

**Output**: data-model.md, /contracts/*, quickstart.md

## Key rules

- Use absolute paths for filesystem operations; use project-relative paths for references in documentation
- ERROR on gate failures or unresolved clarifications

## Done When

- [ ] Plan workflow executed and design artifacts generated
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with branch, plan path, and generated artifacts
