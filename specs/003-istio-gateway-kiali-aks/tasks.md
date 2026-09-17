# Tasks: 003-istio-gateway-kiali-aks

**Branch**: 003-istio-gateway-kiali-aks
**Blocked by**: Architect approval of Istio version split (1.30.4 on AKS, 1.17.2 on EKS)
**Awaiting**: AKS cluster availability (story #97, PR #99)

---

## Task List

### Phase 1: Setup & Validation (sequential, no cloud access needed)

- [ ] **T001** `.env`: Add ISTIO_VERSION=1.30.4, ISTIO_NAMESPACE=istio-system, HELM_TIMEOUT=5m for AKS section only. EKS section unchanged. Verify `.env` syntax with `grep "^AKS_\|^ISTIO_" .env` and review current EKS pins against makefile
- [ ] **T002** Validate Istio chart versions exist: `helm search repo istio/base --version 1.30.4`, `helm search repo istio/istiod --version 1.30.4`, `helm search repo istio/gateway --version 1.30.4` (report exact versions available)
- [ ] **T003** Research: Verify EKS targets exist unchanged. `grep -n "^setup-istio:" makefile`, `grep -n "^setup-gateway:" makefile`, confirm no modifications to these lines since main
- [ ] **T004** Create `infra/scripts/cluster/setup-istio-aks.sh` (new file): Helm repo add istio, helm repo update, helm install istio-base/istiod/gateway in sequence to istio-system namespace. All chart versions from `.env`. Use `--wait --timeout` from `.env`. Include idempotency: check if release exists before install.
- [ ] **T005** Create `infra/scripts/cluster/setup-gateway-aks.sh` (new file): Deploy ingress-gateway LoadBalancer Service (type: LoadBalancer, selector: istio=ingressgateway). Include wait loop for external IP assignment (timeout from `.env`).
- [ ] **T006** Create `infra/scripts/cluster/cleanup-istio.sh` (new file): Helm uninstall istio-ingressgateway, istiod, istio-base from istio-system (in that order, if present). Include `--ignore-not-found` or equivalent check. Tolerate missing releases.
- [ ] **T007** Create `infra/scripts/cluster/cleanup-gateway.sh` (new file): Delete istio-ingressgateway Service; delete any associated LoadBalancer. Tolerate "not found" gracefully with exit 0.
- [ ] **T008** Extend `infra/scripts/common-aks.sh`: Add function `get_lb_endpoint_aks()` that fetches the external IP of the istio-ingressgateway Service and prints it in format `http://<IP>:80` (matching EKS format).
- [ ] **T009** Update `makefile`: Add `setup-istio` target with `STACK_MODE` branch: if aks, call setup-istio-aks.sh; if eks, call existing EKS setup. Same for `setup-gateway` and cleanup targets. Verify syntax with `make lint`.
- [ ] **T010** Update `makefile`: Update `get-service-endpoints` target to include AKS branch. If `STACK_MODE=aks`, call `get_lb_endpoint_aks()` and export `LB_ENDPOINT`.
- [ ] **T011** Lint & syntax check: `make lint` passes; shell scripts pass `shellcheck` with no errors; makefile syntax valid (`make --dry-run setup-istio` runs without error).

### Phase 2: Cloud verification (sequential, requires AKS cluster from story #97)

- [ ] **T012** Dry-run all Helm commands: `helm template istio-base istio/base --namespace istio-system --version 1.30.4` (and same for istiod, gateway). Output should be valid YAML with no warnings. Redirect to files for inspection.
- [ ] **T013** Create a test makefile target `test-aks-setup` that runs `make setup-istio setup-gateway` on the AKS cluster from story #97. Time the run (should be under 5 min for setup-istio, under 2 min for setup-gateway). Capture output.
- [ ] **T014** Verify Istio pods reach Running: Post-setup, run `kubectl get pods -n istio-system` and confirm all control-plane pods (istiod, base) have status Running within the timeout.
- [ ] **T015** Verify load-balancer IP assigned: `kubectl get svc -n istio-system istio-ingressgateway` returns an external IP (not `<pending>`). Record the IP.
- [ ] **T016** Test idempotency of setup: Run `make setup-istio setup-gateway` a second time. Exit code must be 0. Output must contain no "installed", "created", or "updated" messages (script is a no-op on second run).
- [ ] **T017** Test cleanup: Run `make cleanup-gateway` followed by `make cleanup-istio`. All Istio/gateway resources deleted. Verify: `kubectl get all -n istio-system` returns only system pods (kube-dns, etc.), or is empty.
- [ ] **T018** Test cleanup idempotency: Run cleanup commands again. Exit code must be 0. No error messages about missing resources.
- [ ] **T019** Verify EKS unchanged: Diff the branch against main for EKS scripts. Command: `git diff main -- makefile | grep -E "(setup-istio|setup-gateway)" | grep -v "STACK_MODE=aks"` should return nothing (EKS targets unchanged).
- [ ] **T020** Verify git and linting: Final `make lint` passes; no new linting errors. `git status` shows only new AKS files and modified makefile/README/AGENTS.md.

### Phase 3: Documentation & evidence

- [ ] **T021** Update `README.md`: Add "Istio Gateway on AKS" section. Include command examples: `STACK_MODE=aks make setup-istio && make setup-gateway && make get-service-endpoints`. Link to `.env` section documenting AKS Istio settings.
- [ ] **T022** Update `AGENTS.md`: Add line noting Istio version pin split (1.30.4 on AKS for K8s 1.34 compatibility; 1.17.2 on EKS unchanged). Include reference to Istio support matrix decision.
- [ ] **T023** Paste verification output into PR: Output from T013 (timings), T014 (pod status), T015 (LB IP), T016 (second run, no-op confirmation), T017/T018 (cleanup), T019 (EKS unchanged diff). Evidence must include command executed, exit code, and timestamp.

---

## Notes

- **Blockers**: Plan.md documents two blockers (Istio version compatibility, AKS cluster availability). Both must be addressed or explicitly accepted by Architect before T012 can run.
- **Principle VIII**: All chart versions verified against official sources (Istio Helm repo, not cached docs). All access requirements documented in plan.md.
- **Paths**: All tasks use repo-relative paths (e.g., `infra/scripts/cluster/`), not absolute paths. All filenames are lowercase (e.g., `makefile`, not `Makefile`).
- **Taints & affinity**: R10 (pod placement) is deferred to clarification. Tasks assume default node scheduling (no custom values files); if placement is required, plan must be updated before T004/T005.
- **AD-003**: scalesetpriority toleration (for spot VMs) is not part of this story; workload-installation stories handle it per constitution principle V.
