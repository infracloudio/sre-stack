# Tasks: Deploy Istio Ingress Gateway and Kiali to AKS

**Story:** #104  
**Plan:** `specs/003-istio-gateway-kiali-aks/plan.md`  
**Total Tasks:** 10 | **Effort:** ~2.5 hours

---

## Phase 1: Setup AKS Helm Values (30 min)

### Task 1.1: Create AKS chart-values directory and istio-values.yaml
**Effort:** 10 min  
**Acceptance:**
- [ ] Directory exists: `infra/chart-values/aks/`
- [ ] File exists: `infra/chart-values/aks/istio-values.yaml`
- [ ] Contains: global.hub, global.tag (1.31.0), pilot.nodeSelector (agentpool: system), tolerations
- [ ] `helm template istio/base -f infra/chart-values/aks/istio-values.yaml` renders without errors

### Task 1.2: Create gateway-values.yaml
**Effort:** 10 min  
**Acceptance:**
- [ ] File exists: `infra/chart-values/aks/gateway-values.yaml`
- [ ] Contains: service.type=LoadBalancer, nodeSelector (agentpool: system), tolerations
- [ ] Matches pattern from monitoring/chart-values/

### Task 1.3: Create kiali-values.yaml
**Effort:** 10 min  
**Acceptance:**
- [ ] File exists: `infra/chart-values/aks/kiali-values.yaml`
- [ ] Contains: spec.version=v1.85, auth.strategy=anonymous
- [ ] Contains: prometheus URL pointing to `prometheus-stack-kube-prom-prometheus.monitoring:9090`
- [ ] Contains: nodeSelector (agentpool: o11y), tolerations for workload=o11y taint

---

## Phase 2: Update Makefile Dispatch (REUSE existing targets) (20 min)

### Task 2.1: Add STACK_MODE=aks variable dispatch to Makefile
**Effort:** 10 min  
**Acceptance:**
- [ ] Makefile lines 59–63: Add `ifeq ($(STACK_MODE),aks)` block
- [ ] Sets: ISTIO_VALUES_FILE, GATEWAY_VALUES_FILE, KIALI_VALUES_FILE
- [ ] Paths point to `infra/chart-values/aks/` files
- [ ] Similar blocks exist for eks/local (no new variables, just add aks)
- [ ] `make lint` passes
- [ ] **NO new `-aks` targets created** (reuse setup-istio, setup-gateway, setup-kiali)

### Task 2.2: Modify existing setup-istio, setup-gateway, setup-kiali targets
**Effort:** 10 min  
**Acceptance:**
- [ ] setup-istio target: uses $(ISTIO_VALUES_FILE) variable, works for STACK_MODE=aks/eks/local
- [ ] setup-gateway target: uses $(GATEWAY_VALUES_FILE) variable, applies infra/$(STACK_MODE)/platform-gateway.yaml
- [ ] setup-kiali target: uses $(KIALI_VALUES_FILE) variable
- [ ] All targets check STACK_MODE dispatch at top of Makefile
- [ ] No `-aks`, `-eks`, `-local` suffixed targets added
- [ ] `make lint` passes
- [ ] `STACK_MODE=aks make setup-istio` works
- [ ] `STACK_MODE=eks make setup-istio` still works (unchanged)

---

## Phase 3: Create Platform-Owned Gateway Manifest (15 min)

### Task 3.1: Create infra/aks/ directory and platform-gateway.yaml
**Effort:** 15 min  
**Acceptance:**
- [ ] Directory exists: `infra/aks/`
- [ ] File exists: `infra/aks/platform-gateway.yaml`
- [ ] Contains: Gateway resource (name: platform-ingress-gateway, namespace: istio-system)
- [ ] Contains: VirtualService for /kiali route (routing to kiali.istio-system.svc.cluster.local:20001)
- [ ] Does NOT contain /grafana VirtualService (belongs in #101 story)
- [ ] `kubectl apply --dry-run=client -f infra/aks/platform-gateway.yaml` succeeds
- [ ] YAML passes yamllint

---

## Phase 4: Update get-service-endpoints (10 min)

### Task 4.1: Extend get-service-endpoints target for AKS with polling retry
**Effort:** 10 min  
**Acceptance:**
- [ ] Makefile get-service-endpoints target: Add AKS branch with `ifeq ($(STACK_MODE),aks)`
- [ ] Queries: `kubectl get svc -n istio-system ingress-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
- [ ] Polls with 5-second retries, up to 2 minutes (24 attempts) for LoadBalancer IP
- [ ] Outputs: "LoadBalancer IP pending..." message while waiting
- [ ] Once IP assigned: prints `/kiali` path (same format as EKS)
- [ ] If timeout: prints error message (no IP assigned after 2 min)
- [ ] `make get-service-endpoints STACK_MODE=aks` works correctly
- [ ] EKS/local `make get-service-endpoints` unaffected

---

## Phase 5: Test on Dev AKS Cluster (45 min)

### Task 5.1: Run setup-istio with STACK_MODE=aks and verify SC-001
**Effort:** 15 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-istio` exits 0
- [ ] `kubectl get pods -n istio-system | grep istiod` shows Running pod
- [ ] `kubectl get pods -n istio-system | grep ingress-gateway` shows Running pod
- [ ] Both pods: Ready 1/1, Restarts 0
- [ ] `kubectl get pods -n istio-system -l app=istiod -o jsonpath='{.items[*].spec.nodeSelector}' | grep agentpool` shows agentpool=system
- [ ] `kubectl get ns istio-system -L istio-injection` shows enabled

### Task 5.2: Run setup-gateway with STACK_MODE=aks and verify SC-002
**Effort:** 15 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-gateway` exits 0
- [ ] `kubectl get svc -n istio-system ingress-gateway` shows type=LoadBalancer
- [ ] EXTERNAL-IP field is assigned (not pending) within 2 minutes (polling works)
- [ ] Port 80:PORT/TCP is listed
- [ ] `kubectl get gateway -n istio-system` shows platform-ingress-gateway
- [ ] `kubectl get vs -n istio-system | grep kiali` shows kiali-vs

### Task 5.3: Run setup-kiali with STACK_MODE=aks and verify SC-003a/SC-004
**Effort:** 10 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-kiali` exits 0
- [ ] `kubectl get pods -n istio-system | grep kiali` shows Running pod on o11y node pool
- [ ] Pod: Ready 1/1, Restarts 0
- [ ] Node pool verification: `kubectl get pod -n istio-system -l app=kiali -o jsonpath='{.items[*].spec.nodeSelector}' | grep agentpool` shows agentpool=o11y
- [ ] Toleration verification: `kubectl get pod -n istio-system -l app=kiali -o jsonpath='{.items[*].spec.tolerations}' | grep workload` shows workload=o11y
- [ ] `make get-service-endpoints STACK_MODE=aks` polls and prints LoadBalancer IP + /kiali path
- [ ] `curl http://$LB_IP/kiali/` returns 200 (dashboard loads)

---

## Phase 6: Verify Idempotency and Cross-Cloud (30 min)

### Task 6.1: Test SC-007 — idempotency (first + second run)
**Effort:** 15 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-istio` (first run) exits 0
- [ ] `STACK_MODE=aks make setup-istio` (second run) exits 0, no error
- [ ] Second run output shows "upgrade" message, not "install" (proves idempotency)
- [ ] `STACK_MODE=aks make setup-gateway` (second run) exits 0
- [ ] `STACK_MODE=aks make setup-kiali` (second run) exits 0

### Task 6.2: Verify EKS/local unaffected (SC-006)
**Effort:** 10 min  
**Acceptance:**
- [ ] `STACK_MODE=eks make setup-istio` exits 0 (existing behavior unchanged)
- [ ] `STACK_MODE=local make setup-istio` exits 0 (existing behavior unchanged)
- [ ] `make get-service-endpoints STACK_MODE=eks` prints EKS LB correctly
- [ ] `make get-service-endpoints STACK_MODE=local` prints local ingress correctly

### Task 6.3: Verify cleanup removes LoadBalancer and IP (SC-007)
**Effort:** 5 min  
**Acceptance:**
- [ ] Before cleanup: `kubectl get svc -n istio-system ingress-gateway` shows EXTERNAL-IP
- [ ] Run `make cleanup`
- [ ] After cleanup: AKS cluster no longer exists
- [ ] Verify in Azure CLI: `az group list | grep -i "MC_.*_aks"` returns empty (no orphaned resource group)

---

## Phase 7: Final Verification and Documentation (10 min)

### Task 7.1: Run full verification checklist
**Effort:** 5 min  
**Acceptance:**
- [ ] SC-001: Istio mesh operational (pods Ready 1/1, no restarts)
- [ ] SC-002: Gateway responding with external IP (LoadBalancer provisioned)
- [ ] SC-003a: Kiali pod running, dashboard loads at /kiali
- [ ] SC-004: Anonymous auth works (no login prompt)
- [ ] SC-005: Pods scheduled to correct node pools via agentpool labels (no evictions)
- [ ] SC-006: EKS/local unchanged
- [ ] SC-007: Idempotent, cleanup removes resources

### Task 7.2: Document findings in story PR
**Effort:** 5 min  
**Acceptance:**
- [ ] PR comment: `kubectl get pods -n istio-system -o wide` output (node pool verification)
- [ ] PR comment: `curl http://$LB_IP/kiali/` response (dashboard loads)
- [ ] PR comment: Screenshot of Kiali dashboard at /kiali path
- [ ] PR comment: Confirmation that /grafana route will be added by #101 (this story only adds gateway)
- [ ] PR comment: Confirmation that STACK_MODE=aks make setup-istio succeeds twice (idempotency)
- [ ] All tasks checked off

---

## Parallelizable Tasks

- Task 1.1, 1.2, 1.3 can run in parallel (independent files)
- Task 2.1 and 2.2 can run in parallel (same Makefile edit, complementary)

## Dependencies

- Task 2.2 depends on: Task 2.1 (Makefile variables must exist)
- Task 3.1 depends on: Nothing (standalone manifest)
- Task 4.1 depends on: Task 2.2 (targets must exist to call from get-service-endpoints)
- Task 5.x depends on: Tasks 1–4 (all files created)
- Task 6.x depends on: Task 5.x (setup verified)
- Task 7.x depends on: Task 6.x (all tests pass)

## MVP Scope

Tasks 1–5 deliver core Istio/Kiali/gateway on AKS. Tasks 6–7 are validation + documentation.

---

## Key Differences from Original Plan

1. **No new `-aks` targets** → Reuse setup-istio/gateway/kiali with STACK_MODE dispatch (FR-005)
2. **Node pool verification uses agentpool labels** → More robust than name pattern matching
3. **LoadBalancer IP polling with retry** → Handles Azure 1-2 min provisioning delay
4. **No grafana-vs in this story** → Belongs in #101 (observability)
5. **Cleanup verification via Azure CLI** → Checks that resource group is gone
