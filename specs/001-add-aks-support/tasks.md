# Tasks: Azure AKS Cluster Support

**Input**: Design documents from `/specs/001-add-aks-support/`

**Prerequisites**: 
- plan.md (implementation plan with technical decisions)
- spec.md (user stories and acceptance criteria)
- research.md (technology choices: Azure CLI, VM SKUs, storage class)
- data-model.md (CloudProvider, NodePool, KubernetesCluster entities)
- contracts/provider-interface.md (provider abstraction interface)
- quickstart.md (validation scenarios)

**Organization**: Tasks grouped by user story to enable independent implementation and testing. Three user stories from spec.md (P1, P2, P3); organized into 5 phases.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Include exact file paths

---

## Phase 1: Setup (Shared Infrastructure & Configuration)

**Purpose**: Project initialization; create `.env` Azure section and Makefile provider selection

**Duration**: 30 min (blocking prerequisite)

- [ ] T001 Add Azure configuration section to `.env` with template values (subscription, tenant, region, cluster name, K8s version)
- [ ] T002 [P] Document `.env` Azure variables in README or `.env.example`
- [ ] T003 [P] Add `CLOUD_PROVIDER` variable to `.env` with default value `eks`

**Checkpoint**: `.env` structure ready for all three providers (EKS, k3d, AKS)

---

## Phase 2: Foundational (Provider Abstraction & Directory Structure)

**Purpose**: Shared infrastructure for provider abstraction; establish Makefile-driven provider dispatch

**Duration**: 1 hour (blocks all user stories)

**⚠️ CRITICAL**: Phase 2 must complete before ANY user story work begins

### Provider Validation & Dispatch

- [ ] T004 Create provider validation function in Makefile or `infra/scripts/provider-check.sh` to validate `CLOUD_PROVIDER` and fail fast if invalid/missing
- [ ] T005 [P] Add `make start-cluster` target in Makefile that dispatches to provider-specific cluster provisioning script based on `CLOUD_PROVIDER`
- [ ] T006 [P] Add `make cleanup` target in Makefile that dispatches to provider-specific cleanup script based on `CLOUD_PROVIDER`
- [ ] T007 [P] Update existing `make setup` to call `make start-cluster` after provider dispatch (ensure EKS/k3d paths still work)

### Infrastructure Directory Structure

- [ ] T008 Create `infra/aks/` directory structure: `cluster.sh`, `node-pools.sh`, `storage-class.sh`, `cleanup.sh`
- [ ] T009 [P] Create stub versions of all AKS scripts with proper bash headers (#!/bin/bash, set -e, error handling, sourcing `.env`)
- [ ] T010 [P] Create `infra/scripts/azure-auth-check.sh` to validate Azure CLI authentication early and fail with clear error if not authenticated

### Common Infrastructure Scripts

- [ ] T011 Create `infra/scripts/provider-state.sh` to query current cluster state (exists/ready/not-provisioned) for idempotency checks
- [ ] T012 [P] Create `infra/scripts/get-kubeconfig.sh` to fetch and configure kubeconfig after cluster provisioning for all providers

**Checkpoint**: Provider dispatch in Makefile works; AKS directory exists with stub scripts; auth validation ready

---

## Phase 3: User Story 1 - Provision Empty AKS Cluster (P1) 🎯 MVP

**Goal**: Enable platform engineers to configure `.env` for Azure and provision a correctly-shaped, empty AKS cluster with four node pools (app, persistent, observability, loadgen) with matching labels, taints, and compute sizing.

**Priority**: P1 (primary requirement of this story)

**Independent Test**: Follow quickstart.md Scenario 1 (Provision Empty AKS Cluster) + Scenario 2 (Verify No Application Workloads)

### AKS Cluster Provisioning

- [ ] T013 Implement `infra/aks/cluster.sh` to create AKS cluster via `az aks create` with:
  - Resource group creation (from `AZURE_RESOURCE_GROUP`)
  - Cluster name, region, K8s version from `.env`
  - VNet/subnet management (AKS-managed)
  - Check for existing cluster before creating (idempotency)
  - Wait for cluster readiness with timeout
  - Exit 0 on success or "already exists"

- [ ] T014 Implement `infra/aks/node-pools.sh` to create four node pools via `az aks nodepool add`:
  - **app pool**: Standard_D2s_v5 (2 vCPU, 8 GB), min=3, max=6, label `workload=app`, no taint
  - **persistent pool**: Standard_D4s_v5 (4 vCPU, 16 GB), min=2, max=2, label `workload=persistent`, taint `persistent=true:NoSchedule`
  - **observability pool**: Standard_D4s_v5 (4 vCPU, 16 GB), min=2, max=3, label `workload=o11y`, taint `o11y=true:NoSchedule`
  - **loadgen pool**: Standard_D4s_v5 (4 vCPU, 16 GB), min=1, max=1, label `workload=loadgen`, taint `loadgen=true:NoSchedule`
  - Check for existing node pools before creating (idempotency)
  - Wait for each pool readiness with timeout
  - Exit 0 on success or "already exists"

- [ ] T015 Implement `infra/aks/storage-class.sh` to deploy custom StorageClass named `gp2`:
  - Create Kubernetes StorageClass manifest with provisioner `disk.csi.azure.com`
  - Use `Premium_LRS` disk type (or `StandardSSD_LRS` for cost variant)
  - Apply manifest via `kubectl apply` after cluster is ready
  - Idempotent: check if StorageClass exists before applying
  - Exit 0 on success

- [ ] T016 Update `infra/aks/cluster.sh` to call `infra/scripts/get-kubeconfig.sh` after cluster creation to fetch credentials and configure kubectl context

### Error Handling & Validation

- [ ] T017 [P] Add validation in `infra/aks/cluster.sh` and `node-pools.sh` to check Azure quotas and region availability before provisioning
- [ ] T018 [P] Add clear error messages in all AKS scripts (file paths, variable names, troubleshooting hints)

### Integration with Makefile

- [ ] T019 Update Makefile `start-cluster` target to call `infra/aks/cluster.sh` and `infra/aks/node-pools.sh` and `infra/aks/storage-class.sh` when `CLOUD_PROVIDER=aks`
- [ ] T020 Verify `make start-cluster` works end-to-end for AKS (test with valid `.env` credentials)

### Verification Tasks

- [ ] T021 Add verification step after US1 provisioning: run quickstart.md Scenarios 1-2 to validate cluster structure and empty state
- [ ] T022 Document expected node pool sizes in comments within `infra/aks/node-pools.sh` referencing research.md VM SKU mapping

**Checkpoint**: `make start-cluster` with `CLOUD_PROVIDER=aks` provisions empty, correctly-shaped AKS cluster with four node pools, labels, taints, and storage class alias. Meets FR-001 through FR-010 (except teardown, which is US2).

---

## Phase 4: User Story 2 - Tear Down AKS Infrastructure Cleanly (P2)

**Goal**: Enable platform engineers to run `make cleanup` and ensure every Azure resource created by provisioning is removed with no manual follow-up or leftover billable resources.

**Priority**: P2 (cost control and re-runnability depend on complete teardown)

**Independent Test**: Follow quickstart.md Scenarios 5-6 (Cleanup & Teardown, then Re-run Cleanup)

### AKS Cleanup Implementation

- [ ] T023 Implement `infra/aks/cleanup.sh` to delete AKS cluster and all supporting resources:
  - Check if cluster exists before attempting deletion (idempotency)
  - Delete cluster via `az aks delete` (this cascades to node pools, managed disks, etc.)
  - Delete resource group via `az group delete` if scoped per cluster (atomic deletion)
  - Wait for deletion to complete with timeout
  - Exit 0 on success or "cluster/resources do not exist"
  - Exit non-zero only if deletion fails on existing resources

- [ ] T024 Add safeguards in `infra/aks/cleanup.sh`:
  - Require explicit confirmation before deleting (or set `--yes` flag in `az` commands)
  - Double-check cluster name matches `AZURE_CLUSTER_NAME` to prevent accidental deletions
  - Log deletion steps for auditability

### Integration with Makefile

- [ ] T025 Update Makefile `cleanup` target to call `infra/aks/cleanup.sh` when `CLOUD_PROVIDER=aks`
- [ ] T026 Verify `make cleanup` works end-to-end for AKS (test deletion and verify no resources remain)

### Verification Tasks

- [ ] T027 Add verification step after US2 cleanup: run quickstart.md Scenario 5 (verify cluster deleted) and Scenario 6 (re-run cleanup is safe)
- [ ] T028 Document cleanup expectations and cost impact in README

**Checkpoint**: `make cleanup` with `CLOUD_PROVIDER=aks` removes all Azure resources. Meets FR-007, FR-008 (teardown idempotency).

---

## Phase 5: User Story 3 - Regression Testing (Existing AWS and Local Workflows) (P3)

**Goal**: Verify that existing AWS/EKS and local k3d provisioning workflows remain unchanged and function identically to pre-change behavior.

**Priority**: P3 (non-regression guarantee; without this, change is unsafe to merge)

**Independent Test**: Follow quickstart.md Scenarios 7-8 (EKS Regression, k3d Regression)

### EKS Regression Tests

- [ ] T029 Verify Makefile `start-cluster` works for EKS when `CLOUD_PROVIDER=eks`:
  - EKS cluster provisioning calls existing `infra/eksctl.yaml` flow unchanged
  - Node groups created: app-ng, persistent-ng, observability-ng, loadgen-ng
  - Node labels and taints match expected values
  - Kubeconfig accessible
  - Document: infra/eksctl.yaml unchanged, no modifications to EKS flow

- [ ] T030 Verify Makefile `cleanup` works for EKS when `CLOUD_PROVIDER=eks`:
  - EKS cluster teardown uses existing eksctl delete flow unchanged
  - All resources removed, no orphans
  - Document: EKS cleanup unchanged

- [ ] T031 Run full end-to-end EKS test (quickstart.md Scenario 7):
  - Provision EKS cluster
  - Verify 4 node pools exist with correct labels/taints
  - Verify `gp2` StorageClass exists
  - Clean up cluster
  - Verify no resources remain

### Local k3d Regression Tests

- [ ] T032 Verify Makefile `setup-local` works when `CLOUD_PROVIDER=local`:
  - k3d cluster provisioning unchanged
  - k3d nodes created with correct labels
  - Kubeconfig accessible
  - Document: k3d setup flow unchanged

- [ ] T033 Verify Makefile `cleanup-local` works when `CLOUD_PROVIDER=local`:
  - k3d cluster teardown unchanged
  - k3d cluster deleted cleanly
  - Document: k3d cleanup unchanged

- [ ] T034 Run full end-to-end k3d test (quickstart.md Scenario 8):
  - Provision k3d cluster
  - Verify nodes with workload labels
  - Verify `gp2` StorageClass or equivalent
  - Clean up cluster
  - Verify no resources remain

### `.env` Backward Compatibility

- [ ] T035 Verify `.env` AWS section unchanged:
  - All existing AWS variables (AWS_REGION, CLUSTER_NAME, etc.) unchanged
  - Existing `.env` file with AWS config still works (no breaking changes to variable names/defaults)
  - Document: AWS variables preserved, defaults unchanged

- [ ] T036 Verify `.env` local section unchanged:
  - All existing local variables (LOCAL_NODES, etc.) unchanged
  - Existing `.env` file with local config still works
  - Document: Local variables preserved

- [ ] T037 Verify default `.env` CLOUD_PROVIDER value:
  - Default `CLOUD_PROVIDER=eks` ensures backward compatibility
  - Existing scripts/CI that don't set CLOUD_PROVIDER still default to EKS (current behavior)

### Regression Documentation

- [ ] T038 Document `.env` backward compatibility in README or `.env.example`
- [ ] T039 Document that US1 (AKS provisioning) and US2 (AKS cleanup) are independent from AWS and local flows

**Checkpoint**: All existing AWS/EKS and local k3d workflows verified unchanged. Meets FR-012 (non-regression guarantee). Ready to merge.

---

## Phase 6: Integration, Validation & Documentation

**Purpose**: Cross-cutting concerns, documentation, final validation

- [ ] T040 [P] Run `make lint` to verify all scripts pass linting (bash syntax, YAML validation, shell best practices)
- [ ] T041 [P] Run all quickstart.md scenarios (S1-S8) end-to-end:
  - AKS provisioning, verification, idempotency, cleanup (S1-S6)
  - EKS regression test (S7)
  - k3d regression test (S8)
  - Document results in PR evidence attachment

- [ ] T042 [P] Update project documentation:
  - Add AKS section to README with prerequisites (Azure CLI, subscription, auth)
  - Update AGENTS.md if provider dispatch logic needs documentation
  - Add `.env` example for Azure section to `.env.example`

- [ ] T043 [P] Verify Constitution compliance:
  - I. Re-runnable Scripts: All AKS scripts check before create/delete ✅
  - II. Pinned Versions: `AZURE_KUBERNETES_VERSION` in `.env` ✅
  - III. One Config Surface: All `.env` variables prefixed `AZURE_` ✅
  - IV. No Secrets in Git: No credentials in `.env` or code ✅
  - V. Workload Contract: Node pools have identical labels/taints/storage across providers ✅

- [ ] T044 [P] Code review & cleanup:
  - All scripts follow existing code style (bash conventions, error handling)
  - Comments document "why" for non-obvious decisions (e.g., Standard_Dv5 SKU choice)
  - Remove debug/test code
  - Verify file paths and variable names are consistent

- [ ] T045 [P] Edge case testing:
  - Test with missing `.env` Azure variables → fail fast with clear error
  - Test with invalid `CLOUD_PROVIDER` value → fail fast with clear error
  - Test cluster provisioning twice in a row → second run completes quickly (idempotency)
  - Test cleanup when cluster already deleted → exits cleanly (idempotency)
  - Test partial AKS provisioning (e.g., cluster created, but node pools fail) → subsequent run completes remaining pools

- [ ] T046 [P] Update `.specify/memory/constitution.md` if needed (probably no changes; just verify alignment)

**Checkpoint**: All tests pass, documentation complete, code ready for PR review.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately (~30 min)
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories (~1 hour)
- **User Story 1 (Phase 3, P1)**: Depends on Foundational completion - AKS provisioning (~3-4 hours)
- **User Story 2 (Phase 4, P2)**: Depends on Foundational completion; can start after US1 is working - AKS cleanup (~1 hour)
- **User Story 3 (Phase 5, P3)**: Depends on Foundational completion; can start after US1/US2 - Regression testing (~2 hours)
- **Integration & Validation (Phase 6)**: Depends on all user stories - Final verification & documentation (~1-2 hours)

### User Story Dependencies

- **US1 (Provision AKS)**: Independent after Foundational
- **US2 (Cleanup AKS)**: Independent after Foundational; benefits from US1 being complete (can test against real cluster)
- **US3 (Regression)**: Independent after Foundational; should run after US1/US2 to validate non-regression

### Within Each User Story

- Cluster provisioning before node pool provisioning
- Node pool provisioning before storage class provisioning
- All provisioning before verification tests

### Parallel Opportunities

- **Phase 1 (Setup)**:
  - T002, T003 can run in parallel with T001
  
- **Phase 2 (Foundational)**:
  - T004 (provider dispatch) can start immediately
  - T005-T007 can run in parallel once T004 is roughed out
  - T008-T012 (directory structure & scripts) can run in parallel

- **Phase 3 (US1)**:
  - T017, T018 (validation & error handling) can run in parallel with T013-T016

- **Phase 6 (Integration)**:
  - T040-T046 can run in parallel (different concerns)

---

## Parallel Example: Team of Two Developers

**Developer A (Infra Focus)**:
1. Phases 1-2: Setup & Foundational (~2 hours)
2. Phase 3 (US1): AKS provisioning (~3-4 hours)
3. Phase 6: Integration & validation (~1 hour)

**Developer B (Validation Focus)**:
1. Wait for Developer A to complete Foundational
2. Phase 5 (US3): Regression testing (~2 hours) - can start in parallel with Dev A's US1
3. Phase 6: Testing & documentation (~1 hour)

Or sequentially:
1. Dev A & B together: Phases 1-2 (Setup & Foundational)
2. Dev A: Phase 3 (US1 AKS provisioning)
3. Dev B: Phase 5 (US3 regression testing in parallel)
4. Dev B (or whoever finishes first): Phase 4 (US2 cleanup)
5. Both: Phase 6 (integration & validation)

---

## Implementation Strategy

### MVP Scope (User Story 1 Only)

**Stop After**: Phase 3 (US1 provisioning complete)

**What Works**: Platform engineers can provision empty AKS clusters with correct node pool structure. Meets FR-001 through FR-010.

**Timeline**: ~5-6 hours (1-2 days with overhead)

**Deliverable**: `make start-cluster` with `CLOUD_PROVIDER=aks` works; AKS clusters provisioned correctly.

### Full Scope (All User Stories)

**Complete**: Phases 1-6 (all three user stories + regression + integration)

**What Works**: 
- Provision AKS clusters (US1)
- Clean up AKS clusters (US2)
- Existing AWS/k3d workflows unchanged (US3)

**Timeline**: ~10-12 hours (2-3 days with overhead)

**Deliverable**: Full AKS support with backward compatibility; ready to merge and deploy.

### Recommended Approach

1. **Day 1 Morning**: Complete Phases 1-2 (Setup & Foundational) as a team
2. **Day 1 Afternoon**: Implement Phase 3 (US1 AKS provisioning); test thoroughly
3. **Day 2 Morning**: Implement Phase 4 (US2 cleanup) and Phase 5 (US3 regression testing) in parallel
4. **Day 2 Afternoon**: Complete Phase 6 (integration & validation); run full test suite
5. **Day 2 EOD**: Ready for code review and merge

---

## Task Execution Checklist

### Before Starting

- [ ] Clone branch `f/097/add_aks_support`
- [ ] Read specs/001-add-aks-support/spec.md (requirements)
- [ ] Read specs/001-add-aks-support/plan.md (technical decisions)
- [ ] Read specs/001-add-aks-support/research.md (VM SKU choices, auth model)
- [ ] Read specs/001-add-aks-support/contracts/provider-interface.md (idempotency contract)
- [ ] Verify Azure CLI ≥2.87.0 installed and authenticated

### Phase 1: After Setup tasks

- [ ] `.env` has CLOUD_PROVIDER variable
- [ ] `.env` has AZURE_* section template
- [ ] Make hooks enabled (`make hooks`)

### Phase 2: After Foundational tasks

- [ ] `make start-cluster` target exists and dispatches by provider
- [ ] `make cleanup` target exists and dispatches by provider
- [ ] Provider validation fails fast for invalid CLOUD_PROVIDER
- [ ] `infra/aks/` directory exists with 4 stub scripts
- [ ] Azure auth check works

### Phase 3: After User Story 1

- [ ] `make start-cluster` with CLOUD_PROVIDER=aks provisions AKS cluster
- [ ] Four node pools created with correct sizing, labels, taints
- [ ] StorageClass `gp2` exists and is usable
- [ ] Quickstart.md Scenarios 1-2 pass
- [ ] Idempotency: `make start-cluster` twice completes quickly second time

### Phase 4: After User Story 2

- [ ] `make cleanup` with CLOUD_PROVIDER=aks deletes all resources
- [ ] Quickstart.md Scenarios 5-6 pass
- [ ] Idempotency: `make cleanup` twice exits cleanly second time

### Phase 5: After User Story 3

- [ ] `make start-cluster` with CLOUD_PROVIDER=eks still works (unchanged)
- [ ] `make cleanup` with CLOUD_PROVIDER=eks still works (unchanged)
- [ ] `make setup-local` still works (unchanged)
- [ ] Quickstart.md Scenarios 7-8 pass

### Phase 6: After Integration

- [ ] `make lint` passes
- [ ] All quickstart.md scenarios pass (1-8)
- [ ] Code reviewed and cleaned
- [ ] Constitution compliance verified
- [ ] `.env` backward compatibility confirmed
- [ ] Documentation updated
- [ ] Ready for PR and merge

---

## Notes

- **Tests**: No unit/integration tests are included in this task list (spec does not request tests). Validation is via quickstart.md scenarios and manual verification of cluster state.
- **Commits**: Create one commit per task or logical group. Use clear commit messages referencing the task IDs (e.g., "T013: Implement infra/aks/cluster.sh").
- **Code Review**: Each phase should be reviewed before proceeding to the next (e.g., review Foundational before starting US1).
- **Edge Cases**: Address edge cases from spec.md (missing variables, invalid provider, partial provisioning, missing auth).
- **Cost Control**: Cleanup must be rigorous; test cleanup thoroughly before declaring task complete.
- **Idempotency**: Every provisioning task must be tested twice in a row to ensure idempotency (second run should be fast/no-op).

---

## Done When

- [ ] All 46 tasks completed and verified
- [ ] All quickstart.md scenarios pass (S1-S8)
- [ ] `make lint` passes
- [ ] Constitution compliance confirmed
- [ ] All three providers work (EKS, k3d, AKS)
- [ ] Code reviewed and merged to main
- [ ] Ready for deployment
