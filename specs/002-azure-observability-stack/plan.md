# Plan: 002-azure-observability-stack

**Status**: Draft — content complete 2026-09-28, awaiting `/speckit-tasks`, `/speckit-analyze`, and `gate:plan-approved`

**Spec**: [spec.md](./spec.md) · **Research**: [research.md](./research.md)

## Summary

Give AKS its own observability command (mirroring the cluster-only pattern the other AKS stories already established), install Prometheus/Grafana/Loki with an AKS-specific, latest-GA Loki pin, skip the metric-server step that collides with AKS's built-in one, and reuse Kiali's existing cross-platform manifest unmodified — proven live to work against AKS's Istio 1.30.4 — through its own separate command so a missing mesh never blocks the core stack.

## Approach

1. **New AKS observability target**, `setup-aks-o11y` (mirrors `setup-local-o11y`'s naming), chaining: `setup-db-grafana-psql setup-kube-prometheus-stack setup-loki-aks setup-aks-o11y-routes setup-dashboards`. No `setup-metric-server` (research.md Phase 0 summary #2: AKS's built-in addon already serves the same API; installing a second one collides on `ClusterRole system:metrics-server`, proven live in story 004's research against this exact cluster). No Tempo/Beyla/Caretta (out of scope).
2. **New target `setup-loki-aks`**, values file at `infra/azure/chart-values/loki.yaml` (reuses the existing Azure-specific folder from story 001, satisfying FR-008's "own folder" rather than inventing a second Azure folder under `monitoring/`). Chart `loki` pinned at `18.13.5` from the `grafana-community/helm-charts` repo (research.md finding 12 — confirmed via ArtifactHub 2026-09-25; the old `grafana/helm-charts` chart depends on Promtail/Grafana Agent, both past EOL). AWS/local's `setup-loki` target and `monitoring/chart-values/loki.yaml` stay untouched (FR-007/FR-017).
3. **New target `setup-aks-o11y-routes`**: applies only `monitoring/istio-observability-addons/grafana-vs.yaml`, `prometheus-vs.yaml`, `istio-podmonitor.yaml`, `istio-servicemonitor.yaml` — the same files EKS/local already use via `setup-istio-o11y-addons`, unmodified, applied individually rather than via that whole-folder target. These four need only Istio's CRDs (already installed by `setup-istio`), not istiod actually running, so they ride with the core stack, ungated by mesh readiness (FR-005: reachability, not install, is what depends on the mesh/routing step).
4. **New target `setup-kiali-aks`, separate from `setup-aks-o11y`**: checks the mesh is actually up (`helm status istiod -n istio-system`), refuses clearly if not (FR-013), then applies `monitoring/istio-observability-addons/kiali.yaml` + `kiali-vs.yaml` — the exact same shared files, unmodified. Research (L3/L4) proved these already carry the correct `nodeSelector`/toleration and run healthy against AKS's Istio 1.30.4 with no changes, so this story adds no new Kiali chart or version pin — only the AKS wiring and the mesh-readiness gate. `setup-istio-o11y-addons` itself (EKS/local's whole-folder apply) is untouched.
5. **Deployment check (FR-011)**: a new offline script, pattern-matched on `agent/tests/azure/`'s existing scenario/PASS-FAIL harness but asserting on YAML content (`nodeSelector`/`tolerations` fields) rather than a fake-CLI call log, verifies every AKS-specific chart-values/manifest file this story adds or wires in carries the `workload: o11y` selector and `o11y=true:NoSchedule` toleration before any live run.
6. **Existing cluster reconciliation**: the live cluster already has `loki`/`prometheus-stack`/`tempo`/`caretta` installed via the shared (non-AKS) chart pins, and `roboshop` already deployed (research.md L1) — both from earlier manual work, not this story's target. Implementation decides whether to reinstall Loki under the new `setup-loki-aks` target (likely, so the AKS-specific pin actually takes effect) — a tasks.md item, not a plan-level open question.

## Constitution check (v1.4.0)

| Principle | Satisfied? | Evidence |
|---|---|---|
| **I. Re-runnable Scripts** | ✓, pending task detail | `kubectl apply` and `helm upgrade --install` are idempotent by construction; `setup-kiali-aks`'s mesh-readiness check is a read before act, not a mutation. Exact re-run behavior for the three new targets gets its own tasks.md verification task, same pattern as story 004's plan. |
| **II. Pinned Versions** | ✓ | Loki `18.13.5` newly pinned (research.md finding 12, ArtifactHub-verified today). Kiali stays at its existing pin (`v1.63.1`, unchanged, proven compatible live — L3/L4). Istio (`1.30.4`) untouched, owned by story 003. |
| **III. One Configuration Surface** | ✓ | New chart-values files (`infra/azure/chart-values/loki.yaml`) follow the repo's existing `*/chart-values/` mechanism per-tool settings live outside `.env` by design (Principle II's own exception); no new hand-edited values, no new required `.env` keys beyond what story 001 already added. |
| **IV. No Secrets in Git** | ✓ | No new credentials introduced. Grafana's admin account/password handling is unchanged from the existing setups (spec Assumptions). |
| **V. Workload Placement Contract** | ✓, verified live for Kiali | Kiali's pod confirmed running on an `o11y` node (research.md L4). The new `loki.yaml` mirrors the exact `nodeSelector: workload: o11y` / `tolerations: [o11y=true:NoSchedule]` shape already proven in `monitoring/chart-values/loki.yaml:23-28,46-49` — not yet re-verified live for the new file specifically, since it doesn't exist yet; that's a tasks.md verification step once `setup-loki-aks` is implemented. |
| **VI. Specs Without Technical Detail** | ✓ | `spec.md` re-checked clean (no chart/target/manifest names, no `[NEEDS CLARIFICATION]` markers) after the 2026-09-25 revision. |
| **VII. Plain Language Everywhere** | ✓, plan-appropriate density | This plan uses technical terms (Helm, `kubectl`, `ClusterRole`, `nodeSelector`) at the same density story 004's approved plan did, on the same reasoning: this document's audience is the Architect/Builder, not a newcomer; `spec.md` carries the plain-language obligation for this story, and does. |
| **VIII. Try It Before You Plan It** | ✓✓ | Every claim in this plan traces to `research.md`'s L1–L4 live command output against the real AKS cluster (node placement, gateway/routing state, the metrics-server collision reused from story 004's own live run, Kiali's actual health and node placement) — not memory or documentation. |
| **IX. Author In Steps, Developer in the Loop** | ✓ so far | `research.md`'s findings were proposed and confirmed one at a time with real output attached; this plan's Summary/Approach section was proposed, approved, then written; this Constitution Check section followed the same loop. |
| **X. Converge to the Agreed Scope, Then Stop** | N/A yet | No implementation exists yet to converge against. |

**Complexity table**: none — no principle violation to justify at this point.

## Files changing

| File | Change | Rationale |
|---|---|---|
| `makefile` | Add `setup-aks-o11y`, `setup-loki-aks`, `setup-aks-o11y-routes`, `setup-kiali-aks` targets. Add a `STACK_MODE=aks`-specific branch to `get-service-endpoints`, checked before the existing `APP_STACK`-based branches, printing Grafana/Prometheus/Kiali URLs — existing EKS/local branches untouched. Add corresponding `make help` lines. | FR-001/002/004/005/010/018; FR-017 (EKS/local unchanged) |
| `infra/azure/chart-values/loki.yaml` (new) | Loki values for AKS: chart `loki` `18.13.5` from `grafana-community/helm-charts`, mirroring the exact `nodeSelector: workload: o11y` / `tolerations: [o11y=true:NoSchedule]` shape from `monitoring/chart-values/loki.yaml:23-28,46-49`. | FR-007, FR-002, FR-008 |
| `infra/scripts/cluster/setup-kiali-aks.sh` (new) | Checks `helm status istiod -n istio-system` before applying the existing `kiali.yaml`/`kiali-vs.yaml` unmodified; refuses with a plain message if the mesh isn't up. A dedicated script (not an inline recipe) so it's unit-testable the same way `setup-cluster-aks.sh`/`verify-cluster-aks.sh` already are. | FR-013, FR-018 |
| `agent/tests/azure/check-observability-placement.sh` (new) + scenarios | Offline, no-cluster check asserting `nodeSelector`/`tolerations` on every AKS-specific monitoring file this story adds — new assertion style alongside the existing fake-CLI harness, not a modification of it. | FR-011 |
| `docs/architectural-decisions.md` | New ADR: skip `setup-metric-server` on AKS (reuse the platform's own addon) rather than fix the `ClusterRole` collision; reuse Kiali's existing manifest unmodified rather than a separate AKS pin — both proven live in research.md. | FR-016 |
| `README.md`, `AGENTS.md` | Document the new AKS observability commands and run order (cluster → istio → gateway → `setup-aks-o11y` / `setup-kiali-aks`). | FR-015 |

No new cleanup script is needed — AKS's existing `cleanup: cleanup-cluster` already tears down everything this story adds (FR-014 satisfied for free, since cleanup is a full cluster teardown). No new `.env` keys are needed either — everything reuses `MONITORING_NS` and the existing required-vars list.

## Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| The live cluster already has `loki`/`prometheus-stack`/`tempo`/`caretta` installed under the shared (non-AKS) chart pins (research.md L1) — running the new AKS-specific targets could collide with these exploratory releases, same failure class as story 004's `roboshop`/`robot-shop` release-name collision | HIGH | `helm uninstall loki -n monitoring` (the exploratory release) before implementation's first real `make setup-loki-aks` run — same playbook 004 used. Add as an explicit tasks.md item. |
| `setup-kiali-aks`'s mesh-readiness check uses `helm status istiod` — a Helm release can show `deployed` even if the pod itself is unhealthy, so this could be a false-positive readiness signal | LOW-MEDIUM | Note as an option to strengthen (e.g. `kubectl rollout status deployment/istiod`) during implementation if the simple check proves flaky in practice; not blocking the plan. |
| `setup-aks-o11y-routes` names four files individually rather than applying the whole `monitoring/istio-observability-addons/` folder like EKS/local do — a future edit to that shared folder (new file, renamed file) could silently not reach AKS | MEDIUM | Document the coupling explicitly in the new ADR and with an inline makefile comment pointing back to it. No automated drift check proposed for this story — a known, accepted limitation, not solved here. |
| Loki's chart moved to `grafana-community/helm-charts` very recently (2026-03-16) — a new, less battle-tested dependency | LOW | Exact version (`18.13.5`) pinned and verified same-day via ArtifactHub; the OCI path (`oci://ghcr.io/grafana-community/helm-charts/loki`) is a documented fallback if the classic repo add has issues during implementation. |
| Skipping `setup-metric-server` entirely on AKS assumes nothing needs a self-installed metrics-server specifically (vs. AKS's built-in one) | LOW | AKS's built-in addon already serves the standard `metrics.k8s.io` API (confirmed live, 2/2 Running, standard ClusterRole) — what `kubectl top`/HPA actually consume. Nothing this story needs is lost. |
| `roboshop` (Robot Shop) is already running on this cluster from earlier work, outside this story's scope | LOW | Informational only — this story deploys no app workloads; existing app traffic showing up in dashboards early is a bonus, not a defect, but implementation must avoid touching robot-shop's own resources. |

## Verification

1. **Core stack up (US1)**: `kubectl get pods -n monitoring` → Prometheus, Grafana, Loki pods `Running`/`Ready`; `kubectl get pods -n monitoring -o wide` → all on `o11y` nodes except any log-shipper DaemonSet pods.
2. **Deployment check (FR-011)**: `agent/tests/azure/check-observability-placement.sh` exits 0 with no live cluster.
3. **Reachability (FR-004/FR-005)**: `make get-service-endpoints` under `STACK_MODE=aks` prints Grafana and Prometheus URLs; `curl -sI http://<LB_ENDPOINT>/grafana` and `/prometheus` both return `200`.
4. **Dashboards healthy (FR-006)**: open Grafana, confirm Prometheus and Loki datasources report connected/healthy.
5. **Kiali (US2)**: `make setup-kiali-aks` → pod `Running` on an `o11y` node; `curl -sI http://<LB_ENDPOINT>/kiali/` → `200`.
6. **Mesh-gating (FR-013/SC-009)**: on a cluster with Istio torn down, `make setup-kiali-aks` stops with a clear message; `make setup-aks-o11y` still succeeds independently.
7. **Idempotency (FR-003)**: re-run `make setup-aks-o11y` and `make setup-kiali-aks` → both exit 0, no new resources.
8. **Live verification check (FR-012)**: run against the freshly-verified cluster, reports all workloads on `o11y`, both datasources healthy.
9. **EKS/local unaffected (FR-017)**: `git diff main -- makefile monitoring/ infra/` shows only AKS-scoped additions; existing `setup-observability`/`setup-local-o11y` targets byte-identical.
10. **`make lint` passes** with no new errors.
