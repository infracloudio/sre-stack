# Tasks: Deploy Istio Ingress Gateway and Kiali to AKS

**Feature**: Deploy Istio Ingress Gateway and Kiali to AKS  
**Story**: #104  
**Spec**: `specs/003-istio-gateway-kiali-aks/spec.md`  
**Plan**: `specs/003-istio-gateway-kiali-aks/plan.md`  
**Branch**: `feat/istio-gateway-kiali-aks`

---

## Phase 1: Setup & Validation

**Goal**: Prepare project structure and pre-flight checks.

**Independent Test Criteria**:
- [ ] Pre-check script validates AKS cluster is reachable
- [ ] Pre-check script detects required node pools (system, observability)
- [ ] Directory structure matches plan

**Implementation Tasks**:

- [ ] T001 Create infra/aks directory structure per plan.md
- [ ] T002 Create app/gateway directory structure for Istio gateway manifests
- [ ] T003 [P] Create infra/aks/pre-checks.sh to validate AKS cluster and node pools exist
- [ ] T004 [P] Update .env.example with ISTIO_VERSION and KIALI_VERSION for AKS

---

## Phase 2: Helm Chart Values (Foundational)

**Goal**: Define Azure-specific Istio and Kiali Helm values; keep EKS/local unchanged.

**Independent Test Criteria**:
- [ ] infra/aks/chart-values/istio-values.yaml is valid YAML and includes node pool selectors
- [ ] infra/aks/chart-values/kiali-values.yaml is valid YAML and configures Prometheus endpoint
- [ ] `helm template` commands validate without errors for both charts

**Implementation Tasks**:

- [ ] T005 [P] Create infra/aks/chart-values/istio-values.yaml with system node pool affinity and gateway LoadBalancer service type
- [ ] T006 [P] Create infra/aks/chart-values/kiali-values.yaml with observability node pool affinity, anonymous auth, and Prometheus endpoint placeholder
- [ ] T007 Verify Istio Helm chart values by running `helm template istio istio/base` command (manual validation in research.md)
- [ ] T008 Verify Kiali Helm chart values by running `helm template kiali kiali/kiali` command (manual validation in research.md)

---

## Phase 3: Infrastructure Scripts

**Goal**: Implement setup, cleanup, and helm repository management scripts.

**Independent Test Criteria**:
- [ ] setup.sh installs Istio and Kiali Helm releases when not present
- [ ] setup.sh skips installation if releases already exist (idempotent)
- [ ] cleanup.sh uninstalls both Helm releases and removes gateway public IP
- [ ] Second `make setup` with azure selected succeeds without errors

**Implementation Tasks**:

- [ ] T009 Create infra/aks/setup.sh: add Helm repos (istio, kiali), install Istio release to istio-system namespace
- [ ] T010 [P] Update infra/aks/setup.sh: install Kiali release to kiali namespace with Prometheus endpoint from #101
- [ ] T011 Update infra/aks/setup.sh: verify idempotency (helm list check before install)
- [ ] T012 Create infra/aks/cleanup.sh: uninstall Istio and Kiali Helm releases
- [ ] T013 Update infra/aks/cleanup.sh: remove Azure LoadBalancer public IP from node resource group

---

## Phase 4: Istio Gateway and Routing Manifests

**Goal**: Deploy platform-owned Istio gateway and route `/kiali` to Kiali service.

**Independent Test Criteria**:
- [ ] Gateway resource is created in istio-system namespace
- [ ] VirtualService routes `/kiali` path to Kiali service
- [ ] `kubectl apply --dry-run=client` succeeds for all manifests
- [ ] Gateway LoadBalancer service has external IP assigned

**Implementation Tasks**:

- [ ] T014 [P] Create app/gateway/istio-gateway.yaml: define platform-owned Istio Gateway on default HTTP port
- [ ] T015 [P] Create app/kiali-route.yaml: define VirtualService to route `/kiali` path to kiali/kiali service
- [ ] T016 Add gateway and kiali-route manifests to setup.sh deployment phase (kubectl apply after Helm releases)
- [ ] T017 [P] Update app/gateway/istio-gateway.yaml: configure hostnames and domain for AKS (if needed per Azure networking)

---

## Phase 5: Makefile Integration

**Goal**: Integrate Azure Istio/Kiali setup into existing cloud provider dispatcher.

**Independent Test Criteria**:
- [ ] `make setup` with CLOUD_PROVIDER=azure invokes AKS setup scripts
- [ ] `make clean` with CLOUD_PROVIDER=azure invokes AKS cleanup scripts
- [ ] EKS and local setup paths remain unchanged

**Implementation Tasks**:

- [ ] T018 Update Makefile to dispatch `make setup` with CLOUD_PROVIDER=azure to infra/aks/setup.sh
- [ ] T019 Update Makefile to dispatch `make clean` with CLOUD_PROVIDER=azure to infra/aks/cleanup.sh
- [ ] T020 [P] Verify EKS setup path still works (regression test in manual testing)
- [ ] T021 [P] Verify local setup path still works (regression test in manual testing)

---

## Phase 6: Service Endpoints Output

**Goal**: Include AKS gateway address in endpoints command output.

**Independent Test Criteria**:
- [ ] `make endpoints` with CLOUD_PROVIDER=azure prints AKS gateway LoadBalancer IP
- [ ] Output format matches EKS and local format
- [ ] Handles case where gateway IP is pending (not yet assigned)

**Implementation Tasks**:

- [ ] T022 Update endpoints/output.sh to query AKS gateway service IP: `kubectl get svc -n istio-ingress` for istio-ingress service
- [ ] T023 Add AKS gateway endpoint to endpoints output formatting (match EKS/local structure)
- [ ] T024 Handle pending IP case: display "Pending" until Azure assigns LoadBalancer IP

---

## Phase 7: Validation & Testing

**Goal**: Verify all requirements are met and system is operational.

**Independent Test Criteria**:
- [ ] All mesh control-plane and gateway pods are Ready with zero restarts
- [ ] Kiali pod is Running in observability node pool
- [ ] Gateway LoadBalancer has external IP assigned
- [ ] `/kiali` route is accessible at gateway IP (anonymous auth)
- [ ] Setup is idempotent (second run succeeds without error)
- [ ] Cleanup removes all resources

**Implementation Tasks**:

- [ ] T025 Create quickstart.md validation scenarios: verify pod readiness, external IP assignment, Kiali dashboard accessibility
- [ ] T026 Document manual test: `kubectl get pods -n istio-system` and verify Ready status
- [ ] T027 Document manual test: `kubectl get svc -n istio-ingress` and verify external IP assignment
- [ ] T028 Document manual test: `kubectl get pods -n kiali` and verify pod on observability node pool
- [ ] T029 Create test scenario: run `make setup` twice on clean AKS and verify second run is no-op (idempotency)
- [ ] T030 Create test scenario: run `make clean` and verify LoadBalancer and public IP are removed from Azure resource group
- [ ] T031 [P] Document regression test for EKS setup: `make setup` with CLOUD_PROVIDER=eks still works
- [ ] T032 [P] Document regression test for local setup: `make setup` with no CLOUD_PROVIDER still works

---

## Phase 8: Documentation

**Goal**: Document design decisions and operational procedures.

**Independent Test Criteria**:
- [ ] research.md captures Istio/Kiali compatibility with AKS K8s 1.34
- [ ] data-model.md documents node pool contracts and resource placement
- [ ] All manual test procedures are documented

**Implementation Tasks**:

- [ ] T033 [P] Create research.md: document Istio version compatibility with K8s 1.34
- [ ] T034 [P] Add to research.md: Kiali Prometheus integration and configuration
- [ ] T035 [P] Add to research.md: Azure LoadBalancer public IP lifecycle and cleanup behavior
- [ ] T036 Create data-model.md: document Istio CRDs (Gateway, VirtualService), Kiali ConfigMap structure
- [ ] T037 Add to data-model.md: node pool selectors and tolerations for mesh components and Kiali
- [ ] T038 Document in quickstart.md: troubleshooting steps (pod logs, describe, helm status)

---

## Dependencies & Execution Order

**Blocking Dependencies**:
- Phase 1 (Setup & Validation) must complete before all other phases
- Phase 2 (Helm Values) must complete before Phase 3 (Infrastructure Scripts)
- Phase 3 (Infrastructure Scripts) must complete before Phase 4 (Manifests)

**Parallel Opportunities**:
- Phase 2 tasks T005, T006 (Helm values files) can run in parallel
- Phase 3 tasks T009, T010, T012 (setup.sh components, cleanup.sh) can run in parallel after Phase 2
- Phase 4 tasks T014, T015, T017 (manifests) can run in parallel
- Phase 5 tasks T020, T021 (regression tests) can run in parallel
- Phase 6 tasks T022, T023, T024 (endpoints integration) can run sequentially (dependencies on T023)
- Phase 7 tasks T031, T032 (regression tests) can run in parallel
- Phase 8 tasks T033–T038 (documentation) can run in parallel

**Story Completion**:
- #104 (Istio, gateway, Kiali on AKS) is complete when Phase 7 validation tests pass
- Success verified by: SC-001 through SC-008 acceptance criteria from spec.md
- Phase 8 documentation is post-completion; does not block story closure

---

## Implementation Strategy

**MVP Scope (Minimum Viable Product)**:
1. Phase 1: Setup (directory structure + pre-checks)
2. Phase 2: Helm values (Istio + Kiali configs)
3. Phase 3: Infrastructure scripts (setup.sh, cleanup.sh)
4. Phase 4: Gateway and routing manifests
5. Phase 5: Makefile integration

**Incremental Delivery**:
- After MVP: Phase 6 (service endpoints output)
- After MVP + Phase 6: Phase 7 (validation tests)
- After MVP + Phase 7: Phase 8 (documentation polish)

**Verification Gates**:
- After Phase 3: Run `make setup` on AKS cluster; verify Istio pods are Ready
- After Phase 4: Verify gateway has LoadBalancer IP; test `kubectl apply` of manifests
- After Phase 5: Verify Makefile dispatcher works; run all three cloud paths (azure, eks, local)
- After Phase 6: Verify `make endpoints` includes AKS gateway IP
- After Phase 7: All acceptance criteria SC-001 through SC-008 verified on test AKS cluster

---

## Task Summary

- **Total Tasks**: 38
- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Helm Values)**: 4 tasks
- **Phase 3 (Infrastructure)**: 5 tasks
- **Phase 4 (Manifests)**: 4 tasks
- **Phase 5 (Makefile)**: 4 tasks
- **Phase 6 (Endpoints)**: 3 tasks
- **Phase 7 (Validation)**: 8 tasks
- **Phase 8 (Documentation)**: 6 tasks

**Parallelizable Tasks**: 27 (marked with [P])  
**MVP Delivery**: 20 tasks (Phases 1–5)  
**Full Delivery**: 38 tasks (all phases)
