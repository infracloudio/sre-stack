# Tasks: 003-istio-gateway-kiali-aks

**Branch**: 003-istio-gateway-kiali-aks
**Version split (1.30.4 on AKS, 1.17.2 on EKS)**: Resolved — see research.md §1-§2.
**Awaiting**: AKS cluster availability (story #97, PR #99)

---

## Task List

### Phase 1: Setup & Validation (sequential, no cloud access needed)

- [ ] **T001** `.env`: Add ISTIO_VERSION=1.30.4, ISTIO_NAMESPACE=istio-system, HELM_TIMEOUT=5m for AKS section only. EKS section unchanged. Verify `.env` syntax with `grep "^AKS_\|^ISTIO_" .env` and review current EKS pins against makefile
- [ ] **T002** Validate Istio chart versions exist: `helm search repo istio/base --version 1.30.4`, `helm search repo istio/istiod --version 1.30.4`, `helm search repo istio/gateway --version 1.30.4` (report exact versions available)
- [ ] **T003** Research: Verify EKS targets exist unchanged. `grep -n "^setup-istio:" makefile`, `grep -n "^setup-gateway:" makefile`, confirm no modifications to these lines since main
- [ ] **T004** Create `infra/scripts/cluster/setup-istio-aks.sh` (new file): Helm repo add istio, helm repo update, helm install istio-base, istiod, AND istio/gateway (all three — the gateway chart is what creates the `istio-ingressgateway` LoadBalancer Service, verified against the real EKS makefile:74-78 where all three installs live under `setup-istio`, not `setup-gateway`) in sequence to istio-system namespace. All chart versions from `.env`. Use `--wait --timeout` from `.env`. Include idempotency: check if release exists before install. **Owns the LoadBalancer entirely — T005 does not touch it.**
- [ ] **T005** Create `infra/scripts/cluster/setup-gateway-aks.sh` (new file): No-op for this story. Robot Shop (the only thing EKS's real `setup-gateway` applies, per makefile:152-154) is out of scope (story #102), so there is no app-specific Gateway/VirtualService to apply yet. Correction (independent audit): the composite `setup:` target under STACK_MODE=aks does not call `setup-gateway` today (verified: `sed -n '53,57p' makefile` shows only `setup-cluster`) — the earlier "so make setup doesn't break" rationale was false. This script exists so the standalone `make setup-gateway` target (invoked directly, matching R1's pattern) works correctly under STACK_MODE=aks. Exits 0, creates nothing, logs that it's a placeholder pending story #102.
- [ ] **T006** Create `infra/scripts/cluster/cleanup-istio.sh` (new file): Helm uninstall istio-ingressgateway (the gateway chart release, since T004 installed it here), istiod, istio-base from istio-system (in that order, if present). Include `--ignore-not-found` or equivalent check. Tolerate missing releases. **Owns removing the LoadBalancer.**
- [ ] **T007** Create `infra/scripts/cluster/cleanup-gateway.sh` (new file): No-op mirroring T005. Nothing to delete since T005 creates nothing. Exits 0.
- [ ] **T008** Extend `infra/scripts/cluster/azure-common.sh` (verified path: `ls infra/scripts/cluster/`; this file exists today, `common-aks.sh` does not): Add function `get_lb_endpoint_aks()` that fetches the external IP of the istio-ingressgateway Service and prints it as a bare IP/hostname (e.g. `52.xxx.xxx.xxx`), no scheme, no port. **Correction (round-5 audit, a fourth copy of the same error)**: this task previously specified format `http://<IP>:80`, "matching EKS format" — same wrong claim already fixed in spec.md R4 and the makefile-targets.md contract. Verified (`sed -n '42,46p' makefile`): neither EKS nor AKS's real `LB_ENDPOINT` carries a scheme or port; that gets added only by the `@echo` lines that consume it. **Open question, carried over from plan.md's Approach #4**: whether this function is even needed, since the makefile's existing top-level `LB_ENDPOINT` assignment may already cover `STACK_MODE=aks` with no new code — not resolved here.
- [ ] **T009** Update `makefile`: Add `STACK_MODE=aks` branch to the existing `setup-istio` target (calls setup-istio-aks.sh) and `setup-gateway` target (calls the no-op setup-gateway-aks.sh). Same branching for `cleanup-istio`/`cleanup-gateway` (new targets). Verify syntax with `make lint`.
- [ ] **T010** **Correction (round-6 audit)**: this task was missing the redundancy flag T008 already carries, and as written it isn't implementable — a recipe (shell command inside a target) can't "export" a value back into a make variable that's already assigned at file scope (makefile:42-46). Real open question, not resolved here: the existing `else` branch at makefile:44-46 already computes the correct value for `STACK_MODE=aks` with zero new code. Before implementing this task as "update `get-service-endpoints` target to include AKS branch, call `get_lb_endpoint_aks()`", confirm on a real AKS cluster whether the existing assignment already works — if it does, this task may reduce to "no change needed."
- [ ] **T011** Lint & syntax check: `make lint` passes; shell scripts pass `shellcheck` with no errors; makefile syntax valid (`make --dry-run setup-istio` runs without error).
- [ ] **T012** Dry-run all Helm commands (moved from Phase 2: `helm template` needs no cluster, so this runs today and is the one check that would catch a 1.17.2→1.30.4 breaking change before any cloud access exists): `helm template istio-base istio/base --namespace istio-system --version 1.30.4` (and same for istiod, gateway). Output must be captured verbatim to a file, not summarized or retyped. Compare against `helm template ... --version 1.17.2` output for the same charts to surface any rendering differences.

### Phase 2: Cloud verification (sequential, requires AKS cluster from story #97; genuinely blocked until PR #99 merges and access is granted — see plan.md Blocker section)

- [ ] **T013** Run `make setup-istio setup-gateway` (STACK_MODE=aks) on the AKS cluster from story #97 once available. Time the run — S1/S2 are now both covered by `setup-istio` alone (under 5 min, including LoadBalancer IP acquisition), since `setup-gateway` is a no-op for this story (see R2 correction, this round). Capture output verbatim into the PR #107 evidence block (T023) — no new permanent makefile target for this, and no separate quickstart.md (deleted this round; it had drifted from R10/R3 and duplicated this task list).
- [ ] **T014** Verify Istio pods reach Running: Post-setup, run `kubectl get pods -n istio-system` and confirm the istiod pod and the istio-ingressgateway pod have status Running within the timeout. Correction: `istio-base` installs CRDs and cluster-scoped resources only — it creates no pods, so there's nothing to check Running for that release specifically.
- [ ] **T015** Verify load-balancer IP assigned: `kubectl get svc -n istio-system istio-ingressgateway` returns an external IP (not `<pending>`). Record the IP.
- [ ] **T016** Test idempotency of setup: Run `make setup-istio setup-gateway` a second time. Exit code must be 0. Output must contain no "installed", "created", or "updated" messages (script is a no-op on second run).
- [ ] **T017** Test cleanup: Run `make cleanup-gateway` followed by `make cleanup-istio`. All Istio/gateway resources deleted. Verify: `kubectl get all -n istio-system` returns no user-created pods, or is empty. **Correction (round-5 audit)**: previous wording said "only system pods (kube-dns, etc.)" — wrong namespace; kube-dns/CoreDNS runs in `kube-system`, not `istio-system`. After a correct cleanup, `istio-system` should have nothing left in it at all.
- [ ] **T018** Test cleanup idempotency: Run cleanup commands again. Exit code must be 0. No error messages about missing resources.
- [ ] **T019** Verify EKS/local unchanged: the check must assert the EKS/local helm lines are byte-unchanged, not merely that no line matching "setup-istio" changed — extending the target with an AKS branch necessarily touches lines containing that string, so a naive grep for it fails by construction. Correct check: `git diff main -- makefile` and confirm the pre-existing EKS helm lines (`--version 1.17.2`, the two `--set` flags on istiod, `--wait --timeout 2m0s`) appear unmodified in the diff — only new AKS-branch lines should appear as additions.
- [ ] **T020** Verify git and linting: Final `make lint` passes; no new linting errors. `git status` shows only new AKS files and modified makefile/README/AGENTS.md.

### Phase 3: Documentation & evidence

- [ ] **T021** Update `README.md`: Add "Istio Gateway on AKS" section. Include command examples: `STACK_MODE=aks make setup-istio && make setup-gateway && make get-service-endpoints`. Link to `.env` section documenting AKS Istio settings.
- [ ] **T022** Update `AGENTS.md`: Add line noting Istio version pin split (1.30.4 on AKS for K8s 1.34 compatibility; 1.17.2 on EKS unchanged). Include reference to Istio support matrix decision.
- [ ] **T023** Paste verification output into PR: Output from T013 (timings), T014 (pod status), T015 (LB IP), T016 (second run, no-op confirmation), T017/T018 (cleanup), T019 (EKS unchanged diff). Evidence must include command executed, exit code, and timestamp.

---

## Notes

- **Blockers**: Only one remains — AKS cluster availability (research.md §5), which gates Phase 2 (T013 onward). T001-T012 can proceed now.
- **Principle VIII**: chart versions — see research.md §1-§2, not restated here.
- **Paths**: All tasks use repo-relative paths (e.g., `infra/scripts/cluster/`), not absolute paths. All filenames are lowercase (e.g., `makefile`, not `Makefile`).
- **Taints & affinity**: R10 is resolved (spec.md, research.md §10) — istiod and the gateway land on the AKS system node pool, which carries no taint. No tolerations or custom Helm values files are needed. AD-003 (spot-priority toleration) does not apply to this story. (Correction: an earlier draft of this note said R10 was still deferred, contradicting the headline fix of the previous round — fixed here.)
- **AD-003**: scalesetpriority toleration (for spot VMs) is not part of this story; workload-installation stories handle it per constitution principle V.
