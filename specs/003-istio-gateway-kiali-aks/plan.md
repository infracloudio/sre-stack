# Implementation Plan: Deploy Istio Ingress Gateway and Kiali to AKS

**Branch**: `003-istio-gateway-kiali-aks` | **Date**: 2026-09-16 | **Spec**: [#104](../003-istio-gateway-kiali-aks/spec.md)

**Input**: Feature specification from `/specs/003-istio-gateway-kiali-aks/spec.md`

---

## Summary

Deploy a self-hosted Istio service mesh with an ingress gateway and Kiali observability dashboard to the AKS cluster provisioned by story #97. The mesh control plane and gateway use the system node pool; Kiali uses the observability pool. Setup integrates with the existing Makefile `make setup` dispatcher, and cleanup removes all mesh infrastructure. The platform owns the shared ingress gateway, enabling path-based routing for workloads and the `/kiali` dashboard (verified after Prometheus from #101 lands).

---

## Technical Context

**Cloud Platform**: Azure Kubernetes Service (AKS) with node pools (system, observability, persistent, app)

**Primary Dependencies**: 
- Istio (self-hosted, open-source, Helm deployed)
- Kiali (dashboard, Helm deployed)
- Prometheus (deployed by #101 — Kiali reads metrics from it)
- Azure LoadBalancer for ingress gateway

**Networking**: 
- AKS cluster networking via Azure VNet
- LoadBalancer service provisions public IP for gateway
- Service-to-service: Istio sidecar injection

**Storage**: N/A for this story (mesh and Kiali are stateless; metrics come from Prometheus #101)

**Target Platform**: Azure Kubernetes Service (managed K8s on Azure)

**Project Type**: Infrastructure provisioning (Helm charts + Makefile integration)

**Scope**: 
- Istio Helm chart (latest pinned version for AKS K8s 1.34)
- Kiali Helm chart (latest pinned version for AKS K8s 1.34)
- Azure-specific settings files (separate from EKS/local)
- Makefile + script integration
- Node pool placement via selectors and tolerations

**Constraints**:
- Setup must be idempotent (safe to run twice)
- No changes to existing EKS or local version pins
- Cleanup must remove gateway public IP (lives in node resource group)

---

## Constitution Check

**Principle I: Re-runnable Scripts**
- ✓ Setup and cleanup scripts MUST be idempotent
- ✓ Helm installs MUST detect existing releases and skip re-install
- Action: Research.md will document idempotency checks for Helm

**Principle II: Pinned Versions**
- ✓ Istio and Kiali versions MUST be pinned in Azure-specific chart-values files
- ✓ Existing EKS and local pins MUST remain unchanged
- Action: Plan will isolate Azure pins from shared `.env`

**Principle III: One Configuration Surface**
- ✓ Cloud selection flows through `.env` (CLOUD_PROVIDER=azure)
- ✓ No hand-edits needed to change mesh versions
- Action: Research.md documents `.env` keys for Istio/Kiali versions

**Principle IV: No Secrets in Git**
- ✓ Istio and Kiali Helm defaults use demo/public configs
- ✓ No real credentials in manifests
- Action: Confirm in research.md

**Principle V: Workload Placement Contract**
- ✓ Mesh control plane and gateway → system pool with workload=system selector + system:NoSchedule toleration
- ✓ Kiali → observability pool with workload=o11y selector + observability:NoSchedule toleration
- Action: Verify node labels/taints from #97

**Principle VI: Specs Without Technical Detail**
- ✓ This plan holds technical material; spec.md is narrative
- Action: N/A

**Principle VII: Plain Language**
- ✓ This plan uses plain language with concrete Helm/kubectl examples in research.md
- Action: Research.md will include actual helm template output

**Principle VIII: Try It Before You Plan It**
- ✓ Research phase MUST include hands-on Helm template and kubectl dry-run commands
- ✓ Actual AKS cluster deployment confirmation (if available) or helm template verification
- Action: Phase 0 research will run helm template for Istio and Kiali and report actual output

**Principle IX: Plan In Steps**
- ✓ This plan built iteratively in conversation, paused after Technical Context and Constitution Check
- Action: Awaiting reviewer feedback before Phase 0

**Principle X: Converge to Agreed Scope**
- ✓ Convergence will trace findings to spec requirements and acceptance criteria
- ✓ No new edge cases beyond what spec names
- Action: Convergence phase will validate against SC-001 through SC-008

**Gate Status**: ✓ Constitution check passed. Ready for Phase 0 research.

---

## Project Structure

### Documentation (this feature)

```text
specs/003-istio-gateway-kiali-aks/
├── spec.md              # Feature specification (APPROVED)
├── plan.md              # This file (DRAFT)
├── research.md          # Phase 0 output — hands-on Helm research
├── data-model.md        # Phase 1 output — Helm values, node pool contracts
├── contracts/           # Phase 1 output — if applicable for routing/gateway API
├── quickstart.md        # Phase 1 output — verification scenarios
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
infra/aks/
├── chart-values/
│   ├── istio-values.yaml        # AKS-specific Istio Helm values
│   └── kiali-values.yaml        # AKS-specific Kiali Helm values
├── setup.sh                     # Setup script: adds Helm repos, installs Istio + Kiali
├── cleanup.sh                   # Cleanup script: uninstalls Helm releases
└── pre-checks.sh                # Validates node pools exist, cluster is reachable

app/
├── gateway/
│   └── istio-gateway.yaml       # Platform-owned gateway resource
└── kiali-route.yaml             # VirtualService routing `/kiali` to Kiali service

monitoring/
└── (Prometheus deployed by #101)
```

**Structure Decision**: Helm chart-values split by cloud provider (`.../aks/`, `.../eks/`, `./`, local).

---

## Phases

### Phase 0: Research (Hands-On Validation)

**Objective**: Resolve technical unknowns and validate Istio/Kiali deployment approach on AKS.

**Research Tasks**:

1. **Istio deployment on AKS**
   - Task: Verify Istio Helm chart compatibility with AKS K8s 1.34
   - Find: Latest stable Istio version for K8s 1.34
   - Run: `helm template istio istio/base --version [VERSION]` to validate chart structure
   - Find: Node affinity/toleration patterns for system node pool placement
   - Find: LoadBalancer service configuration for Azure

2. **Kiali deployment and Prometheus integration**
   - Task: Verify Kiali Helm chart and Prometheus scrape endpoint discovery
   - Find: Kiali config for reading metrics from external Prometheus (provided by #101)
   - Run: `helm template kiali kiali/kiali --version [VERSION]` to validate chart structure
   - Find: Anonymous authentication configuration for Kiali dashboard

3. **Azure LoadBalancer public IP lifecycle**
   - Task: Confirm how Azure manages LoadBalancer public IPs in node resource group
   - Find: Public IP naming convention; will it be cleaned up by cluster deletion?
   - Reference: AKS cluster deletion cleanup behavior

4. **Istio gateway and VirtualService for `/kiali` path**
   - Task: Validate routing pattern used in EKS/local applies to AKS
   - Find: Gateway and VirtualService YAML patterns (already in repo for EKS)
   - Run: `kubectl apply --dry-run=client` test for gateway + VirtualService

5. **Idempotency check strategy**
   - Task: Confirm `helm install --set=CreateCRD=false` strategy (if used)
   - Find: Helm hooks or upgrade patterns for re-runs
   - Validate: Second `make setup` with azure selected succeeds without error

**Deliverable**: research.md with findings, helm template outputs, and rationale for each decision.

### Phase 1: Design & Contracts

**Objective**: Finalize Helm values, node pool placement contracts, and validation scenarios.

**Design Tasks**:

1. **data-model.md**: Istio/Kiali resource contracts
   - Istio CRDs: Gateway, VirtualService, DestinationRule (if used), PeerAuthentication
   - Kiali ConfigMap for Prometheus address and auth settings
   - Node pool selectors and tolerations

2. **contracts/** (if applicable): 
   - Gateway API routing rules (path-based routing for `/kiali`)
   - Service mesh observability contract (what metrics Kiali expects from Prometheus)

3. **quickstart.md**: Validation scenarios
   - Verify Istio mesh is operational: `kubectl get pods -n istio-system`
   - Verify gateway external IP: `kubectl get svc -n istio-ingress`
   - Verify Kiali is running: `kubectl get pods -n kiali`
   - Port-forward and test dashboard: `kubectl port-forward -n kiali svc/kiali 20001:20001`
   - Verify `/kiali` path through gateway (after #101 Prometheus lands, verify topology)

**Deliverable**: data-model.md, contracts/, quickstart.md, ready for tasks.md generation.

---

## Complexity Tracking

No Constitution Check violations. All requirements align with existing principles.

---

## Next Steps

1. **Architecture review**: Pause here for feedback on plan direction
2. **Phase 0 research**: Execute hands-on Helm template and Azure research
3. **Phase 1 design**: Finalize Helm values and quickstart scenarios
4. **Task generation**: Run `/speckit-tasks` once plan is approved

---

**Status**: DRAFT — awaiting reviewer feedback on Technical Context and Phase 0 approach.
