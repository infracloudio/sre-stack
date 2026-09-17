# Plan: 003-istio-gateway-kiali-aks

**Status**: Awaiting review & `gate:plan-approved` label

## Approach

Reuse the existing self-hosted Istio + ingress-gateway pattern already working on EKS/local. On AKS:

1. **Setup Istio**: Extend the existing `setup-istio` target (makefile:74, currently EKS/local-only) with a `STACK_MODE=aks` branch that runs three Helm installs in sequence (`istio-base`, `istiod`, `istio-gateway`), installing to the `istio-system` namespace with configuration pinned in `.env`. The existing EKS/local helm lines (makefile:76-78) are untouched.
2. **Setup gateway**: Extend the existing `setup-gateway` target (makefile:152) with an AKS branch that applies the ingress-gateway Service (LoadBalancer). This story creates no VirtualServices (see R3 — routing is owned by later stories).
3. **Cleanup**: Create `cleanup-istio` and `cleanup-gateway` targets (these do not exist today; verified via `grep -n "^cleanup-istio:\|^cleanup-gateway:" makefile` — no matches) that safely uninstall/delete resources; cleanup is repeatable (exists checks, tolerate "not found")
4. **Endpoints**: Update `get-service-endpoints` to fetch and print the AKS load-balancer external IP in the same format as EKS (stored in `LB_ENDPOINT` environment variable)

All scripts follow the check-then-create, re-runnable pattern already used by story #97 (AKS cluster setup).

## Blocker: Kubernetes 1.34 support

**Status**: Blocking implementation. Requires Architect review before proceeding.

**Issue**: Story #97 pins `AKS_KUBERNETES_VERSION=1.34` in `.env`. Cross-cloud consistency (R1) suggests using the same Istio version as EKS/local, which is `1.17.2`. However, Istio 1.17.2 reached end-of-life on Oct 27, 2023 and supports only Kubernetes up to 1.26.

**Resolution**: Verified via Istio support matrix (fetched 2026-09-17):
- Istio 1.30.4 (currently supported) supports Kubernetes 1.32–1.36 ✓
- Istio 1.30.4 is CVE-free (no blocker CVEs at 1.30.0+)
- Istio 1.30.4 charts are in the Helm repository (verified: `helm search repo istio/base --version 1.30.4`)

**Decision**: Pin Istio to `1.30.4` on AKS only. EKS/local remain on `1.17.2` (unchanged per R8).

**Awaiting**: Architect approval of this version split before tasks proceed.

## Blocker: AKS cluster availability

**Status**: Blocking verification phase (Phase 2 tasks only; Phase 1 dry-run validation can proceed now).

**Issue**: Story #97 (AKS cluster + node pools) is a dependency. Verified directly against GitHub (fetched 2026-09-17): PR #99 (`f/097/add_aks_support`) is open, targeting `main`. The Architect requested changes and removed the `gate:plan-approved` label on Sep 11, 2026, so PR #99's plan is not currently approved and the cluster is not deployed.

**Who was asked**: Nobody yet. This is the honest current state, not a placeholder — per Principle VIII, the next action is to actually ask (not to substitute a guess). Action: ask the Architect/deployment lead for sandbox subscription access before Phase 2 tasks (T013 onward) begin.

**What is needed** (to state clearly once asked):
- Access to sandbox Azure subscription (Contributor role)
- An available AKS cluster from story #97, once PR #99 merges

**Substitute**: None approved. Per Principle VIII, cheap read-only checks (chart names, versions, makefile targets, paths) never qualify for a substitute — all of those are verified directly in research.md. The end-to-end cluster verification (T013 onward) has no substitute and will wait for real access.

**This limitation is stated in the PR description** (see PR #107), not only here, per Principle VIII.

---

## Files changing

| File | Change | Rationale |
|---|---|---|
| `.env` | Add `ISTIO_VERSION=1.30.4` (AKS-only); add `ISTIO_NAMESPACE=istio-system` (shared); review existing EKS pins | Pin Istio version for cross-cloud consistency, with K8s 1.34 compatibility |
| `makefile` | Add `setup-istio` target with `STACK_MODE=aks` branch; add `setup-gateway` target with AKS branch; add `cleanup-istio` and `cleanup-gateway` | Drive AKS Istio/gateway via existing `make setup-*` interface |
| `infra/scripts/cluster/setup-istio-aks.sh` (new) | Helm repos + istio-base, istiod, gateway chart installs | Install Istio via Helm; check-then-create pattern |
| `infra/scripts/cluster/setup-gateway-aks.sh` (new) | Helm install gateway; apply ingress LoadBalancer Service | Deploy AKS ingress gateway |
| `infra/scripts/cluster/cleanup-istio.sh` (new) | Delete istio-system namespace or helm uninstall; tolerate already-gone | Idempotent cleanup; all Istio resources removed |
| `infra/scripts/cluster/cleanup-gateway.sh` (new) | Delete istio-ingressgateway helm release; delete Service; tolerate not found | Cleanup gateway; no orphaned load-balancers |
| `infra/scripts/cluster/azure-common.sh` | Extend to include Istio/gateway helpers: `get_lb_endpoint_aks()` (verified path via `ls infra/scripts/cluster/`; the file is `azure-common.sh`, not `common-aks.sh`) | Reusable function for fetching load-balancer IP |
| `makefile` | Update `get-service-endpoints` with AKS branch | Print `LB_ENDPOINT` for AKS (same format as EKS) |
| `README.md` | Add "Istio Gateway on AKS" section | Document AKS Istio setup alongside EKS/local |
| `AGENTS.md` | Add line noting Istio 1.30.4 pin for AKS (K8s 1.34 compatibility) | Record version split rationale for future agents |

## Pinned choices (reasoning in research.md)

| Choice | Value | Rationale |
|---|---|---|
| Istio chart version (AKS) | 1.30.4 | Currently supported; K8s 1.34 compatible; EKS/local unchanged at 1.17.2 |
| Kubernetes namespace | `istio-system` | Matches EKS/local; standard Istio convention |
| Ingress Service type | LoadBalancer | Matches EKS/local; managed by Azure LB controller |
| Gateway name | `istio-ingressgateway` | Matches EKS/local Helm release name |
| Configuration | `.env`-driven | All settings (namespace, versions, replicas) from `.env`; no inline defaults |

## Constitution check (v1.4.0)

Checked directly against `.specify/memory/constitution.md` (verified: `grep -n "^### [IVX]*\." .specify/memory/constitution.md`, confirming version 1.4.0 and these ten principle names). Unlike the two previous rounds, this check is not self-certifying — it is written after the fixes above, against the actual file, and two rows below genuinely fail.

| Principle | Satisfied? | Evidence |
|---|---|---|
| **I. Re-runnable Scripts** | Planned ✓ | Scripts (T004-T007, not yet written) are designed check-then-create; cleanup tolerates "not found". Not yet verified in code since implementation hasn't started. |
| **II. Pinned Versions** | ✓ | Istio 1.30.4 (AKS) / 1.17.2 (EKS, unchanged) pinned explicitly. New AKS helm calls add no inline `--set` flags (R10 resolved to system-pool default scheduling, no custom values needed). Note: the *existing* EKS helm line (makefile:77) already uses inline `--set` for tracing config — pre-existing, out of scope per R8, not introduced by this story. |
| **III. One Configuration Surface** | ✓ | ISTIO_VERSION, ISTIO_NAMESPACE, HELM_TIMEOUT all read from `.env`; no hand-edited values elsewhere. |
| **IV. No Secrets in Git** | ✓ | No credentials; all charts are public/open-source. |
| **V. Workload Placement Contract** | Ambiguous — flagging, not asserting | This principle requires workloads to use the `app\|persistent\|o11y\|loadgen` labels/taints. R10 places istiod/gateway on the AKS **system** pool, which is outside that four-pool taxonomy (it's AKS's own infra pool, not one of the four). Reading: Istio is platform infrastructure, not one of the four named workload categories, so this principle's labels don't apply to it — but that's an interpretation, not a settled fact, and I'm not confident enough to mark it ✓ outright. Needs Architect confirmation. |
| **VI. Specs Without Technical Detail** | ✗ Fails as written | `spec.md` currently contains commands and config throughout (`make setup-istio`, `STACK_MODE=aks`, `.env`, `curl <LB_ENDPOINT>`, `kubectl get all -n istio-system`). Principle VI says spec.md "MUST NOT hold technical material: no code, no config snippets... no commands." This spec violates that as literally written. This predates my involvement (the original spec, before any of my edits, already used `make setup-cluster` style commands) — flagging for the Architect to decide whether VI is meant to be read this literally for infra stories, or whether spec.md needs a rewrite into outcome language with the commands moved to plan.md/quickstart.md. |
| **VII. Plain Language Everywhere** | ✗ Fails as written | Terms like "LoadBalancer", "VirtualService", "taint", "toleration", "Helm chart" appear without a first-use plain-language explanation, as VII requires. Same status as VI — real gap, not fixed by this pass. |
| **VIII. Try It Before You Plan It** | ✗ Fails currently | No one has actually been asked for AKS/subscription access yet (see Blocker section above). Per VIII, "no access is a blocker, not a licence to substitute" — the required next step is to ask and record who/what, not to proceed on dry-run alone. Phase 1 dry-run work (helm template, chart search) is a legitimate placeholder for the *cheap* checks, but the substitute for full cluster verification has not been asked for or approved by the Architect yet, as VIII requires. |
| **IX. Author In Steps, Developer in the Loop** | ✗ Fails currently | This spec/plan/tasks/research were produced as complete documents across multiple passes, not proposed and approved one section at a time with explicit developer sign-off per section, as IX requires. |
| **X. Converge to the Agreed Scope, Then Stop** | N/A | Not yet applicable — no implementation exists yet for convergence to check against. |

**Two failures (VIII, IX) and one open question (V) are real, not decorative.** The previous two rounds' Constitution Checks scored everything ✓ against a document that either didn't match the real constitution or wasn't read critically. A check that never returns a failure isn't checking anything — these are recorded as failures because they are failures, and resolving them (asking for access; running future authoring in sections) is process work for the team, not something I can retroactively fix by rewriting this document again.

---

## Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Istio 1.30.4 introduces breaking changes vs. EKS's 1.17.2 | HIGH | T001: Validate YAML configs via `helm template` before any cloud runs; T002: Test charts in CI before PR merge |
| Load-balancer provisioning timeouts on first AKS deployment | MEDIUM | T006: `HELM_TIMEOUT=5m` in `.env`; T006: Wait for Service to have external IP before proceeding |
| Cluster not ready (story #97 dependency) | MEDIUM | Not yet asked (see Blocker above); Phase 1 dry-run validation (helm template, lint) proceeds without cluster access in the meantime |
| Helm chart namespace mismatch (istiod vs. gateway in different namespaces) | LOW | T004: All three helm installs target `--namespace istio-system` explicitly |

---

## Verification (quickstart.md provided separately)

Commands run on AKS cluster post-deployment:

1. **Istio install complete**: `kubectl get pods -n istio-system` → all control-plane pods Running
2. **Gateway deployed**: `kubectl get svc -n istio-system` → `istio-ingressgateway` has external IP
3. **Routes exist**: `kubectl get vs -A | grep istio` → gateway routes are present
4. **Endpoints work**: `curl http://<LB_IP>` → gateway answers on port 80
5. **Second setup idempotent**: `make setup-istio` (again) → exits 0, no "created" or "installed" output
6. **Cleanup works**: `make cleanup-gateway && make cleanup-istio` → all resources deleted; `kubectl get all -n istio-system` empty
7. **Cleanup idempotent**: Run cleanup again → exits 0, no "not found" errors
8. **EKS unchanged**: `git diff main -- makefile | grep -i eks` → no changes to EKS targets

---

## Deviations from spec (will be updated as reality diverges)

*None yet. This is the first implementation pass.*
