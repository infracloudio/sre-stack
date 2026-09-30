# Implementation Plan: Azure AKS Cluster Support

**Branch**: `f/097/add_aks_support` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-add-aks-support/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Add Azure Kubernetes Service (AKS) cluster provisioning alongside existing AWS EKS and local k3d infrastructure. The Makefile-driven lifecycle commands (`make setup`, `make cleanup`) will dynamically target the selected provider based on `.env` configuration. The implementation provisions an empty AKS cluster that mirrors EKS node pool architecture (four pools: app, persistent, observability, loadgen) with matching labels, taints, and compute sizing, without deploying any application or observability workloads. Existing AWS/EKS and k3d paths remain unchanged.

## Technical Context

**Language/Version**: bash/makefile (consistent with existing infra tooling)

**Primary Dependencies**: 
- Azure CLI (az) — cluster provisioning and resource management
- kubectl — cluster inspection, label/taint verification
- Terraform or Azure Resource Manager (ARM) templates — infrastructure definition (needs research for Azure SDK alignment)

**Storage**: N/A (empty cluster, no persistent volumes in this story)

**Testing**: 
- Azure Control Plane inspection (az aks commands)
- kubectl introspection (node labels, taints, capacity)
- Makefile output validation

**Target Platform**: 
- Azure cloud (prod/dev AKS clusters)
- Local development machines (CI runners, developer workstations)

**Project Type**: Infrastructure as Code / Orchestration (Makefile + shell + cloud provider SDKs)

**Performance Goals**: 
- Cluster provisioning completes within typical cloud bootstrapping timelines (15-30 min for AKS)
- Idempotent re-runs complete within seconds (no duplicate resource creation)

**Constraints**: 
- Strict idempotency: running setup/cleanup twice must be safe
- No secrets in `.env` — authentication comes from external CLI session or CI env vars
- Backward compatibility: existing AWS/k3d `.env` and behavior unchanged
- Node pool sizing must match or exceed EKS instance types (vCPU/memory match rule)

**Scale/Scope**: 
- Four node pools per cluster (fixed size matching EKS)
- Empty cluster (no workloads, 0 initial setup complexity for AKS-specific code)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **I. Re-runnable Scripts**: Spec requires idempotent cluster provisioning (FR-009), safe teardown (FR-007, FR-008), and no duplicate resources on re-run. Implementation scripts will check for existing AKS clusters/node pools before creating and handle already-provisioned state.

✅ **II. Pinned Versions**: Spec states "The Kubernetes version targeted for AKS is the closest available version to the version currently pinned for EKS at implementation time." This will be captured in `.env` as `AZURE_KUBERNETES_VERSION` and `.specify/memory/constitution.md` will document the requirement to pin.

✅ **III. One Configuration Surface**: Spec mandates `.env` hold all Azure settings (subscription, tenant, resource group, region, cluster naming) and provider selection (FR-001, FR-002). No inline values or separate config files. Existing AWS and local `.env` sections unchanged.

✅ **IV. No Secrets in Git**: Spec explicitly requires ".env MUST NOT hold Azure credential secrets; authentication comes from outside `.env`" (FR-002, FR-014). The Azure section holds only non-secret settings. Real credentials (service principal, managed identity) come from `az` CLI session or CI env vars.

✅ **V. Workload Placement Contract**: Spec requires AKS node pools carry same `workload=app|persistent|o11y|loadgen` labels, matching taints, and provide storage class `gp2` alias as EKS (FR-006), ensuring existing manifests deploy unchanged.

**Verdict**: All five constitution principles align with spec requirements. No violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/001-add-aks-support/
├── spec.md              # Feature specification
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

sre-stack is a Makefile-driven infrastructure provisioning repo. This feature modifies:

```text
makefile                          # Top-level lifecycle orchestration
.env                              # Configuration surface (adds Azure section)

infra/
├── eks/                          # AWS EKS provisioning scripts (unchanged)
│   ├── cluster.sh
│   ├── node-pools.sh
│   └── cleanup.sh
├── local/                        # k3d local provisioning scripts (unchanged)
│   └── ...
└── aks/                          # NEW: Azure AKS provisioning scripts
    ├── cluster.sh               # AKS cluster creation
    ├── node-pools.sh            # AKS node pool creation
    ├── storage-class.sh         # gp2 storage class alias
    └── cleanup.sh               # AKS resource teardown

app/                              # Application workloads (no changes in this story)
monitoring/                       # Observability stack (no changes in this story)
scenarios/                        # Fault scenarios (no changes in this story)
agent/                            # Policies and hooks (may add provider validation hook)
```

**Structure Decision**: Infra-as-Code orchestration repo using bash + Makefile. This feature adds a new `infra/aks/` directory with provider-specific scripts following the same pattern as existing `infra/eks/` and `infra/local/`. All provider selection and configuration happens in `makefile` and `.env`; no new application-level code.

## Complexity Tracking

No constitution violations. All five principles align with spec requirements.

---

## Phase 0: Research & Clarifications (COMPLETE)

**Output**: `research.md`

**Key Findings**:
- **Provisioning Tool**: Azure CLI + bash scripts (lightweight, idempotent, aligns with EKS pattern)
- **VM SKU Mapping**: Standard_Dv5 series (modern, Spot-capable, widely available)
  - app pool: Standard_D2s_v5 (2 vCPU, 8 GB)
  - persistent pool: Standard_D4s_v5 (4 vCPU, 16 GB)
  - observability pool: Standard_D4s_v5 (4 vCPU, 16 GB)
  - loadgen pool: Standard_D4s_v5 (4 vCPU, 16 GB)
- **Storage Class**: Custom Kubernetes StorageClass named `gp2` using Azure Disk CSI driver
- **Authentication**: Pre-authenticated `az` CLI session or CI-supplied env vars; no secrets in `.env`
- **Resource Scoping**: Dedicated resource group per cluster; atomic teardown via RG deletion

**No Further Clarifications Needed**: All NEEDS CLARIFICATION items resolved.

---

## Phase 1: Design & Contracts (COMPLETE)

**Outputs**:
- `data-model.md`: Entity definitions (CloudProvider, NodePool, KubernetesCluster, WorkloadPlacementContract)
- `contracts/provider-interface.md`: Provider abstraction interface (input/output contracts, idempotency rules, workload portability)
- `quickstart.md`: 8 end-to-end validation scenarios for testing

### Design Artifacts Summary

#### Data Model (`data-model.md`)
Defines four entities:
1. **CloudProvider**: Provider selection (EKS, k3d, AKS) and config
2. **NodePool**: Workload label, taint, min/max sizing, compute specs
3. **KubernetesCluster**: Aggregates provider + 4 node pools + storage class
4. **WorkloadPlacementContract**: Ensures manifest portability across providers

#### Provider Interface (`contracts/provider-interface.md`)
Contract all providers must implement:
- **Input**: `.env` configuration (provider-scoped variables)
- **Output**: Accessible kubeconfig, 4 node pools, labels, taints, `gp2` storage class
- **Idempotency**: Cluster scripts check before creating; cleanup checks before deleting
- **Workload Portability**: Manifests using `workload=` label + `gp2` StorageClass work on all providers

#### Quickstart Guide (`quickstart.md`)
8 runnable validation scenarios:
1. Provision empty AKS cluster
2. Verify no application workloads deployed
3. Verify StorageClass `gp2` exists
4. Test idempotent re-provisioning
5. Test cleanup & teardown
6. Test idempotent re-cleanup
7. Regression: EKS provisioning unchanged
8. Regression: k3d provisioning unchanged

### Constitution Check (Post-Design)

✅ **I. Re-runnable Scripts**: Idempotency rules baked into contract; all scripts check before create/delete.

✅ **II. Pinned Versions**: `.env` captures `AZURE_KUBERNETES_VERSION` (pinned to 1.27 or closest available).

✅ **III. One Configuration Surface**: All `.env` variables scoped to `AZURE_` prefix; no separate config files.

✅ **IV. No Secrets in Git**: Azure section holds only subscription, tenant, resource group, region; no credentials.

✅ **V. Workload Placement Contract**: All 4 node pools have identical labels, taints, storage class alias across EKS/k3d/AKS.

---

## Ready for Implementation

- [x] Phase 0 research complete; all clarifications resolved
- [x] Phase 1 design complete; data model, contracts, quickstart documented
- [x] Constitution check passed (pre- and post-design)
- [x] No violations; no complexity trades to justify
- [x] Next step: `/speckit-tasks` to break design into actionable work items for implementation
