# Feature Specification: Azure Kubernetes Service (AKS) Support

**Feature Branch**: `001-add-aks-support`

**Created**: 2026-09-07

**Status**: Draft

**Input**: Add cloud-provider-agnostic Makefile targets for deploying AKS infrastructure that mirrors existing EKS node pool architecture, with backward compatibility for AWS and k3d deployments.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure Cloud Provider and Deploy Full Infrastructure Stack (Priority: P1)

An infrastructure engineer needs to deploy a complete Kubernetes cluster environment to Azure using the same Makefile interface they currently use for AWS/local environments. They set cloud provider configuration in .env and execute a single command to provision all base infrastructure.

**Why this priority**: This is the primary user journey and the foundational requirement. Engineers need a single, unified deployment experience across cloud providers to reduce context switching and operational complexity.

**Independent Test**: Can be fully tested by configuring `CLOUD_PROVIDER=aks` in .env, running `make setup`, and verifying that an AKS cluster with matching node specifications is provisioned and ready for use.

**Acceptance Scenarios**:

1. **Given** .env is configured with `CLOUD_PROVIDER=aks`, Azure credentials, and cluster parameters, **When** engineer runs `make setup`, **Then** AKS cluster provisions successfully with all required nodes, labels, and networking configuration
2. **Given** AKS cluster is provisioning, **When** configuration is missing or invalid, **Then** Makefile validates and provides clear error messages before attempting deployment
3. **Given** AKS cluster is deployed, **When** engineer inspects cluster, **Then** node labels and resource sizes match the configuration specified in .env

---

### User Story 2 - Independently Provision Kubernetes Cluster (Priority: P2)

An infrastructure engineer needs to provision just the Kubernetes cluster without the full infrastructure stack, decoupling cluster creation from foundational services. This allows iterative cluster configuration and testing.

**Why this priority**: Enables modular infrastructure workflow where engineers can create the cluster separately, test configurations, and deploy supporting services independently.

**Independent Test**: Can be fully tested by setting `CLOUD_PROVIDER=aks` in .env and running `make start-cluster`, verifying that an empty AKS cluster is created with correct node specifications but no application components.

**Acceptance Scenarios**:

1. **Given** .env is configured with `CLOUD_PROVIDER=aks` and cluster parameters, **When** engineer runs `make start-cluster`, **Then** AKS cluster provisions with configured node pool and labels
2. **Given** AKS cluster is provisioned, **When** engineer inspects the cluster, **Then** no application components (Istio, Robot Shop, HotROD, Grafana) are deployed

---

### User Story 3 - Cleanup and Remove All Infrastructure (Priority: P3)

An infrastructure engineer needs to tear down all provisioned resources in a single operation to avoid costs and resource waste. This applies to any cloud provider (EKS, AKS, or k3d).

**Why this priority**: Critical for cost control and resource management, but lower priority than creation workflows since it executes less frequently.

**Independent Test**: Can be fully tested by provisioning AKS infrastructure with `make setup`, then running `make cleanup` and verifying all resources (cluster, node groups, networking components) are removed.

**Acceptance Scenarios**:

1. **Given** AKS infrastructure is deployed, **When** engineer runs `make cleanup`, **Then** all provisioned resources are removed and no charges accrue
2. **Given** `make cleanup` is executed, **When** cleanup encounters resource dependencies, **Then** cleanup proceeds in correct dependency order without errors

---

### Edge Cases

- What happens when .env is missing required Azure credentials (subscription ID, resource group, etc.)? — Makefile validation halts with actionable error message (FR-007)
- How does the system handle partial deployment failures (e.g., node pool created but networking failed)? — Deployment fails fast and halts; operators manually inspect state and decide to retry or run `make cleanup` (FR-014)
- What happens when user switches `CLOUD_PROVIDER` between deployments without cleanup (e.g., AWS cluster exists, switch to AKS)? — Makefile detects existing deployment and halts with error message requiring explicit `make cleanup` (FR-013)
- How are existing AWS/k3d deployments unaffected when AKS configuration is added to .env? — Backward compatibility maintained; existing configurations continue to work unchanged (FR-009)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Makefile `make setup` target MUST support dynamic cloud provider selection via `CLOUD_PROVIDER` environment variable in .env
- **FR-002**: Makefile `make start-cluster` target MUST support dynamic cloud provider selection and provision AKS cluster when `CLOUD_PROVIDER=aks`
- **FR-003**: Makefile `make cleanup` target MUST support dynamic cloud provider selection and remove all AKS resources when AKS was deployed
- **FR-004**: AKS cluster MUST be provisioned with node pool configuration (node count, instance type/VM size, availability zones) matching or equivalent to existing EKS node pool specification
- **FR-005**: AKS nodes MUST have all labels applied (e.g., node-role.kubernetes.io, custom labels) consistent with EKS node labeling
- **FR-006**: .env configuration file MUST include dedicated Azure credentials section (subscription ID, tenant ID, client secret, resource group name, region) as environment variables alongside existing AWS configuration
- **FR-007**: Makefile MUST validate .env configuration completeness for the selected cloud provider before attempting deployment
- **FR-013**: Makefile MUST detect existing deployments from different cloud providers and halt with clear error message directing user to run `make cleanup` before switching providers
- **FR-014**: Makefile MUST fail fast on deployment errors (e.g., node pool creation failure during cluster provisioning) and halt without attempting partial resource cleanup; operators must manually resolve and retry or explicitly run `make cleanup`
- **FR-008**: Existing `make setup-aws` and `make setup-local` targets MUST remain fully functional without modification
- **FR-009**: .env configuration MUST maintain backward compatibility — existing AWS/k3d configurations must work unchanged
- **FR-010**: Makefile MUST support idempotent operations — re-running `make setup` or `make start-cluster` on an existing deployment MUST not cause errors
- **FR-011**: AKS deployment MUST NOT include application stack components (Istio, Robot Shop, HotROD, Grafana, observability services)
- **FR-012**: AKS deployment MUST NOT provision auxiliary services (Azure Key Vault, managed databases)

### Key Entities

- **Cloud Provider Configuration**: Environment variables defining which cloud provider (EKS/AKS/k3d) to target, stored in .env
- **Azure Credentials**: Subscription ID, tenant ID, client secret, and resource group name provided as .env environment variables and passed to deployment scripts
- **Node Pool Specification**: Number of nodes, VM instance type, availability zones, and labels to apply to AKS nodes
- **Makefile Targets**: `make setup`, `make start-cluster`, `make cleanup` — entry points for infrastructure operations
- **Deployment State**: State tracking to detect existing deployments; used to prevent accidental multi-cloud deployments and trigger warnings when switching providers

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Engineer can deploy AKS infrastructure end-to-end by setting configuration in .env and executing `make setup` (no additional manual steps required)
- **SC-002**: AKS cluster node count and compute sizing match the specification defined in .env (e.g., if .env specifies 3 nodes of type Standard_D2s_v3, cluster has exactly 3 nodes of that type)
- **SC-003**: 100% of required node labels are successfully applied to AKS nodes and are queryable via standard Kubernetes API (verified by `kubectl get nodes --show-labels`)
- **SC-004**: Existing AWS deployment workflow (`make setup` with `CLOUD_PROVIDER=eks`) works without modification and deploys to AWS as before
- **SC-005**: Existing k3d deployment workflow (`make setup` with `CLOUD_PROVIDER=k3d`) works without modification and creates k3d cluster as before
- **SC-006**: `make cleanup` removes all AKS resources (cluster, node pools, networking, storage) when AKS was deployed
- **SC-007**: Configuration validation provides actionable error messages when required fields are missing (user can identify and fix issue in < 5 minutes)
- **SC-008**: No application components are deployed to AKS cluster after `make start-cluster` completes (cluster is empty, ready for application deployment)
- **SC-009**: When switching cloud providers without cleanup, Makefile detects and blocks with clear error message (user is directed to run `make cleanup` first)
- **SC-010**: Deployment failures halt immediately without partial resource cleanup; operators can inspect state and manually recover

## Assumptions

- **Azure Subscription Access**: Engineers deploying to AKS have access to an Azure subscription and appropriate permissions to create resource groups, AKS clusters, and networking resources
- **Node Specification Equivalence**: The node configuration options available in AKS (VM sizes, availability zones) will map to the existing EKS node pool specification without requiring significant changes to deployment logic
- **Backward Compatibility Focus**: Modifications to the Makefile will use conditional logic or separate target definitions to avoid impacting existing AWS and k3d workflows
- **Single Cloud Provider per Deployment**: A single .env configuration targets one cloud provider at a time; simultaneous multi-cloud deployments are out of scope
- **No Shared State**: Each cloud provider deployment maintains independent state (Terraform state files, kubeconfig files, etc.); no cross-provider resource sharing
- **Manual Configuration Management**: Infrastructure engineers are responsible for setting correct values in .env; no automatic cloud provider detection
- **Standard Kubernetes API**: Both AKS and EKS expose standard Kubernetes API; no provider-specific custom APIs required for core operations
- **Existing Tooling**: Deployment scripts can be extended to support AKS without replacing existing AWS/k3d infrastructure code

## Clarifications

### Session 2026-09-07

- Q: How should Azure credentials be provided and stored in the deployment process? → A: Environment variables — Azure credentials (subscription ID, tenant ID, client secret) are provided as .env variables and passed to deployment scripts
- Q: When a user switches cloud providers without running `make cleanup` first, what should happen? → A: Warn and require explicit cleanup — Makefile detects existing deployment and halts with error message directing user to run `make cleanup` first
- Q: When AKS deployment fails partway through, what should happen? → A: Fail fast and halt — Stop at first error; operators must manually inspect state, fix issues, and re-run deployment or use `make cleanup` to reset
