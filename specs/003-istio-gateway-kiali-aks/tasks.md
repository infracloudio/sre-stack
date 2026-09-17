# Tasks: Istio Gateway on AKS

**Input**: Design documents from `/specs/003-istio-gateway-kiali-aks/`

**Prerequisites**: plan.md (complete), spec.md (complete), research.md (findings with blocked cluster access), data-model.md (Istio entities), contracts/ (Makefile and K8s resource specs), quickstart.md (validation scenarios)

**Implementation Strategy**: All tasks are Makefile modifications to extend existing AKS branching. No new source code files created. Tests are provided in quickstart.md (separate validation story).

**Scope**: Add AKS-specific conditional branching to setup-istio, setup-gateway, cleanup, and get-service-endpoints targets. Ensure byte-identical behavior for EKS/local per R8.

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Review and prepare for implementation

- [ ] T001 Review plan.md and specification requirements for Istio/gateway implementation on AKS

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Makefile structure that enables all implementation tasks

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T002 Extend Makefile setup target to branch STACK_MODE=aks for Istio/gateway installation in `/Users/viknesh/sre-stack/Makefile` lines 53-66

- [ ] T003 Extend Makefile cleanup target to branch STACK_MODE=aks for Istio/gateway teardown in `/Users/viknesh/sre-stack/Makefile` lines 221-227

**Checkpoint**: Makefile branching structure in place — implementation can now begin

---

## Phase 3: Implementation (Istio & Gateway Deployment on AKS)

**Goal**: Extend Makefile targets to deploy Istio, gateway, and provide service endpoints on AKS

**Independent Test**: Complete quickstart.md validation scenarios 1-7 against a deployed AKS cluster

### Implementation Tasks

- [ ] T004 Modify setup-istio target to add AKS-specific pod placement and resource tags via Helm --set flags in `/Users/viknesh/sre-stack/Makefile` lines 74-78
  - Add node selectors: `workload=o11y` for istiod, `workload=app` for gateway
  - Add tolerations for istiod: `o11y=true:NoSchedule`
  - Add resource tags: `project=sre-stack,environment=aks`
  - Verify: `make STACK_MODE=aks setup-istio` → istiod on o11y nodes, gateway on app nodes

- [ ] T005 Verify setup-gateway target works identically on AKS without modification in `/Users/viknesh/sre-stack/Makefile` lines 152-154
  - Confirm uses existing `app/robot-shop/Istio/gateway.yaml` (no changes needed)
  - Verify: `make STACK_MODE=aks setup-gateway` → Gateway and VirtualService CRDs applied

- [ ] T006 Extend get-service-endpoints target to capture AKS LoadBalancer IP and set LB_ENDPOINT in `/Users/viknesh/sre-stack/Makefile` lines 169-190
  - Add AKS branch to query `kubectl get svc istio-ingressgateway -n istio-system` for external IP
  - Format as `LB_ENDPOINT=http://{external-ip}:80`
  - Verify: `make STACK_MODE=aks get-service-endpoints` → Prints LB_ENDPOINT and service URLs

- [ ] T007 Add destroy-istio-gateway target to uninstall istio-ingressgateway Helm release in `/Users/viknesh/sre-stack/Makefile` lines 196-201
  - Idempotent: `helm uninstall istio-ingressgateway -n istio-system 2>/dev/null || true`
  - Verify: Run twice, both exit 0, second run shows no error messages (S7)

- [ ] T008 Add cleanup-istio target to uninstall istiod and istio-base Helm releases in `/Users/viknesh/sre-stack/Makefile` (new target after cleanup section)
  - Idempotent: `helm uninstall istiod -n istio-system 2>/dev/null || true` and same for istio-base
  - Verify: Run twice, both exit 0, no "release not found" errors (S6, S7)

**Checkpoint**: All Istio and gateway deployment/cleanup targets implemented and working

---

## Phase 4: Polish & Validation

**Purpose**: Final verification and lint checks

- [ ] T009 Run make lint and verify no new linting errors in Makefile changes in `/Users/viknesh/sre-stack/Makefile`
  - Verify: `make lint` exits 0
  - Verify: `git diff main -- Makefile` shows only AKS sections changed, EKS/local unchanged (S8, R8)

**Checkpoint**: All tasks complete, Makefile validated, ready for PR review

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - review first
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS Phase 3
- **Implementation (Phase 3)**: Depends on Foundational completion - Core feature work
- **Polish (Phase 4)**: Depends on Phase 3 completion - Final validation

### Task Dependencies (within Phase 3)

- **T004** (setup-istio): No dependencies within phase, can start after Foundational
- **T005** (setup-gateway): No direct dependency on T004 (both are independent modifications)
- **T006** (get-service-endpoints): Depends on T004 and T005 (LB endpoint only exists after gateway deployed)
- **T007** (destroy-istio-gateway): No dependencies on T004-T006
- **T008** (cleanup-istio): Depends on T007 (gateway should be cleaned first)

### Parallel Opportunities

**Within Phase 3** (after Foundational complete):
- T004 and T005 can be implemented in parallel (different parts of Makefile)
- T007 and T008 can be implemented in parallel (different cleanup targets)
- T006 can start after T004 and T005 are done but before T007/T008

**Recommended Sequential Order** (conservative approach):
1. T004 (setup-istio) - Core deployment
2. T005 (setup-gateway) - Gateway routing
3. T006 (get-service-endpoints) - User-facing endpoints
4. T007 (destroy-istio-gateway) - Gateway cleanup
5. T008 (cleanup-istio) - Control plane cleanup
6. T009 (lint validation) - Final checks

---

## Implementation Strategy

### MVP Scope (Everything - Single Story)

This feature is a single cohesive story (no sub-stories). The MVP is complete when:
1. Phase 2 (Foundational): Makefile branching in place
2. Phase 3 (Implementation): All Istio/gateway targets working
3. Phase 4 (Polish): Lint validation passes

### Validation Checkpoints

1. **After T003**: Makefile structure ready
   - Verify: `make -n STACK_MODE=aks setup` shows setup-istio and setup-gateway targets

2. **After T004**: Istio control plane deployable
   - Verify: `make STACK_MODE=aks setup-istio` completes (if cluster available)
   - Or: `helm template` dry-run shows correct node selectors and tolerations

3. **After T005**: Gateway deployable
   - Verify: Gateway CRDs can be applied

4. **After T006**: Service endpoints accessible
   - Verify: LB_ENDPOINT is captured and printed

5. **After T008**: Complete teardown possible
   - Verify: `make STACK_MODE=aks cleanup` removes all Istio/gateway resources

6. **After T009**: Code ready for review
   - Verify: `make lint` passes, no regressions

### Testing (Run Against Deployed Cluster)

Once AKS cluster from story #97 is available:
1. Run all scenarios from quickstart.md (S1-S9)
2. Validate pod placement (istiod on o11y, gateway on app)
3. Validate idempotency (all setup/cleanup targets work twice)
4. Validate byte-identical EKS/local (git diff main -- infra/scripts/cluster/aws/ infra/scripts/cluster/local/ is empty)

---

## Notes

- All tasks are **Makefile modifications only** - no new source files
- EKS/local behavior must remain **byte-identical** per R8
- All targets must be **idempotent** (run twice safely) per R6
- **No custom Helm values files** created (per R8, use inline --set or no changes)
- Pod placement strategy implemented via Helm node selectors + tolerations (T004)
- Cleanup targets use `2>/dev/null || true` pattern for idempotency (T007, T008)
- Final validation via `make lint` ensures no syntax errors (T009)
- Live cluster testing deferred until story #97 (AKS cluster) completes
