---
description: "Task list for Azure Cluster Support"
---

# Tasks: Azure Cluster Support

**Input**: Design documents from `/specs/001-azure-aks-setup/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/azure-cli-contract.md, quickstart.md

**Tests**: Included, because the spec asks for them (FR-013): the offline stand-in `az` checks and the quickstart checks are explicit requirements, not extras.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own. The order the story owner demanded is encoded here: **manual try-out first, then scripts, then offline tests, then final checks** (plan.md, "How the work will be ordered").

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Every description carries exact file paths

## Path Conventions

- Cluster scripts: `infra/scripts/cluster/` (existing layout)
- Azure manifests: `infra/azure/` (new directory, mirrors `infra/local/`)
- Settings: `.env` (tracked, demo values only)
- Offline tests: `agent/tests/azure/` (next to the other conformance tests)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Settings surface ready before any command is written

- [x] T001 Add the Azure settings block to `.env`: extend the `STACK_MODE` comment on line 4 to `eks | local | aks`, and add `AZURE_SUBSCRIPTION_ID=` (empty demo value), `AZURE_LOCATION=` (empty demo value, comment documents the `eastus2` fallback), and `AKS_KUBERNETES_VERSION=` (empty placeholder, comment says the manual try-out fills it). Existing entries and their values stay untouched.

---

## Phase 2: Foundational (Manual Try-Out — Blocks All User Stories)

**Purpose**: The story owner's rule: prove every Azure command by hand, one at a time, before any script is written (plan.md ordering requirement; quickstart.md Part A).

**⚠️ CRITICAL**: No script may be written until this phase is complete. The findings feed `.env`, the helper, and the offline stand-in.

- [x] T002 Run the manual try-out, steps A1–A9, exactly as written in `specs/001-azure-aks-setup/quickstart.md` Part A, against real Azure (sign-in check, location and machine-size checks, group create/delete rehearsal, `az aks get-versions`, cluster + one spot pool with label and taint, read-back of output fields, gp2 apply via a temporary copy of `infra/local/gp2-storageclass.yaml`, teardown with the exact-name `MC_` check). Record every raw output.
- [x] T003 Fill the "Manual pass findings" section in `specs/001-azure-aks-setup/research.md`: tick every checkbox, write the chosen supported Kubernetes version from A4, the confirmed VM sizes from A2b, the real `az aks show` / `az aks nodepool list` JSON shapes from A7, and the observed `MC_<rg>_<cluster>_<location>` name from the A5–A9 window.
- [x] T004 Set `AKS_KUBERNETES_VERSION` in `.env` to the version confirmed in T003 (replaces the placeholder from T001).
- [x] T005 Create the shared helper `infra/scripts/cluster/azure-common.sh`: resolve repo root and source `.env`; validate `STACK_MODE` is one of `eks|local|aks` and refuse otherwise naming the three valid choices (FR-006); print the `az --version` and warn plainly when the CLI is older than the documented minimum (plan.md: 2.87.0); in order run the four pre-checks from `specs/001-azure-aks-setup/contracts/azure-cli-contract.md` §1 (signed in via `az account show`; subscription via `az account set`; location real via `az account list-locations`; all three VM sizes offered via `az vm list-skus --location <loc> --all`, refusing on the first missing size with no silent swap); build the generated names `resource group = <name>-aks-<code>` and `cluster = sre-stack-<code>` per `specs/001-azure-aks-setup/data-model.md` §2; export the names and location for callers. Every refusal prints what is wrong, what to do, and that nothing was created (contract §3 style).

**Checkpoint**: Manual try-out proven, findings recorded, version pinned, shared helper ready. Script writing may begin.

---

## Phase 2b: Amendment from PR 98 review (cost-first allowance check)

**Purpose**: The review asked for cost minimization as a guiding light (PR 98, comment on plan.md §64). Decision recorded as AD-002 (`docs/architectural-decisions.md`); FR-014 added to the spec. The check runs in the shared helper's pre-checks, before anything is created.

- [x] T023 Extend `infra/scripts/cluster/azure-common.sh` (T005 deliverable) with the allowance pre-check from `specs/001-azure-aks-setup/contracts/azure-cli-contract.md` §1: first confirm the real `az vm list-usage --location <loc> --output json` shape **by hand, with the story owner** (constitution VIII — the manual try-out did not cover this command), and record the field names in the "Manual pass findings" of `specs/001-azure-aks-setup/research.md`; then compute the needed vCPUs from the data-model §3 table (spot: 26 total; regular: 22 DSv5 + 4 FSv2 at minimum counts), pick `AZURE_POOL_MODE=spot` when the location's spot vCPU covers the whole shape, `regular` when every family's regular limit covers its need, refuse naming the short family (current, limit, what to do) before any create otherwise, and export `AZURE_POOL_MODE` plus the numbers used for the decision. Every path keeps the contract §3 refusal style and idempotency rules.

---

## Phase 2c: Amendment from story-owner review (permission pre-check)

**Purpose**: the story owner asked (2026-09-10) for one more pre-check: the
helper must prove the signed-in identity can actually create everything on
the chosen subscription — Owner, Contributor, or a custom role whose
permissions allow unrestricted writes, before anything is created.

- [x] T024 Extend `infra/scripts/cluster/azure-common.sh` (T005/T023
      deliverable) with the permission pre-check from
      `specs/001-azure-aks-setup/contracts/azure-cli-contract.md` §1: confirm
      the `az role assignment list --assignee … --include-groups` shape by
      hand first (constitution VIII; findings recorded in research.md),
      then pass only when an Owner or Contributor assignment covers the
      exact subscription (or `/`/parent management-group), or when a custom
      role's actions include `*`, `*/write`, or `Microsoft.ContainerService/*`
      (checked via `az role definition list`); refuse naming the signed-in
      identity and the fix otherwise — before anything is created. Computes
      `_azure_user` once and feeds it to the generated-name recipe; exports
      `AZURE_RBAC_ROLE`/`AZURE_RBAC_SCOPE`.

---

## Phase 3: User Story 1 — Stand up an empty Azure cluster (Priority: P1) 🎯 MVP

**Goal**: `STACK_MODE=aks` + signed-in Azure + `make setup-cluster` produces an empty cluster whose five pools match the table in `specs/001-azure-aks-setup/data-model.md` §3, plus the `gp2` StorageClass — and running it twice creates nothing new.

**Independent Test**: Select Azure in `.env`, sign in, run `make setup-cluster` once, run `bash infra/scripts/cluster/verify-cluster-aks.sh`, and see ✓ for the control plane and every pool; run `make setup-cluster` again and see "already exists" with nothing new created.

### Implementation for User Story 1

- [x] T006 [P] [US1] Create `infra/azure/gp2-storageclass.yaml` with exactly the fields from `specs/001-azure-aks-setup/data-model.md` §4: name `gp2`, provisioner `disk.csi.azure.com`, `StandardSSD_LRS`, `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Delete`, `allowVolumeExpansion: true` (same shape as `infra/local/gp2-storageclass.yaml`, pointed at Azure's driver).
- [x] T007 [US1] Create `infra/scripts/cluster/setup-cluster-aks.sh`: source `azure-common.sh`; then create idempotently, resource by resource — check each one by its exact name and create only what is missing (FR-003, FR-011): `az group exists` true skips only `az group create`; `az aks show` succeeding skips `az aks create` (cluster + system pool); each `az aks nodepool show` succeeding skips that pool's add; `kubectl get storageclass gp2` succeeding skips the apply. Build order stays: `az group create` → `az aks create` with the pinned version and the 1-node Standard_D2s_v5 system pool (no `--mode` argument — the initial pool is System by default, contract §1) → four `az aks nodepool add` calls for `app`, `persistent`, `o11y`, `loadgen` with counts/sizes/labels/taints/autoscaler exactly per the data-model §3 table and contract §1 creating section, and the spot flags from research.md §3 **only** when `AZURE_POOL_MODE=spot` (T023 decides; never mixed — FR-014, AD-002) → `az aks get-credentials --overwrite-existing` → `kubectl apply -f infra/azure/gp2-storageclass.yaml`; on any failure stop, print the partial-failure report from contract §3 (what was created so far, what was not, no automatic delete), and exit non-zero.
- [ ] T008 [US1] Edit `infra/scripts/cluster/setup-cluster.sh`: when `STACK_MODE=aks` hand over to `setup-cluster-aks.sh`; when `STACK_MODE` is neither `eks|local|aks` refuse with the valid-choices message (FR-006); the existing `eks` and `local` branches stay byte-identical (FR-007).
- [x] T009 [US1] Check the `makefile` `setup-cluster` target still reaches the right script for `aks` through the T008 dispatch; edit the makefile only if the dispatch needs it, and change nothing about the `eks`/`local` behaviour (plan.md lists the makefile as a touched file; the change must stay minimal).
- [x] T010 [US1] Create `infra/scripts/cluster/verify-cluster-aks.sh`: read-only (never calls create/update/delete); `az aks show` for `provisioningState: Succeeded` and `powerState.code: Running`; `az aks nodepool list` compared per pool against the data-model §3 table (name, count/min/max, vmSize, nodeLabels, nodeTaints — with the contract §1 spot-mode exception excluding Azure's auto taint `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`, and scaleSetPriority — `Spot` expected on the four workload pools when setup ran in spot mode, `null`/`Regular` when regular mode; the system pool is always `null`/`Regular` and never carries the spot auto-taint), confirm nothing beyond the expected namespaces and workloads exists (FR-008); print one plain `✓`/`✗` line per pool in the contract §1 style, e.g. `✓ app: 3 nodes, Standard_D2s_v5, label workload=app, regular — matches Amazon`.
- [x] T011 [P] [US1] Create the offline stand-in `agent/tests/azure/fake-az.sh` per contract §2: appends every full argument list to a log file, answers from a scenario file with JSON shaped like the real output recorded in T003, never touches the network.
- [x] T012 [US1] Create the runner `agent/tests/azure/run-offline-tests.sh` covering the US1 scenarios from contract §2: `happy` (create sequence in order), `already-there` (group, cluster, all five pools, and the StorageClass pre-exist → second run records zero create calls), `resume` (group, cluster, and `app` pool pre-exist → records only the three missing pool adds plus credentials and storage apply, never a group create, cluster create, or `app` add), `not-signed-in` (refusal text, nothing created after it), `bad-location` (refusal, nothing created), `missing-vm-size` (refusal names `Standard_F4s_v2`, no `group create` recorded), `spot-fits` (spot allowance covers 26 → every workload pool add recorded with the spot flags, system pool without), `spot-short` (spot below 26, regular per-family limits fit → same adds recorded without spot flags, no refusal), `no-room` (neither fits → refusal names the short family with its numbers, exit ≠ 0, no `group create` recorded), `partial` (stop + report names what exists, zero delete calls) — run with `STACK_MODE=aks` and the fake `az` first on PATH; the stand-in (T011) gets a `vm list-usage` answer per scenario from the field names recorded in T023.
- [ ] T013 [US1] Run `bash agent/tests/azure/run-offline-tests.sh` until all US1 scenarios pass; fix only the Azure scripts/stand-in, and update `specs/001-azure-aks-setup/contracts/azure-cli-contract.md` in the same commit if a command shape had to change; report the actual output.

**Checkpoint**: User Story 1 works alone: offline scenarios green; a real signed-in run creates the matching empty cluster and the verify report is the SC-004 evidence.

---

## Phase 4: User Story 2 — Remove everything afterwards (Priority: P2)

**Goal**: `make cleanup-cluster` with `STACK_MODE=aks` deletes the generated resource group (which takes the `MC_` node resource group with it), refuses safely when there is nothing to clean, and never touches anyone else's groups.

**Independent Test**: After a successful Azure setup, run `make cleanup-cluster` twice: first deletes the generated group, second says "nothing to clean" and exits 0; the exact-name `MC_` check comes back "gone".

### Implementation for User Story 2

- [ ] T014 [US2] Edit `infra/scripts/cluster/cleanup-cluster.sh`: when `STACK_MODE=aks` run the Azure cleanup — source `azure-common.sh`; if `az group exists` is false print "nothing to clean" and exit 0 (FR-004 case 2); delete only when the existing group name equals the generated name (`az group delete --name <generated> --yes`), never on mismatch; afterwards check the one exact predicted name `MC_<generated-rg>_<generated-cluster>_<location>` via `az group show` (never a `MC_*` prefix search — shared subscription, data-model §2) and if it still exists print a plain warning naming it plus `az group delete --name <that-exact-group> --yes`, and exit non-zero; refuse with the valid-choices message on any other `STACK_MODE`; the `eks`/`local` branches stay byte-identical.
- [ ] T015 [US2] Extend `agent/tests/azure/run-offline-tests.sh` with the US2 scenarios from contract §2: `cleanup-full` (exactly one `az group delete --yes` recorded), `cleanup-empty` (zero delete calls, exit 0), `mc-lingers` (warning names the one group, exit non-zero, no second delete call, and other people's `MC_` groups exist in the scenario while the script never issues any list/search over `MC_*`), plus `bad-provider` (`STACK_MODE=nonsense` refusal naming the three valid values, on both setup and cleanup paths).
- [ ] T016 [US2] Run `bash agent/tests/azure/run-offline-tests.sh` until all US1+US2 scenarios pass; keep the contract in sync if shapes changed; report the actual output.

**Checkpoint**: User Stories 1 AND 2 work independently; teardown leaves nothing behind and is provably safe on a shared subscription.

---

## Phase 5: User Story 3 — Existing setups are untouched (Priority: P3)

**Goal**: Amazon and local users see zero change: same `.env` entries, same commands, same behaviour.

**Independent Test**: `git diff` against the base branch shows no changed file under `infra/eksctl.yaml`, the eks/local scripts, `app/`, `monitoring/`, or `scenarios/`; a person with real Amazon access runs `make setup` and `make cleanup` and they behave exactly as before.

### Implementation for User Story 3

- [ ] T017 [US3] Run the untouched-files guard: `git diff --name-only` (merge-base with the base branch) and confirm zero entries under `infra/eksctl.yaml`, `infra/scripts/cluster/` eks/local logic other than the two dispatch edits (T008, T014), `app/`, `monitoring/`, `scenarios/`, and `infra/local/`; paste the file list into the story evidence; any unexpected entry is a bug to fix before proceeding.
- [ ] T018 [US3] Run `make lint` (hooks enabled, secrets, protected paths, ratchets, shell/YAML lint) and report its actual output; fix only Azure-side findings — never weaken a hook, allowlist, or check.
- [ ] T019 [US3] Hand the one real-run confirmation to a person with Amazon access (spec US3): they run `make setup` and `make cleanup` with `STACK_MODE=eks` as usual and confirm nothing changed; record their confirmation as story evidence. This step is manual and blocks story completion, not script writing.

**Checkpoint**: New Azure path works, old paths provably unchanged.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final acceptance evidence and documentation sync

- [ ] T020 Execute `specs/001-azure-aks-setup/quickstart.md` Part B end to end: B1 refusals (logged out, made-up subscription, made-up location, `STACK_MODE=nonsense`), B2 real run + second-run no-op + keep the verify report as the SC-004 evidence, B4 double cleanup + exact-name `MC_` "gone" check; attach all outputs as evidence (`evidence:attached`).
- [ ] T021 [P] Re-read `specs/001-azure-aks-setup/contracts/azure-cli-contract.md` against the finished scripts: every `az` command the scripts call is listed in §1, the stand-in scenarios in §2 match the runner, and any drift found is fixed in the same commit.
- [ ] T022 Final sweep: run `bash agent/tests/azure/run-offline-tests.sh` and `make lint` one last time, confirm every "Manual pass findings" checkbox in `specs/001-azure-aks-setup/research.md` is ticked, and confirm the quickstart "Done when" list is fully checked; report both outputs.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately.
- **Foundational (Phase 2)**: depends on Phase 1 — **BLOCKS all user stories**. The manual try-out (T002) is the story owner's hard requirement; scripts come after it.
- **User Story Dependencies**

- **US1 (Phase 3)**: depends on Phase 2. Within it: T006 ∥ T007–T010 scripts; offline stand-in (T011) needs the real JSON shapes from T003; T023 (Phase 2b) must finish before T007/T010/T012 are *executed*, because they consume `AZURE_POOL_MODE` — and T023 itself needs one hand-run of `az vm list-usage` with the story owner before it edits the helper (constitution VIII).
- **US2 (Phase 4)**: depends on Phase 3 (cleanup logic reuses `azure-common.sh` and the stand-in from US1).
- **US3 (Phase 5)**: depends on Phases 3–4 (the diff guard only means something once all code changes exist); T019 additionally needs a person with Amazon access.
- **Polish (Phase 6)**: depends on all user stories being complete.

### User Story Dependencies

- **US1 (Phase 3)**: can start after Phase 2 — no dependency on other stories.
- **US2 (P2)**: can start after US1 — shares the helper and test harness but is independently testable (teardown after its own setup).
- **US3 (P3)**: constrains rather than adds; its checks run last, against the finished diff.

### Within Each User Story

- Helper/manifest before scripts; scripts before offline tests (the plan's ordering rule); runner before "run until green".
- Story complete before moving to the next priority.

### Parallel Opportunities

- T006 (StorageClass) ∥ T007–T010 (scripts) — different files, no overlap.
- T011 (stand-in) can be written while T007–T010 are in review — different files.
- T021 (contract re-sync) ∥ T020 (quickstart Part B).
- US2 script work could overlap US1 test polish for two people, but the default is sequential by priority.

---

## Parallel Example: User Story 1

```bash
# Independent manifest (no dependency on the scripts):
Task: "Create infra/azure/gp2-storageclass.yaml"                          # T006

# Script work (sequential, same story):
Task: "Create infra/scripts/cluster/setup-cluster-aks.sh"                 # T007
Task: "Edit infra/scripts/cluster/setup-cluster.sh dispatch"              # T008
Task: "Create infra/scripts/cluster/verify-cluster-aks.sh"                # T010

# Offline stand-in can be built alongside the scripts:
Task: "Create agent/tests/azure/fake-az.sh"                               # T011
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: add the `.env` settings.
2. Phase 2: manual try-out → findings → pin → shared helper (hard gate).
3. Phase 3: scripts + offline tests for US1.
4. **STOP and VALIDATE**: real signed-in run + `verify-cluster-aks.sh` report (SC-004).
5. Demo ready — but note US2 immediately follows, because creation without teardown leaves paid machines running.

### Incremental Delivery

1. Setup + Foundational → approach proven by hand.
2. US1 → empty Azure cluster, verified → MVP.
3. US2 → one-command, leave-nothing teardown → safe to repeat daily.
4. US3 → proof the old paths never moved.
5. Polish → evidence attached, contract in sync.

### Single-Developer Path

All phases are strictly sequential as numbered (T001 → T022). Every [P] pair is an optimization, never a requirement.

---

## Notes

- [P] tasks = different files, no dependencies.
- [Story] label maps a task to its spec story for traceability.
- The manual try-out (T002) is not skippable: it is the story owner's explicit condition for writing any script.
- Cleanup (US2) exists because creation (US1) costs money the moment it succeeds — do not ship US1 alone and stop for long.
- `az group delete` cascades to the `MC_` node resource group by Azure's documented behaviour; the script only ever checks that group by its one exact predicted name.
- Nothing under `app/`, `monitoring/`, `scenarios/` is touched by any task here.
- Commit after each task or logical group; stop at any checkpoint to validate the story independently.
