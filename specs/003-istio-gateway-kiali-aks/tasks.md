# Tasks: Deploy Istio Ingress Gateway and Kiali to AKS

**Story:** #104  
**Plan:** `specs/003-istio-gateway-kiali-aks/plan.md`  
**Total Tasks:** 12 | **Effort:** ~2.5 hours

---

## Phase 1: Setup AKS Helm Values (30 min)

### Task 1.1: Create AKS chart-values directory and istio-values.yaml
**Effort:** 10 min  
**Acceptance:**
- [ ] Directory exists: `infra/chart-values/aks/`
- [ ] File exists: `infra/chart-values/aks/istio-values.yaml`
- [ ] Contains: global.hub, global.tag (1.31.0), pilot.nodeSelector, tolerations
- [ ] `helm template` renders without errors

### Task 1.2: Create gateway-values.yaml
**Effort:** 10 min  
**Acceptance:**
- [ ] File exists: `infra/chart-values/aks/gateway-values.yaml`
- [ ] Contains: service.type=LoadBalancer, nodeSelector, tolerations
- [ ] Matches pattern from monitoring/chart-values/

### Task 1.3: Create kiali-values.yaml
**Effort:** 10 min  
**Acceptance:**
- [ ] File exists: `infra/chart-values/aks/kiali-values.yaml`
- [ ] Contains: spec.version=v1.85, auth.strategy=anonymous
- [ ] Contains: prometheus URL pointing to `prometheus-stack-kube-prom-prometheus.monitoring:9090`
- [ ] Contains: nodeSelector for o11y pool, tolerations for workload=o11y

---

## Phase 2: Update Makefile Dispatch (20 min)

### Task 2.1: Add STACK_MODE=aks variable dispatch
**Effort:** 10 min  
**Acceptance:**
- [ ] Makefile lines 59–63: Add `ifeq ($(STACK_MODE),aks)` block
- [ ] Sets: ISTIO_VALUES_FILE, GATEWAY_VALUES_FILE, KIALI_VALUES_FILE, KIALI_CHART_VERSION
- [ ] Paths point to `infra/chart-values/aks/` files
- [ ] `make lint` passes

### Task 2.2: Add setup-istio-aks, setup-gateway-aks, setup-kiali-aks targets
**Effort:** 10 min  
**Acceptance:**
- [ ] setup-istio-aks: helm upgrade --install istio-base and istiod with AKS values
- [ ] setup-gateway-aks: helm upgrade --install ingress-gateway, then kubectl apply platform-gateway.yaml
- [ ] setup-kiali-aks: helm repo add kiali, helm upgrade --install kiali with AKS values
- [ ] All targets use $(KIALI_VALUES_FILE) variable, not hardcoded paths
- [ ] `make lint` passes

---

## Phase 3: Create Platform-Owned Gateway Manifest (15 min)

### Task 3.1: Create infra/aks/ directory and platform-gateway.yaml
**Effort:** 15 min  
**Acceptance:**
- [ ] Directory exists: `infra/aks/`
- [ ] File exists: `infra/aks/platform-gateway.yaml`
- [ ] Contains: Gateway resource (name: platform-ingress-gateway, namespace: istio-system)
- [ ] Contains: VirtualService for /kiali (routing to kiali.istio-system:20001)
- [ ] Contains: VirtualService for /grafana (routing to grafana.monitoring:3000)
- [ ] `kubectl apply --dry-run=client -f` succeeds
- [ ] YAML passes yamllint

---

## Phase 4: Update get-service-endpoints (10 min)

### Task 4.1: Extend get-service-endpoints target for AKS
**Effort:** 10 min  
**Acceptance:**
- [ ] Makefile get-service-endpoints target: Add AKS branch with `ifeq ($(STACK_MODE),aks)`
- [ ] Queries: `kubectl get svc -n istio-system ingress-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
- [ ] Outputs: LoadBalancer IP, /kiali path, /grafana path (same format as EKS)
- [ ] Handles case where LB IP not yet assigned (empty check)
- [ ] `make get-service-endpoints STACK_MODE=aks` prints correctly

---

## Phase 5: Test on Dev AKS Cluster (45 min)

### Task 5.1: Run setup-istio-aks and verify SC-001
**Effort:** 15 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-istio` exits 0
- [ ] `kubectl get pods -n istio-system | grep istiod` shows Running pod
- [ ] `kubectl get pods -n istio-system | grep ingress-gateway` shows Running pod
- [ ] Both pods: Ready 1/1, Restarts 0
- [ ] `kubectl get ns istio-system -L istio-injection` shows enabled

### Task 5.2: Run setup-gateway-aks and verify SC-002
**Effort:** 15 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-gateway` exits 0
- [ ] `kubectl get svc -n istio-system ingress-gateway` shows type=LoadBalancer
- [ ] EXTERNAL-IP field is assigned (not pending) within 2 minutes
- [ ] Port 80:PORT/TCP is listed
- [ ] `kubectl get gateway -n istio-system` shows platform-ingress-gateway

### Task 5.3: Run setup-kiali-aks and verify SC-003a/SC-004
**Effort:** 10 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-kiali` exits 0
- [ ] `kubectl get pods -n istio-system | grep kiali` shows Running pod on o11y node pool
- [ ] Pod: Ready 1/1, Restarts 0
- [ ] `kubectl get pod -n istio-system -l app=kiali -o wide | grep o11y` shows correct node pool
- [ ] LB_IP=$(make get-service-endpoints STACK_MODE=aks | grep AKS | awk '{print $NF}')
- [ ] `curl http://$LB_IP/kiali/` returns 200 (dashboard loads)

---

## Phase 6: Verify Idempotency and Cross-Cloud (30 min)

### Task 6.1: Test SC-007 — idempotency (first + second run)
**Effort:** 15 min  
**Acceptance:**
- [ ] `STACK_MODE=aks make setup-istio` (first run) exits 0
- [ ] `STACK_MODE=aks make setup-istio` (second run) exits 0, no reinstall
- [ ] `STACK_MODE=aks make setup-gateway` (second run) exits 0, no error
- [ ] `STACK_MODE=aks make setup-kiali` (second run) exits 0, upgrade check only

### Task 6.2: Verify EKS/local unaffected (SC-006)
**Effort:** 10 min  
**Acceptance:**
- [ ] `STACK_MODE=eks make setup-istio` exits 0 (no change to EKS values)
- [ ] `STACK_MODE=local make setup-istio` exits 0 (no change to local values)
- [ ] `make get-service-endpoints STACK_MODE=eks` prints EKS LB correctly
- [ ] `make get-service-endpoints STACK_MODE=local` prints local ingress correctly

### Task 6.3: Verify cleanup removes LoadBalancer and IP
**Effort:** 5 min  
**Acceptance:**
- [ ] Before cleanup: `kubectl get svc -n istio-system ingress-gateway` shows EXTERNAL-IP
- [ ] Run `make cleanup`
- [ ] After cleanup: AKS cluster no longer exists
- [ ] Verify in Azure portal: node resource group removed (no orphaned public IP)

---

## Phase 7: Final Verification and Documentation (10 min)

### Task 7.1: Run full verification checklist
**Effort:** 5 min  
**Acceptance:**
- [ ] SC-001: Istio mesh operational
- [ ] SC-002: Gateway responding with external IP
- [ ] SC-003a: Kiali pod running, dashboard loads at /kiali
- [ ] SC-004: Anonymous auth works (no login prompt)
- [ ] SC-005: Pods scheduled to correct node pools (no evictions)
- [ ] SC-006: EKS/local unchanged
- [ ] SC-007: Idempotent, cleanup removes resources

### Task 7.2: Document findings in story PR
**Effort:** 5 min  
**Acceptance:**
- [ ] PR comment: Verification script output (pod listing, curl output, node pool verification)
- [ ] PR comment: Screenshot of Kiali dashboard at /kiali path
- [ ] PR comment: Confirmation that Grafana /grafana route is configured (but waiting on #101 to verify)
- [ ] All tasks checked off

---

## Parallelizable Tasks

- Task 1.1, 1.2, 1.3 can run in parallel (independent files)
- Task 2.1 and 2.2 can run in parallel (separate Makefile targets)

## Dependencies

- Task 2.2 depends on: Task 2.1 (Makefile variables)
- Task 3.1 depends on: Nothing (standalone manifest)
- Task 4.1 depends on: Task 2.2 (Makefile targets exist)
- Task 5.x depends on: Tasks 1–4 (all files created)
- Task 6.x depends on: Task 5.x (setup verified)
- Task 7.x depends on: Task 6.x (all tests pass)

## MVP Scope

Tasks 1–5 deliver core Istio/Kiali/gateway on AKS. Tasks 6–7 are validation + documentation.
