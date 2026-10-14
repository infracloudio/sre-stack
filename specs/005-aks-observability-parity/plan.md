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
makefile                                                       # amend setup-aks-o11y chain; add setup-aks-tempo/beyla/caretta/prometheus-stack; STACK_MODE=aks branches in setup-db-grafana-psql/setup-robot-shop/setup-hotrod
infra/azure/chart-values/tempo.yaml                            # NEW — Tempo 3.1.0 values (o11y placement, fresh image, receivers default)
infra/azure/chart-values/beyla.yaml                            # NEW — Beyla 1.16.11 values (tolerations+spot, /sys/fs/bpf hostPath, otel→tempo:4318)
infra/azure/chart-values/caretta.yaml                          # NEW — Caretta 0.0.16 values (memory 512Mi, deps disabled, tolerations+spot)
infra/azure/chart-values/prometheus-stack.yaml                 # NEW — overlay: Tempo datasource :3200 + caretta/beyla scrape jobs + spot tolerations
infra/scripts/cluster/setup-aks-o11y-routes.sh                 # AMENDED — skip all four files, exit 0, when the mesh is absent (see "No-mesh routes step")
agent/tests/azure/check-o11y-routes-offline.sh                 # NEW — offline test of that skip (fake kubectl), called from make lint
infra/scripts/cluster/azure-common.sh                          # AMENDED — default location eastus2 → southindia (see "Default Azure location")
agent/tests/azure/{fake-az.sh,run-offline-tests.sh,scenarios/bad-location.sh}  # AMENDED — fake az lists the configured location; bad-location uses made-up names
specs/002-azure-observability-stack/instructions.md            # AMENDED — "leave empty for southindia"
scenarios/load-gen/load.yaml                                   # REFORMATTED only (yamllint); spot toleration moved to the AKS copy below (see "Spot-mode tolerations")
infra/azure/load-gen/load.yaml                                 # NEW — AKS copy of the load generator with the spot toleration
infra/azure/grafana-postgres/{statefulset,job}.yaml            # NEW — AKS copies of monitoring/grafana-postgres with the spot toleration
infra/azure/chart-values/robot-shop.yaml                       # NEW — AKS values overlay: spot toleration on all 13 robot-shop workloads
infra/azure/hotrod/kustomization.yaml                          # NEW — AKS kustomize overlay on app/hotrod: spot toleration
infra/azure/chart-values/{loki,otel-collector}.yaml            # AMENDED — spot toleration
infra/azure/kiali/kiali.yaml                                   # AMENDED — spot toleration (CR + Deployment)
specs/005-aks-observability-parity/instructions.md            # NEW — reviewer guide: own AKS cluster from scratch, deploy, check (SC-010); commands defer to quickstart.md
monitoring/grafana-postgres/, app/robot-shop/, app/hotrod/     # UNTOUCHED (shared — AKS uses the copies/overlays above)
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

## Implementation departures (2026-10-14)

Small differences between tasks.md and what was done; none changes scope.

- **Chain line number.** The `setup-aks-o11y` chain sits on makefile line 188,
  not 187: the comment above it gained one line when "no Tempo/Beyla/Caretta
  (out of scope)" was rewritten. Task `sed -n '187p'` checks apply to line 188.
- **Rendered scrape jobs are base64.** kube-prometheus-stack 52.0.0 renders
  the inline `additionalScrapeConfigs` into a Secret
  (`prom-...-prometheus-scrape-confg`, key `additional-scrape-configs.yaml`),
  so T010's `grep -c "caretta\|beyla"` on the raw render returns 0. The
  proof is the decoded Secret value: both job blocks present, no
  `__meta_kubrnetes` string.
- **Charts rendered from local tarballs.** The GitHub release-asset CDN
  timed out fetching kube-prometheus-stack 52.0.0 by repo reference (the
  flakiness research.md Finding 3 names). The four pinned charts were
  fetched with `helm pull --version <pin>` and `helm template` ran on those
  tarballs. The pins did not move.
- **Datasource count.** The T002 render shows four datasources in the Grafana
  provisioning ConfigMap: Prometheus and Alertmanager (generated by the chart)
  plus the two from the overlay (loki, Tempo).
- **Spot toleration sweep.** Found live on 2026-10-14 and larger than a
  departure; see "Spot-mode tolerations" below.
- **`AGENTS.md` AKS entry.** Convergence (2026-10-14, finding F1, FR-012)
  found it still said AKS "does not install Tempo, Beyla, or Caretta" with
  two per-machine helpers. Corrected in this story so agents stop treating
  the new chain and the four helpers as mistakes.
- **Reviewer guide `instructions.md`.** Not in the original file list;
  added for SC-010 so a reviewer can build their own cluster and run the
  checks. Kept by the owner after convergence (2026-10-14, finding F3).
  Exact commands live in `quickstart.md`; if one changes, update the other.
- **Beyla application lags the chart (review of bbe4244, 2026-10-14).**
  Chart 1.16.11 is the latest Beyla chart and ships application 3.32.0;
  the latest application release is v3.38.0 (2026-10-05). Accepted by the
  owner: the gap is minor releases within 3.x. 3.32.0 ran clean on AKS 1.34
  (about 6,390 requests counted, traces in Tempo). Overriding the image away
  from the chart's tested pairing adds risk for no gain this story needs.
  Bumping the image is left to a future chart release or a separate story.
- **Live no-mesh proof moved to a follow-up story (review of bbe4244,
  2026-10-14).** T016 clause (a) needs a cluster with `istio-system` absent,
  which `make setup-aks` never produces. The owner cancelled it here. For
  this story, FR-006 and SC-004 rest on the offline proof in
  `check-o11y-routes-offline.sh` (missing VirtualService type and missing
  namespace both skip; a kubectl failure fails). The live run on a cluster
  without the mesh becomes its own story.

## Spot-mode tolerations (live finding, 2026-10-14)

**Why it was required.** The cluster re-provisioned for T016 came up in spot
mode (AD-002: spot whenever the subscription's spot allowance fits). Azure
then puts `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` on every
node outside the system pool, and Azure does not allow removing it. The first
`make setup-aks` stopped at `setup-db-grafana-psql`:
`postgresql-psql-0` stayed `Pending` with `0/9 nodes are available: 1
node(s) didn't match Pod's node affinity/selector, 8 node(s) had untolerated
taint(s)`. Every other workload the AKS path pins to the app, persistent, o11y
or loadgen pool would have failed the same way. AD-003 already requires these
workloads to tolerate the spot taint. The manifests predated spot mode,
because earlier clusters ran on regular (non-spot) VMs, which carry no such
taint. Without this fix, FR-001, FR-011 and SC-009 cannot pass on a spot-mode
cluster.

**Decision (owner, 2026-10-14).** The spot toleration goes only into files
that AKS alone reads. Shared EKS/local files stay as they were (FR-007,
FR-008, SC-005, SC-006). Where AKS used a shared file, it now gets its own
file, which the makefile picks when `STACK_MODE=aks`:

| Workload | AKS-only file | Picked by |
|---|---|---|
| Grafana postgres StatefulSet + DB job | `infra/azure/grafana-postgres/{statefulset,job}.yaml` (copies of `monitoring/grafana-postgres/`) | `setup-db-grafana-psql` via `GRAFANA_PSQL_DIR` |
| robot-shop, all 13 workloads | `infra/azure/chart-values/robot-shop.yaml` (values overlay; persistent-pool entries restate the `persistent` toleration because Helm replaces lists) | `setup-robot-shop`, new `aks` branch |
| hotrod | `infra/azure/hotrod/kustomization.yaml` (kustomize overlay on `app/hotrod`) | `setup-hotrod`, `aks` branch |
| load generator | `infra/azure/load-gen/load.yaml` (copy) | the hint `setup-aks` prints; quickstart step 3 |
| prometheus-stack (Grafana, Prometheus, operator, kube-state-metrics, Alertmanager) | `infra/azure/chart-values/prometheus-stack.yaml` (existing overlay) | `setup-aks-prometheus-stack` |
| Loki, OTel collector, Kiali (CR + Deployment) | their existing `infra/azure/` files | unchanged targets |

Already fine: Tempo, which tolerates spot explicitly; Beyla, Caretta and
Alloy, which tolerate every taint (`operator: Exists`); node-exporter, whose
chart default tolerates everything; Istio and the prometheus-stack admission
jobs, which run on the untainted system pool. Scenario-04 is EKS-only (its
script calls `eksctl`), so it is untouched.
`scenarios/load-gen/load.yaml` keeps `main`'s content. Only its indentation,
a leading `---` and a trailing newline differ, because `main`'s copy fails
`make lint`'s yamllint step. Its behaviour on EKS/local is unchanged.

**What we gave up.** The postgres manifests and `load.yaml` now exist twice,
so a change to either must be made in both copies; each AKS copy's header
says so. robot-shop and hotrod use overlays, so they cannot drift.

**Live fix already applied.** On the 2026-10-14 cluster, the psql
StatefulSet was patched in place with the same toleration and its pod
recreated (`1/1 Running` on an o11y node). The stuck
`create-grafana-database` Job was deleted and re-applied, and printed
`CREATE DATABASE`.

**Convergence directive (owner decision, overrides `/speckit-converge`).**
The files in the table above, the `STACK_MODE=aks` makefile branches, the
AKS copies' duplication, and the shared `load.yaml` lint-only reformat are
approved, in-scope work (FR-014, T019). Convergence MUST NOT report them as
scope creep, unplanned work, an FR-007/FR-008/SC-005/SC-006 violation, or
duplication to remove. It MUST NOT append tasks that revert, merge,
deduplicate or move them into shared files. A convergence finding that
contradicts this section is overruled.

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
