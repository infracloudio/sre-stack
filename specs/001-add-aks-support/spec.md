# Feature Specification: Azure AKS Cluster Support

**Feature Branch**: `f/097/add_aks_support`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Extend the Makefile-driven infrastructure lifecycle (currently AWS EKS and local k3d) to also stand up an empty Azure Kubernetes Service (AKS) cluster that mirrors the existing EKS node pool architecture, node labels, and compute sizing. `make setup` must dynamically target EKS or AKS based on `.env` configuration; a new `make start-cluster` target provisions/starts the chosen cluster; `make cleanup` tears down whatever was provisioned. Application components (Istio, Robot Shop, HotROD, Grafana) are explicitly out of scope for AKS in this story, as are Azure Key Vault and managed databases. Existing `make setup` (AWS/EKS path) and `make setup-local` must keep working unchanged, and `.env` must gain a dedicated Azure section while remaining backward compatible for AWS."

## Clarifications

### Session 2026-09-08

- Q: Should Azure credentials live as demo values directly in the tracked `.env` file, or should `.env` hold only non-secret Azure settings while actual authentication comes from outside `.env`? → A: Non-secret `.env` only — the Azure section holds subscription, tenant, resource group, region, and cluster naming; authentication comes from an already-authenticated CLI session or CI-supplied environment variables outside `.env`.
- Q: How should "comparable compute capacity" be defined when picking Azure VM sizes for each AKS node pool, so the requirement is testable against the EKS instance types? → A: Match vCPU count and memory (GB), using the nearest available general-purpose Azure VM SKU that meets or exceeds each corresponding EKS instance type's vCPU and memory.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stand up an empty AKS cluster that mirrors EKS's node architecture (Priority: P1)

A platform engineer sets the cloud provider configuration in `.env` to Azure, supplies the Azure-specific settings, and runs the standard lifecycle commands. The result is a running AKS cluster with the same four node pools (app, persistent, observability, loadgen) as the EKS cluster, each carrying the same workload label and taint, and sized to the same effective compute capacity — with no application or observability workloads deployed onto it.

**Why this priority**: This is the entire point of the story. Without a correctly shaped, empty AKS cluster, there is nothing for any later story (Key Vault, managed databases, app workloads) to build on.

**Independent Test**: Can be fully tested by configuring `.env` for Azure, running the provisioning commands, and inspecting the resulting AKS cluster's node pools, labels, taints, and sizes against the documented EKS node groups — without deploying or verifying any application.

**Acceptance Scenarios**:

1. **Given** `.env` is configured to target Azure with valid Azure settings, **When** the platform engineer runs the end-to-end setup command, **Then** an AKS cluster is created with five node pools (one system pool + four user pools) whose names, `workload` labels, taints, and min/max node counts match the corresponding EKS node groups (plus system pool in mode: System with no taint).
2. **Given** the AKS cluster has been provisioned, **When** the platform engineer inspects it, **Then** no application, Istio, or observability workloads are present — only the empty cluster and node pool infrastructure.
3. **Given** `.env` is configured to target Azure, **When** the platform engineer runs the dedicated cluster-provisioning command on its own, **Then** the AKS cluster and its node pools come up without requiring the rest of the end-to-end setup to run first.

---

### User Story 2 - Tear down AKS infrastructure cleanly (Priority: P2)

A platform engineer who provisioned an AKS cluster runs the teardown command and expects every Azure resource that setup created to be removed, with no manual cleanup and no leftover billable resources.

**Why this priority**: Cost control and re-runnability depend on teardown being complete; this is nearly as important as bringing the cluster up, since demo/test clusters are created and destroyed frequently.

**Independent Test**: Can be fully tested by provisioning an AKS cluster, running the teardown command, and confirming (via the Azure control plane) that none of the cluster's resources remain.

**Acceptance Scenarios**:

1. **Given** an AKS cluster and its node pools exist, **When** the platform engineer runs the teardown command, **Then** the cluster, its node pools, and every supporting resource created during setup are removed.
2. **Given** no AKS cluster currently exists, **When** the platform engineer runs the teardown command, **Then** it completes successfully without error instead of failing on missing resources.

---

### User Story 3 - Existing AWS and local workflows remain unaffected (Priority: P3)

A platform engineer who only ever targets AWS EKS or the local k3d environment runs the same commands they always have, with `.env` left at its current AWS/local values, and observes identical behavior to before this story shipped.

**Why this priority**: This is a non-regression guarantee rather than new capability, but it is what makes the change safe to merge — existing users and CI must not notice any difference.

**Independent Test**: Can be fully tested by running the existing end-to-end setup against EKS and against local k3d, with `.env` unchanged in its AWS/local sections, and confirming the resulting clusters and outputs match pre-change behavior.

**Acceptance Scenarios**:

1. **Given** `.env` is configured to target AWS (as it is today), **When** the platform engineer runs the end-to-end setup command, **Then** the resulting EKS cluster, node groups, and application stack are identical to the pre-change behavior.
2. **Given** `.env` is configured for the local k3d workflow, **When** the platform engineer runs the local setup command, **Then** behavior is unchanged from before this story.

---

### Edge Cases

- What happens when the provider configuration variable in `.env` is missing, blank, or set to a value that is not one of the supported providers? The system MUST fail fast with a clear error naming the invalid value, rather than silently defaulting to a provider or provisioning nothing.
- What happens when the end-to-end setup or the dedicated cluster-provisioning command is run twice in a row for Azure? The second run MUST complete successfully without creating duplicate node pools, clusters, or supporting resources.
- What happens when the teardown command is run for Azure while Azure authentication is missing, expired, or lacks permission? The system MUST surface a clear authentication/authorization error rather than reporting a false success.
- What happens when only some AKS node pools finish provisioning before a failure interrupts the run? A subsequent run of the provisioning command MUST complete the remaining node pools without duplicating the ones that already exist.
- What happens if a platform engineer targets Azure without having supplied the dedicated Azure configuration values in `.env`? The system MUST fail fast and identify which required value is missing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `.env` MUST expose a configuration setting that selects which cloud provider (existing AWS/EKS, existing local/k3d, or new Azure/AKS) the lifecycle commands target, alongside the existing AWS and local settings, without changing their current names, defaults, or meaning.
- **FR-002**: `.env` MUST gain a dedicated, clearly delimited Azure section holding only non-secret settings needed to target AKS (subscription, tenant, resource group, region, and cluster naming), additive to and independent from the existing AWS section. This section MUST NOT hold Azure credential secrets (for example, a service principal client secret).
- **FR-003**: The end-to-end setup command MUST dynamically provision infrastructure against whichever provider is selected in `.env`, without requiring the platform engineer to invoke a different command per provider.
- **FR-004**: A new cluster-provisioning command MUST provision and bring up the Kubernetes cluster (EKS or AKS) for the selected provider on its own, independent of the rest of the end-to-end setup sequence.
- **FR-005**: When targeting Azure, the cluster-provisioning step MUST create five node pools: one system pool (mode: System, Standard_D4s_v5 or equivalent, minimum 3 nodes, no taint) and four user pools matching the existing EKS node groups in name intent, `workload` label value, taint, minimum/maximum node counts, and compute sizing: app, persistent, observability, and loadgen. The system pool runs critical Kubernetes infrastructure pods (CoreDNS, metrics-server, kube-proxy). 
- **FR-006**: Every AKS node pool MUST carry the same `workload=app|persistent|o11y|loadgen` labeling and matching taint scheme used on EKS, and the cluster MUST provide a storage class usable under the same alias (`gp2`) that existing persistent-volume-consuming manifests already reference, so that manifests written against EKS remain schedulable unchanged if deployed later.
- **FR-007**: The teardown command MUST remove every Azure resource that the Azure provisioning path created (cluster, node pools, and supporting resources), leaving nothing billable behind.
- **FR-008**: The teardown command MUST succeed without error when no AKS cluster currently exists.
- **FR-009**: Re-running the end-to-end setup command or the cluster-provisioning command against Azure MUST be safe: a second consecutive run MUST NOT create duplicate clusters, node pools, or supporting resources.
- **FR-010**: This story MUST NOT deploy any application or observability workload (Istio, Robot Shop, HotROD, Grafana, or any other component from the existing app/observability stacks) onto the AKS cluster.
- **FR-011**: This story MUST NOT provision Azure Key Vault or any managed database service; those remain out of scope for later stories.
- **FR-012**: Existing AWS/EKS setup behavior and existing local k3d setup behavior MUST remain functionally unchanged after this story — same resulting infrastructure, same commands, same `.env` variable names and defaults for AWS and local.
- **FR-013**: When the provider configuration in `.env` is missing, blank, or set to an unsupported value, the lifecycle commands MUST fail with a clear, actionable error rather than proceeding against an unintended provider or silently doing nothing.
- **FR-014**: The Azure lifecycle commands MUST rely on authentication already established outside `.env` (for example, an active `az` CLI session or CI-supplied environment variables) and MUST fail with a clear error identifying the missing authentication, rather than prompting for or storing Azure credential secrets themselves.

### Key Entities

- **Cloud Provider Target**: The `.env`-configured selection of which backend (AWS/EKS, local/k3d, or Azure/AKS) the lifecycle commands operate against for a given run.
- **Kubernetes Cluster**: The provisioned control plane and its node pools for the selected provider; for this story, the Azure instance is an empty cluster with no application workloads.
- **Node Pool**: A named group of compute nodes carrying a `workload` label, a matching taint, a compute size, and minimum/maximum scaling bounds. Four node pools exist per provider: app, persistent, observability, and loadgen.
- **Azure Configuration Section**: The dedicated block of `.env` variables covering Azure subscription, tenant, resource group, region, and cluster naming, additive to the existing AWS variables.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A platform engineer can bring up an empty, correctly shaped AKS cluster with a single end-to-end command, with no manual follow-up steps required to match the target node pool architecture.
- **SC-002**: All five AKS node pools (four user pools + one system pool) are correctly configured: four user pools match their corresponding EKS node groups' `workload` label, taint, minimum/maximum node counts, and vCPU/memory; system pool has mode=System, Standard_D4s_v5 (4 vCPU, 16 GB), no taint, and ≥3 nodes.
- **SC-003**: Running the setup or cluster-provisioning command twice in a row against Azure results in exactly the same set of Azure resources as running it once (zero duplicates).
- **SC-004**: Running the teardown command against a provisioned AKS cluster leaves zero Azure resources behind that setup created.
- **SC-005**: 100% of existing AWS/EKS and local k3d end-to-end setup runs produce infrastructure indistinguishable from pre-change behavior, with no `.env` variable renamed, removed, or redefaulted for those paths.
- **SC-006**: A platform engineer who has never used Azure before can identify every `.env` value they need to set for the Azure path from the dedicated Azure section alone, without reading source code.

## Assumptions

- The new cluster-provisioning command becomes the shared, per-provider entry point that the end-to-end setup command calls after resolving the configured provider. For the existing AWS path, this wraps the current cluster-provisioning script unchanged, so no existing AWS script or behavior is modified — only how the top-level command reaches it.
- The Azure equivalent of the storage driver and `gp2` storage class alias used on EKS (an Azure-managed-disk-backed storage class under the same alias) is provisioned as part of the empty cluster, so that manifests referencing `gp2` remain unchanged if deployed against AKS in a later story.
- Node pools mirror EKS's use of discounted/interruptible compute where the corresponding EKS node group also uses it, to preserve comparable cost characteristics; the exact Azure VM SKU chosen per pool (meeting the vCPU/memory match rule in FR-005) is a planning-phase decision.
- The teardown command operates on infrastructure scoped to a single AKS cluster's own resources (for example, a dedicated resource group created by setup for that cluster), so teardown is a complete, safe operation that cannot affect unrelated Azure resources.
- The Kubernetes version targeted for AKS is the closest available version to the version currently pinned for EKS at implementation time.
