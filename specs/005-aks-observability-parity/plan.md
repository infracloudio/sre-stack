# Implementation Plan: Complete Azure Application Observability

**Branch**: `005-aks-observability-parity` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-aks-observability-parity/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Story 005 adds the three application-observability capabilities that story 002
left out of scope on AKS: service mapping (Caretta — feeds the existing
`Service Map ☸️` panel via `caretta_links_observed`), request tracing
(Tempo, with Beyla exporting spans to it), and automatic application
measurements (Beyla). Wired into the existing
Grafana stack. Today the AKS chain `setup-aks-o11y` installs none of them, and
Grafana carries a Tempo datasource pointing at a nonexistent service. The
approach follows the EKS/local shapes (chart installs with Azure-specific
values files under `infra/azure/chart-values/`), pinned to the latest stable
releases verified live during planning, placed per the workload contract
(per-node collectors on every node, the rest on `workload=o11y`), with no
service-mesh prerequisite added.

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Bash (repository scripts), GNU make, Helm 3, kubectl.
Target clusters: Azure AKS. Current kubeconfig context is stale — the research
cluster `sre-stack-452138` (southindia, Kubernetes **1.34.11**, verified live
2026-10-09) was deleted after research; re-provision one (`make setup-aks`) at
implementation time before any live task.

**Term explanations (principle VII, first use)**:
- **eBPF** — a kernel-side program hook that lets a pod observe and encode
  network traffic and request work of the node's own processes without
  changing the app.
- **OTLP** — OpenTelemetry's wire protocol; the standard endpoint (here
  Tempo's, port 4317 gRPC/4318 HTTP) that tracing exporters push spans to.
- **DaemonSet** — a Kubernetes workload kind that schedules exactly one pod
  on every node; how per-node collectors (Beyla, Caretta, Alloy,
  node-exporter) get full-fleet coverage.
- **hostPath** — a volume that mounts a node directory (here `/sys/fs/bpf`)
  into the pod, needed when a tool must reach kernel state rather than
  process state.
- **prometheus scrape job** — the Prometheus-side periodic pull of a metrics
  HTTP endpoint; jobs defined here live in the kube-prometheus-stack values.

**Primary Dependencies**:
- **Tempo chart 3.1.0** (app 3.1.0, `grafana-community/tempo`; the
  `grafana/tempo` 1.24.4 entry is deprecated — research.md Finding 1).
  Tracing backend. Verified latest stable against live repo
  (`helm search repo grafana-community/tempo --versions`), 2026-10-09.
- **Beyla chart 1.16.11** (app 3.32.0) — eBPF request tracing export +
  automatic application measurements. Verified latest stable against live
  `grafana` repo, same date.
- **Caretta chart 0.0.16** (app v0.0.16) — service map (EKS/local
  incumbent; also the Service Map panel's data source on AKS — research.md
  Finding 3 showed Beyla has no `caretta_links_observed` equivalent).
  Verified latest stable against live `groundcover` repo, same date.
- kube-prometheus-stack **52.0.0** (already installed on AKS), Grafana as the
  map/trace/metrics UI.
- AKS gets its own values files under `infra/azure/chart-values/`; these picks
  never change EKS/local settings (FR-008).

**Verified live cluster state (2026-10-09) — HISTORICAL, cluster deleted**: the
research cluster `sre-stack-452138` was deleted the evening of 2026-10-09
(kubeconfig DNS no longer resolves — confirmed 2026-10-09, analysis run).
Facts below are the date's findings; numbers are re-provable only by
re-provisioning. Acceptance evidence (SC-002 etc.) regenerates live during
implementation — quickstart.md + T016 own that.
- Five pools: `nodepool1` (system, no workload label, no taint), app×3,
  persistent×2, o11y×2, loadgen×1. Every non-system pool labelled `workload=`
  and tainted to match.
- **Every node carries the spot taint
  `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`** — all new
  workloads MUST tolerate it, in addition to the pool taints (developer
  requirement added at plan approval).
- Existing per-node precedent: Alloy DaemonSet and node-exporter already run
  on all 9 nodes including the label-less system pool.
- Grafana datasource `Tempo → http://tempo.monitoring:3100` already exists and
  dangles (no tempo service) — the story wires it to a real Tempo install.

**Storage**: no new StorageClass; contract stays `gp2` (principle V). Grafana
backed by the existing `monitoring/grafana-postgres/` statefulset.

**Testing**: `make lint`; `helm template`/`helm lint` for chart changes; live
SC-002 traffic-run verification per principle VIII.

**Target Platform**: Azure AKS, node pools `workload=app|persistent|o11y|loadgen`.

**Project Type**: Infrastructure-as-YAML + make orchestration (no runtime code).

**Scale/Scope**: amends the AKS observability chain (`setup-aks-o11y` and the
one-command `setup-aks`), adds per-node collectors on every pool and the
remaining workloads on `workload=o11y`, updates the Azure deployment
instructions (FR-012).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* *(approved by developer 2026-10-09)*

| Principle | Status | Why |
|---|---|---|
| I. Re-runnable scripts | ✅ | Helm `upgrade --install` is idempotent — directly serves FR-010/FR-011. |
| II. Pinned versions | ✅ (with note) | New AKS installs get explicit `--version` pins (Tempo 3.1.0 community chart, Beyla 1.16.11, Caretta 0.0.16, prometheus-stack 52.0.0). Note: existing `setup-tempo`/`setup-caretta` (EKS/local) have **no** chart pin today — FR-007 forbids touching them, so they stay as-is; this story does not copy that gap. |
| III. One configuration surface | ✅ (amended 2026-10-09, analysis run) | Fixed chart settings (image tags, receiver ports, placement, scrape jobs) are chart-shape facts and stay in the pinned values files under `infra/azure/chart-values/`; operator tunables live in `.env` — this story adds **zero** new `.env` keys (no new credentials, no new toggles; the release/namespace variables the targets read are the existing ones). |
| IV. No secrets | ✅ | No new credentials. |
| V. Workload placement | ✅ (with note) | Beyla + Caretta DaemonSets run on every node with explicit tolerations for `app/persistent/o11y/loadgen` and the spot taint `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` (developer requirement; verified live every node carries it). Tempo and all other added workloads restricted to `workload=o11y`. No new StorageClass (contract stays `gp2`). |
| VI. Specs without technical detail | ✅ | Approved spec contains no tech; technology lives here. |
| VII. Plain language | ✅ (amended 2026-10-09, analysis run) | Jargon gets first-use explanations (see Technical Context term block); the original row treated the docs as already-jargon-free, which the analysis run showed was not true for eBPF/OTLP/DaemonSet/hostPath. |
| VIII. Try it before you plan it | ✅ (amended 2026-10-09, analysis run) | Planning-time live runs followed principle VIII on the research cluster `sre-stack-452138` (deleted the same evening — see Technical Context). Findings 1–4 in `research.md` carry real command output where the run produced printable blocks; some claim lines summarize without the full paste (analysis finding C3) and now carry reproduction commands so implementation re-proves each one live, on a re-provisioned cluster. |
| IX. Author in steps | ✅ | Section-by-section authoring with developer approval performed throughout. |
| X. Converge to agreed scope | ✅ | Spec closed with 5 edge cases; SC-001–SC-011 are the exit criteria. |

**Gate: PASS — no violations. Complexity table stays empty.**

Honest flag, not a violation: existing Beyla on EKS/local is raw manifests at image 1.3.0; AKS runs the chart at 1.16.11. That is a deliberate new shape on Azure only (FR-008), not drift.

## Project Structure

### Documentation (this feature)

```text
specs/005-aks-observability-parity/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output — live-cluster findings 1–4
├── data-model.md        # Entities, validation rules, live-traced flow
├── contracts/make-targets.md   # Make-target interface contract
├── quickstart.md        # Reviewer validation runbook (SC-002 etc.)
└── tasks.md             # Phase 2 output (/speckit-tasks — not yet)
```

## Files To Change

```text
makefile                                                       # amend setup-aks-o11y chain; add setup-aks-tempo/beyla/caretta/prometheus-stack
infra/azure/chart-values/tempo.yaml                            # NEW — Tempo 3.1.0 values (o11y placement, fresh image, receivers default)
infra/azure/chart-values/beyla.yaml                            # NEW — Beyla 1.16.11 values (tolerations+spot, /sys/fs/bpf hostPath, otel→tempo:4318)
infra/azure/chart-values/caretta.yaml                          # NEW — Caretta 0.0.16 values (memory 512Mi, deps disabled, tolerations+spot)
infra/azure/chart-values/prometheus-stack.yaml                 # NEW — overlay: Tempo datasource :3200 + caretta/beyla scrape jobs
infra/scripts/cluster/setup-aks-o11y-routes.sh                 # AMENDED — skip all four files, exit 0, when the mesh is absent (see "No-mesh routes step")
agent/tests/azure/check-o11y-routes-offline.sh                 # NEW — offline test of that skip (fake kubectl), called from make lint
infra/scripts/cluster/azure-common.sh                          # AMENDED — default location eastus2 → southindia (see "Default Azure location")
agent/tests/azure/{fake-az.sh,run-offline-tests.sh,scenarios/bad-location.sh}  # AMENDED — fake az lists the configured location; bad-location uses made-up names
specs/002-azure-observability-stack/instructions.md            # AMENDED — "leave empty for southindia"
scenarios/load-gen/load.yaml                                   # AMENDED at analysis run — spot-taint toleration added so the traffic generator schedules on AKS (finding I4); harmless on EKS/local
monitoring/dashboards/application.yaml                         # UNTOUCHED
monitoring/chart-values/prometheus-values.yaml                 # UNTOUCHED (shared — FR-007/FR-008)
```

## No-mesh routes step (review of 97f95fa, 2026-10-14)

**Problem.** FR-006, SC-004 and EC-002 require `make setup-aks-o11y` to
succeed with no service mesh installed, and T016 clause (a) proves it on a
cluster where `kubectl get ns istio-system` is empty. The chain cannot pass
that today. Its routes step, `setup-aks-o11y-routes`
(`infra/scripts/cluster/setup-aks-o11y-routes.sh`, from story 002), applies
four files and exits 1 if any fails, which stops the chain before
`setup-dashboards`:

| File | Kind | Namespace | Fails on a no-mesh cluster because |
|---|---|---|---|
| `grafana-vs.yaml` | VirtualService | monitoring | the Istio VirtualService type does not exist ("no matches for kind") |
| `prometheus-vs.yaml` | VirtualService | monitoring | same |
| `istio-podmonitor.yaml` | PodMonitor | istio-system | the `istio-system` namespace does not exist |
| `istio-servicemonitor.yaml` | ServiceMonitor | istio-system | same |

The review named the first two; the last two fail too (their types come
from kube-prometheus-stack, but their namespace comes from the mesh). Story
002 never hit this because its no-mesh check ran on a cluster that still had
Istio's types and namespace, with only `istiod` missing.

**Decision.** Keep FR-006/SC-004/EC-002 as written (no mesh at all) and
make the routes step mesh-aware, the same way `get-service-endpoints`
already handles missing routing (story 002, T025):

- Before applying, the script checks two things: the Istio VirtualService
  type exists (`kubectl get crd virtualservices.networking.istio.io`), and
  the `istio-system` namespace exists.
- If either is missing, it applies **none** of the four files, prints a
  plain message naming what is missing and the fix (run `make setup-istio`,
  then `make setup-aks-o11y-routes`), and exits 0. The rest of the chain
  continues.
- If both exist, it applies all four exactly as today, and still exits 1 if
  any apply fails.
- All four are skipped together rather than per file: the two monitors only
  scrape mesh components, so they are useless without the mesh, and one
  rule is easier to read and test.

Rejected: narrowing FR-006/SC-004/EC-002 to "control plane down, types
present". It weakens a requirement to fit the code, and T016 clause (a)'s
empty-`istio-system` proof would still fail.

This changes a story-002 script, but only on the AKS path (FR-008); EKS and
local never call it (FR-007). On the full `setup-aks` path nothing changes:
`setup-istio` runs before `setup-aks-o11y`, so the routes apply as before.
Task T018 makes the change and adds its offline test.

## Default Azure location (review of 97f95fa, 2026-10-14)

The research cluster's location (`southindia`) was committed to the shared
`.env`, which made every Azure offline test scenario refuse ("location
'southindia' is not a real Azure location for this account"), because the
test stand-in for `az` listed only `eastus2` and `centralindia`.

**Decision (developer, 2026-10-14):** keep `southindia`, as the built-in
default rather than a `.env` value. `.env` keeps `AZURE_LOCATION=` empty
(principle III: this story still adds and sets no `.env` values), and the
empty-value fallback in `infra/scripts/cluster/azure-common.sh` moves from
`eastus2` to `southindia`. The offline-test stand-in now lists whichever
location is configured (`FAKE_LOCATION`, read from `.env`, falling back to
`southindia`), and the bad-location case uses made-up names that no setting
can match, so the suite passes for any configured location. Verified: the
offline suite passes with `.env` empty (214 checks, 0 failed) and with
`AZURE_LOCATION=eastus2` (214, 0).

**Side effect to note in the PR:** the generated resource-group and cluster
names include the location. Anyone who created a cluster with an empty
`AZURE_LOCATION` before this change (an `eastus2` cluster) now gets
different names, so `make cleanup` no longer finds that cluster. They
should set `AZURE_LOCATION=eastus2` to clean it up, or delete it in the
portal.

## Verification Strategy

1. **Before any live run**: `make lint` (actual output attached to the PR,
   `evidence:attached`); `helm template`/`helm lint` on all four new values
   files; re-check targets with `grep -n "^setup-aks" makefile` before
   referencing them.
2. **Setup/idempotency** [FR-010/FR-011]: two successive
   `make setup-aks-o11y` runs succeed; review `helm list` before/after —
   no duplicate installs, same chart pins.
3. **Traffic results** [SC-002]: quickstart.md steps 3a/3b/3c on a
   recorded loadgen window: Service Map links > 0, TraceQL ≥1 openable
   trace, Beyla request-count metric > 0.
4. **Placement** [SC-011/FR-013]: pod-per-node counts per pool for beyla
   and caretta (every pool incl. spot and system); o11y-pool-only for
   tempo and the rest of the added monitoring workloads.
5. **Keep-working** [SC-003/FR-005]: Application Dashboard panels under
   equivalent traffic (error panels need error-producing traffic, A-003).
6. **Latest-stable record** [SC-007/FR-009]: chart-pins table from
   research.md copied into the PR description with verification dates.
7. **PR limitation note**: chart-CDN flakiness fallback (vendored tarball)
   named in the pull request, per research.md Finding 3.
8. **No mesh** [FR-006/SC-004/EC-002]: offline, `make lint` runs
   `check-o11y-routes-offline.sh` (skip with no VirtualService type, skip
   with no `istio-system`, apply all four when both exist). Live, T016
   clause (a): empty `kubectl get ns istio-system`, then a successful
   `make setup-aks-o11y` whose output contains the routes-skipped message.

## Complexity Tracking

No constitution violations — table stays empty (post-design re-check
approved by the developer; see research.md Findings 1–4 for the live
evidence that shaped these decisions).
