# Plan: 003-istio-gateway-kiali-aks

**Status**: Awaiting review & `gate:plan-approved` label

## Approach

Reuse the existing self-hosted Istio + ingress-gateway pattern already working on EKS/local. On AKS:

**Correction found this round, verified against the real makefile (`sed -n '74,90p'` and `sed -n '152,175p' makefile`)**: the plan previously assumed `setup-gateway` creates the ingress-gateway LoadBalancer. It does not, on EKS. `setup-istio`'s third Helm install (`istio/gateway` chart, makefile:78) creates the `istio-ingressgateway` Service that `get-service-endpoints` reads (confirmed: `grep -n LB_ENDPOINT makefile` shows it queries `svc istio-ingressgateway`). `setup-gateway` (makefile:152) does no Helm work at all — it only creates the `robot-shop` namespace and applies `app/robot-shop/Istio/gateway.yaml`, an app-specific route. The plan below reflects this corrected understanding:

1. **Setup Istio**: Extend the existing `setup-istio` target (makefile:74, currently EKS/local-only) with a `STACK_MODE=aks` branch that runs all three Helm installs in sequence (`istio-base`, `istiod`, and `istio/gateway` — the last of which creates the LoadBalancer), installing to the `istio-system` namespace with configuration pinned in `.env`. The existing EKS/local helm lines (makefile:76-78) are untouched.
2. **Setup gateway**: Extend the existing `setup-gateway` target (makefile:152) with an AKS branch. Since Robot Shop is out of scope for this story (#102), the AKS branch is a no-op. **Correction (independent audit)**: I previously justified this as "so `make setup` doesn't break" — false. Verified: the composite `setup:` target under `STACK_MODE=aks` (makefile:53-57) only calls `setup-cluster` today; it never calls `setup-istio` or `setup-gateway`. `setup-gateway` is a standalone target this story fixes for AKS (matching R1's pattern of extending existing EKS/local targets), invoked directly — not wired into the composite chain, which is deliberately scoped to cluster-only for now per the makefile's own comment. This story creates no VirtualServices (see R3 — routing is owned by later stories that also own the apps being routed to).
3. **Cleanup**: Create `cleanup-istio` (uninstalls all three Helm releases — base, istiod, gateway — mirroring what `setup-istio` installs) and `cleanup-gateway` (no-op on AKS, mirroring `setup-gateway`'s no-op setup, for symmetry). Verified via `grep -n "^cleanup-istio:\|^cleanup-gateway:" makefile` — no matches, both are new.
4. **Endpoints**: Update `get-service-endpoints` to fetch and print the AKS load-balancer external IP in the same format as EKS (stored in `LB_ENDPOINT` environment variable, read from the `istio-ingressgateway` Service that `setup-istio` created)

All scripts follow the check-then-create, re-runnable pattern already used by story #97 (AKS cluster setup).

## Resolved: Kubernetes 1.34 / Istio version split

**Status**: Resolved. See research.md §1-§2 for full evidence (version matrix, and the Architect's real Helm output) — not restated here to avoid the exact copy-drift that caused a contradiction in the previous round (plan.md claimed "verified" while research.md said "blocked", in the same commit).

**Issue that needed resolving**: Story #97 pins `AKS_KUBERNETES_VERSION=1.34`. Istio 1.17.2 (EKS/local's version) does not support Kubernetes past 1.26.

**Decision**: Pin Istio to `1.30.4` on AKS only. EKS/local remain on `1.17.2` (unchanged per R8). Confirmed as the newest currently-installable, CVE-clean, Kubernetes-1.34-compatible release — no 1.31.x chart is published yet.

## Blocker: AKS cluster availability

**Status**: Blocking verification phase (Phase 2 tasks only; Phase 1 dry-run validation can proceed now).

**Issue**: Story #97 (AKS cluster + node pools) is a dependency. **Correction (independent audit)**: I previously framed this as "blocked until PR #99 merges." That's misleading — verified directly against `main` (`git log main --oneline`, `ls infra/scripts/cluster/`): PR #98 already merged `setup-cluster-aks.sh`, `azure-common.sh`, and `verify-cluster-aks.sh` to `main`. The cluster-provisioning *code* already exists. PR #99 (`f/097/add_aks_support`) is a separate, still-open PR — I have not mapped out exactly how it relates to #98 (possibly a follow-on or parallel effort), and I'm not asserting a relationship I haven't verified. What I can say plainly: the real blocker is not a pending code merge. It's whether an actual AKS cluster has been *deployed* in a real Azure subscription — i.e., whether someone has run `make setup-cluster` (STACK_MODE=aks) for real — and whether Viknesh has access to that subscription/cluster.

**Who was asked**: Nobody yet. This is the honest current state, not a placeholder — per Principle VIII, the next action is to actually ask (not to substitute a guess). Action: ask the Architect/deployment lead for sandbox subscription access before Phase 2 tasks (T013 onward) begin.

**What is needed** (to state clearly once asked):
- Access to sandbox Azure subscription (Contributor role)
- Confirmation of whether an AKS cluster is already deployed (the code to create one is on `main` via PR #98) or still needs to be run

**Substitute**: None approved. Per Principle VIII, cheap read-only checks (chart names, versions, makefile targets, paths) never qualify for a substitute — all of those are verified directly in research.md. The end-to-end cluster verification (T013 onward) has no substitute and will wait for real access.

**Correction (independent audit caught this too)**: an earlier draft of this line claimed the limitation was stated in the PR #107 description. It was not — I fixed this claim in research.md §5 last round but missed this duplicate copy in this file, which is exactly the "one home per fact" habit this review keeps asking for and I keep half-doing. The real PR #107 description (checked directly) still reads `Closes: [link to issue #103 when you have it]` and says nothing about access, cluster status, or blockers. **This needs Viknesh to edit the actual PR description on GitHub** — not something any file in this repo can state into existence.

---

## Files changing

| File | Change | Rationale |
|---|---|---|
| `.env` | Add `ISTIO_VERSION=1.30.4` (AKS-only); add `ISTIO_NAMESPACE=istio-system` (shared); review existing EKS pins | Pin Istio version for cross-cloud consistency, with K8s 1.34 compatibility |
| `makefile` | Add `setup-istio` target with `STACK_MODE=aks` branch; add `setup-gateway` target with AKS branch; add `cleanup-istio` and `cleanup-gateway` | Drive AKS Istio/gateway via existing `make setup-*` interface |
| `infra/scripts/cluster/setup-istio-aks.sh` (new) | Helm repos + istio-base, istiod, gateway chart installs | Install Istio via Helm; check-then-create pattern |
| `infra/scripts/cluster/setup-gateway-aks.sh` (new) | **Correction (independent audit): this is a no-op**, not a Helm install. The `istio/gateway` chart (which creates the LoadBalancer Service) is installed by `setup-istio-aks.sh` above, not here — see the ownership correction earlier in this document. This script exits 0 and creates nothing, since Robot Shop (the only thing that would need an app-specific route here) is out of scope (#102). An earlier draft of this table row contradicted that decision; fixed here. | Standalone target parity with EKS's `setup-gateway`, which also does no Helm work |
| `infra/scripts/cluster/cleanup-istio.sh` (new) | Delete all three Helm releases — istio-ingressgateway, istiod, istio-base — since `setup-istio-aks.sh` is what installs all three (ownership correction above); tolerate already-gone | Idempotent cleanup; all Istio and gateway resources removed |
| `infra/scripts/cluster/cleanup-gateway.sh` (new) | **No-op**, mirroring `setup-gateway-aks.sh`. Nothing to delete since nothing is created. | Standalone target parity; symmetry with setup |
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

Checked directly against `.specify/memory/constitution.md`. The principle names below come from `grep -n "^### [IVX]*\." .specify/memory/constitution.md`, which lists the ten headings but not the version — that grep does not print a version number, and claiming it did was itself flagged in review round 3. The version comes from a separate, correct command: `tail -1 .specify/memory/constitution.md` → `**Version**: 1.4.0 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-17`. Unlike the two previous rounds, this check is not self-certifying — it is written after the fixes above, against the actual file, and four rows below genuinely fail.

| Principle | Satisfied? | Evidence |
|---|---|---|
| **I. Re-runnable Scripts** | Planned ✓ | Scripts (T004-T007, not yet written) are designed check-then-create; cleanup tolerates "not found". Not yet verified in code since implementation hasn't started. |
| **II. Pinned Versions** | ✓ | Istio 1.30.4 (AKS) / 1.17.2 (EKS, unchanged) pinned explicitly. New AKS helm calls add no inline `--set` flags (R10 resolved to system-pool default scheduling, no custom values needed). Note: the *existing* EKS helm line (makefile:77) already uses inline `--set` for tracing config — pre-existing, out of scope per R8, not introduced by this story. |
| **III. One Configuration Surface** | ✓ | ISTIO_VERSION, ISTIO_NAMESPACE, HELM_TIMEOUT all read from `.env`; no hand-edited values elsewhere. |
| **IV. No Secrets in Git** | ✓ | No credentials; all charts are public/open-source. |
| **V. Workload Placement Contract** | Ambiguous — flagging, not asserting | This principle requires workloads to use the `app\|persistent\|o11y\|loadgen` labels/taints. R10 places istiod/gateway on the AKS **system** pool, which is outside that four-pool taxonomy (it's AKS's own infra pool, not one of the four). Reading: Istio is platform infrastructure, not one of the four named workload categories, so this principle's labels don't apply to it — but that's an interpretation, not a settled fact, and I'm not confident enough to mark it ✓ outright. Needs Architect confirmation. |
| **VI. Specs Without Technical Detail** | ✗ Fails as written | `spec.md` currently contains commands and config throughout (`make setup-istio`, `STACK_MODE=aks`, `.env`, `curl <LB_ENDPOINT>`, `kubectl get all -n istio-system`). Principle VI says spec.md "MUST NOT hold technical material: no code, no config snippets... no commands." This spec violates that as literally written. This predates my involvement (the original spec, before any of my edits, already used `make setup-cluster` style commands) — flagging for the Architect to decide whether VI is meant to be read this literally for infra stories, or whether spec.md needs a rewrite into outcome language with the commands moved to plan.md and tasks.md (quickstart.md was deleted this round — see B2/B3 in review round 3; it had drifted from R10/R3 and its own checks passed by construction). |
| **VII. Plain Language Everywhere** | ✗ Fails as written | Terms like "LoadBalancer", "VirtualService", "taint", "toleration", "Helm chart" appear without a first-use plain-language explanation, as VII requires. Same status as VI — real gap, not fixed by this pass. |
| **VIII. Try It Before You Plan It** | ✗ Fails currently | No one has actually been asked for AKS/subscription access yet (see Blocker section above). Per VIII, "no access is a blocker, not a licence to substitute" — the required next step is to ask and record who/what, not to proceed on dry-run alone. Phase 1 dry-run work (helm template, chart search) is a legitimate placeholder for the *cheap* checks, but the substitute for full cluster verification has not been asked for or approved by the Architect yet, as VIII requires. |
| **IX. Author In Steps, Developer in the Loop** | ✗ Fails currently | This spec/plan/tasks/research were produced as complete documents across multiple passes, not proposed and approved one section at a time with explicit developer sign-off per section, as IX requires. |
| **X. Converge to the Agreed Scope, Then Stop** | N/A | Not yet applicable — no implementation exists yet for convergence to check against. |

**Four failures (VI, VII, VIII, IX) and one open question (V) are real, not decorative.** (Correction: an earlier draft of this sentence said "two failures" while the table above lists four — a copy that drifted from its own source two lines up, the same class of bug this whole review round is about. Fixed here.) The previous two rounds' Constitution Checks scored everything ✓ against a document that either didn't match the real constitution or wasn't read critically. A check that never returns a failure isn't checking anything.

## Complexity table (Governance, constitution.md:259-262)

Per Governance, each violation is either fixed before implementation or justified here and accepted by the Architect. Disposition for each:

| Principle | Disposition | Owner / next step |
|---|---|---|
| **VI. Specs Without Technical Detail** | Not fixed this round. Fixing it means rewriting spec.md's prose to move commands (`make setup-istio`, `curl <LB_ENDPOINT>`, etc.) into plan.md/tasks.md and restate requirements in outcome language. That's a judgment call about wording, not a fact I can verify with a command — and rewriting it unilaterally in one pass would repeat the exact IX violation below. **Requires Viknesh to run this through `/speckit-clarify` or an equivalent section-by-section pass, not a bulk edit.** |
| **VII. Plain Language Everywhere** | Same disposition as VI — first-use explanations for "LoadBalancer", "VirtualService", "taint", "toleration" are additive and lower-risk, but the principle asks for a document a newcomer can read alone, which is a genuine authoring pass, not a patch. **Requires Viknesh's pass, same as VI.** |
| **VIII. Try It Before You Plan It** | Not fixed — the one item in this whole PR that a command cannot close. Requires Viknesh to actually send the access request to the Architect/deployment lead today and record the reply in research.md §5. **Action item for Viknesh, not for any tool.** |
| **IX. Author In Steps, Developer in the Loop** | Cannot be fixed retroactively — these files were already written in full passes across multiple rounds. **Fixed going forward only**: the next authoring pass (re-running `/speckit-plan`/`/speckit-tasks` if either needs regenerating, or any future spec change) must use the incremental "one section, stop, wait" loop both SKILL.md files now require per PR #106. |
| **V. Workload Placement Contract** | Not a failure — an open interpretation question (is Istio a "workload" under the four-pool taxonomy, or platform infrastructure outside it?). **Requesting Architect's read on this**, not proposing to fix anything. |

**What I'm asking the Architect to accept**: VI/VII/VIII are real gaps this round did not close, for the reasons above (they need Viknesh's own judgment or Viknesh's own action, not something a command settles). I'm not asking for `gate:plan-approved` to be granted while pretending these are resolved — I'm asking whether the plan can proceed with VI/VII/VIII tracked as open commitments (with the concrete next step above for each), or whether the Architect wants VI/VII closed before that label is applied.

---

## Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Istio 1.30.4 introduces breaking changes vs. EKS's 1.17.2 | HIGH | T012 (moved to Phase 1, no cluster needed): `helm template` both versions and diff the rendered output before any cloud run. Correction: no CI job actually tests charts — the three real jobs on this PR are `lint and validate`, `azure offline tests`, and `gate:plan-approved check` (none render or test Helm charts) — so the mitigation is this local check, not a CI safety net that doesn't exist. |
| Load-balancer provisioning timeouts on first AKS deployment | MEDIUM | Correction (independent audit): `HELM_TIMEOUT=5m` is added to `.env` by **T001**, not T006 — T006 is `cleanup-istio.sh`, unrelated to this setting. Mitigation: T001 sets the timeout; T004/T005 use it; wait loop for external IP before proceeding. |
| Cluster not ready (story #97 dependency) | MEDIUM | Not yet asked (see Blocker above); Phase 1 dry-run validation (helm template, lint) proceeds without cluster access in the meantime |
| Helm chart namespace mismatch (istiod vs. gateway in different namespaces) | LOW | T004: All three helm installs target `--namespace istio-system` explicitly |

---

## Verification

quickstart.md was deleted this round (see B2/B3, review round 3) — it duplicated tasks.md T013-T020 and had drifted out of sync with R10 and R3 (expected istiod on the o11y pool; expected VirtualServices this story doesn't create). One home for verification steps now: tasks.md.

1. **Istio install complete**: `kubectl get pods -n istio-system` → all control-plane pods Running (T014)
2. **Gateway deployed**: `kubectl get svc -n istio-system` → `istio-ingressgateway` has external IP (T015)
3. **Endpoints work**: `curl http://<LB_IP>` → gateway answers on port 80; a 404 is an acceptable pass since this story creates no routes (S3; there is no "routes exist" check — that would fail by construction, exactly the mistake T019 avoids for the EKS-unchanged check below)
4. **Second setup idempotent**: `make setup-istio` (again) → exits 0, no "created" or "installed" output (T016)
5. **Cleanup works**: `make cleanup-gateway && make cleanup-istio` → all resources deleted; `kubectl get all -n istio-system` empty (T017)
6. **Cleanup idempotent**: Run cleanup again → exits 0, no "not found" errors (T018)
7. **EKS unchanged**: see T019 — the check must confirm the actual EKS helm lines are byte-unchanged, not merely that no line matching "setup-istio" changed (that fails by construction once this story extends the target)

---

## Deviations from spec (will be updated as reality diverges)

*None yet. This is the first implementation pass.*
