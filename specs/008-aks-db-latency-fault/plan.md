# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

> **Work in progress, 2026-10-22.** Only Technical Context and Constitution Check are written, and both were approved before the research changed the approach. **Technical Context is out of date**: the CPU-limit lever, the in-place resize and the pod annotation marker described below were dropped (`research.md` Findings 8 and 9). The fault is now MySQL's Rewriter plugin adding a fixed sleep to the shipping and ratings statements; revert disables the rules and keeps the plugin installed (Finding 10, not yet written). The Constitution Check rows II, III and V stay open until the mechanism is written back. The remaining sections below are still the unfilled template.

## Technical Context

**Language/Version**: Bash 5 scripts (`GNU bash, version 5.2.21(1)-release`) called from GNU make targets. No application code changes; the shop runs upstream images.

**Primary Dependencies**:
- `kubectl` client `v1.33.4`, `helm` `v3.18.6`, `az` `2.91.0`, signed in to `Pune - Sandbox (TPM)`. AKS cluster `sre-stack-452138` (southindia, `Running`, 9 nodes Ready at `v1.34.11`) was already up when planning began.
- The database is the `mysql-0` pod in `robot-shop` (containers `mysql`, `mysql-exporter`, Istio sidecar). Only ratings and shipping are confirmed to use it (spec Assumptions).
- The mesh sidecars already on every shop pod and the Prometheus stack from `make setup-aks-o11y` supply the request-duration measurements FR-010 relies on. Which mechanism slows the database is an open Phase 0 question (see below), so no new dependency is named yet.

**Storage**: None. Whether the fault is on lives only in the cluster (no local state file), so anyone can run status or revert (EC-005). The exact marker is a Phase 0 decision.

**Testing**:
- No offline (fake-`kubectl`) tests, following the developer's decision on story 006 and re-confirmed on 007.
- Live on `sre-stack-452138`: start → status → revert → status, plus a database restart while the fault is on (SC-013), with the load generator running, timed against SC-001 to SC-008, SC-010, SC-012 and SC-013; output pasted into the PR.
- `make lint` for every change.

**Target Platform**: AKS only (`STACK_MODE=aks`, `.env:5`), namespace `robot-shop` (`.env:38`). EKS and k3d are out of scope.

**Project Type**: Operations glue: make targets calling one Azure-only script (new folder `infra/azure/scenario-03/`), plus guide text in `scenarios/README.md` and `docs/aks-explained.md` (FR-011, FR-014).

**Performance Goals**: Start shows slow answers within 60 s (SC-001). Revert is back to normal within 10 s, with dashboards recovered within 2 min (SC-004). Each command takes under 60 s including its own check (SC-006). Status takes under 10 s (SC-007).

**Constraints**:
- FR-012 / SC-011: no line changes in `scenarios/scenario-01/`, `scenario-02/`, `scenario-04/`. `makefile` and `.env` gain Azure-only lines only.
- Principle I: every command is safe to run twice (FR-004, SC-010).
- FR-003 / SC-013: the fault survives a restart of the database pod.
- FR-006 / SC-008: no data change. The slowdown must not write to the database.
- SC-012 / FR-013: a normal setup with the fault never started must not touch the live stack.
- SC-002: slow answers only, no errors. The delay must stay within the 2–10 s window.

**Scale/Scope**: One database pod, one namespace, one presenter at a time.

**Questions for Phase 0 (live on `sre-stack-452138`)**:
1. Which mechanism slows the database without data change or errors, survives a pod restart, and stays inside the 2–10 s window? The candidates are an Istio fault-injection delay on traffic to the database, a MySQL-side change, or network shaping.
2. Does the ratings or shipping path time out before 10 s, so that a delay produces errors and breaks SC-002?
3. What do the normal speeds actually measure for ratings and shipping today? (spec §3 quotes about 0.02 s and 0.4–0.9 s, from earlier work.)
4. Does `make setup-robot-shop` during an active fault clear it (EC-002, FR-013)?
5. How does status tell "our fault" from "slow for another reason" (EC-007, FR-009)?
6. Which installed dashboard panels show the rise (FR-010)?
7. Does anything besides ratings and shipping use MySQL (catalogue, user, cart)? The spec marks this unverified.

## Constitution Check

*Gate before Phase 0. Re-checked after Phase 1 design.*

| Principle | Status | Why |
|---|---|---|
| I. Re-runnable scripts | Pass | Start, revert and status are idempotent by FR-004 and SC-010. The script follows the pattern of `ratings-abort.sh` and `cart-oom-kill.sh`: resolve repo root, source `.env`, check before change. |
| II. Pinned versions | Open | No chart or image is named yet. If the mechanism needs a new image or chart, it is pinned and goes in `*/chart-values/`. Settled by the Phase 0 mechanism finding. |
| III. One configuration surface | Open | Any tunable (for example the delay length) goes in `.env`. The spec fixes the amount (Out of Scope), so the plan expects no new tunable. Confirmed after the mechanism is chosen. |
| IV. No secrets in git | Pass | No credential is added. The slowdown must not need the database password. If Phase 0 finds it does, this row changes. |
| V. Workload placement | Open | Applies only if the mechanism adds a pod or workload. It would then select a `workload=` pool and tolerate its taint. A mesh rule or a change to the existing database pod adds no new workload. |
| VI. Specs without technical detail | Pass | `spec.md` was checked against this at authoring. Technical content lives here. |
| VII. Plain language | Pass | Each plan section is written in plain words with an example. |
| VIII. Try it before you plan it | Pending | Phase 0 runs live on `sre-stack-452138`. Cluster access is already granted. No substitute is needed. |
| IX. Author in steps | Pass | This plan is being written one section at a time. |
| X. Converge to agreed scope | Not yet applicable | Applies at `/speckit-converge`. |

**Gate result**: no violation. No entry for the Complexity Tracking table.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
