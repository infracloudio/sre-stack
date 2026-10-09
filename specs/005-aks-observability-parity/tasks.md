# Tasks: Complete Azure Application Observability

**Input**: Design documents from `/specs/005-aks-observability-parity/`

**Tests**: No test suite exists in this repo; verification is script/evidence-based per principle VIII (`make lint`, `helm lint`/`template`, live checks from `quickstart.md`). Verification commands appear inside each task.

**Term explanations (principle VII, first use — same terms as plan.md)**: **eBPF** — kernel-side program hook that lets a pod observe/encode the node's own processes' network traffic without touching the app; **OTLP** — OpenTelemetry's wire protocol for pushing spans (Tempo's mode, endpoint `:4317` gRPC/`:4318` HTTP); **DaemonSet** — Kubernetes workload that schedules exactly one pod on EVERY node (how per-node collectors get fleet coverage); **hostPath** — volume mounting a node directory (used here for `/sys/fs/bpf` so an eBPF tool reaches kernel state; kube-prometheus-stack scrape-job words self-explained inline).

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ground the work — confirm the pinned charts are real and findable from this repo's tooling before any file is written (principle VIII).

- [ ] T001 Verify the three chart pins resolve from the listed repos and record the output in the PR evidence: run `helm search repo grafana-community/tempo --versions | head -2` (expect chart 3.1.0), `helm search repo grafana/beyla --versions | head -2` (expect chart 1.16.11), `helm search repo groundcover/caretta --versions | head -2` (expect chart 0.0.16); if a repo is missing locally, `helm repo add` it first (`grafana-community https://grafana-community.github.io/helm-charts`, `grafana https://grafana.github.io/helm-charts`, `groundcover https://helm.groundcover.com/`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The AKS prometheus-stack install must move to the overlay shape before any new capability is installed, because Tempo and Beyla data become visible only through this stack's datasource and scrape wiring.

- [ ] T002 Create `infra/azure/chart-values/prometheus-stack.yaml` — AKS-only kube-prometheus-stack values overlay: redefines `grafana.additionalDataSources` as a complete list that KEEPS the existing Loki datasource (name `loki`, `http://loki:3100` — the error-log panels' data source, FR-005) and fixes the Tempo entry to `http://tempo.monitoring:3200` with its existing uid `EbPG8fYoz` preserved (research.md Finding 1: the `:3100` Tempo URL is broken; the uid is what the dashboard panels reference — changing it would orphan every panel's datasource references, FR-003 + FR-005). Also sets `podMonitorSelectorNilUsesHelmValues` only as far as the overlay needs; shared `monitoring/chart-values/prometheus-values.yaml` is NOT edited (FR-007/FR-008).
  Verify: `helm template prom prometheus-community/kube-prometheus-stack --version 52.0.0 -f monitoring/chart-values/prometheus-values.yaml -f infra/azure/chart-values/prometheus-stack.yaml >/tmp/p.yaml` — the rendered Grafana provisioning must show exactly the two datasources with all their existing fields: `grep -A6 "type: loki" /tmp/p.yaml` shows `url: http://loki:3100` intact, `grep -A6 "uid: EbPG8fYoz" /tmp/p.yaml` shows the Tempo entry with `url: http://tempo.monitoring:3200`, and `grep -c "type:" /tmp/p.yaml`'s datasource section counts exactly 2.

- [ ] T003 Add `setup-aks-prometheus-stack` to makefile (next to the existing `setup-kube-prometheus-stack` at makefile:106): installs `prometheus-community/kube-prometheus-stack` chart **52.0.0** (unchanged AKS pin), release `prometheus-stack`, ns `$(MONITORING_NS)`, `--create-namespace`, with two values files in order — `monitoring/chart-values/prometheus-values.yaml` then `infra/azure/chart-values/prometheus-stack.yaml` — then swap the `setup-aks-o11y` dependency at makefile:187 from `setup-kube-prometheus-stack` to `setup-aks-prometheus-stack`; EKS/local targets (`setup-kube-prometheus-stack`, `setup-observability`, `setup-local-o11y`) and the shared values file stay untouched (FR-007/FR-008).
  Verify: `grep -n "setup-aks-prometheus-stack" makefile` (target defined, chained alongside), `sed -n '187p' makefile` prints the `setup-aks-o11y` dependency line containing `setup-aks-prometheus-stack` and NOT `setup-kube-prometheus-stack`, `make -n setup-aks-prometheus-stack` prints both values files in order, and `git diff --stat monitoring/chart-values/` shows no change to the shared file.

---

## Phase 3: User Story 1 — See live service connections (Priority: P1) 🎯 MVP

**Goal**: The Application Dashboard's Service Map shows live links between application services under generated demo-shop traffic (FR-002). Data path: Caretta emits `caretta_links_observed` → existing Prometheus scrape job → existing `Service Map ☸️` panel (panel file untouched, data-model.md entity 4).

**Independent Test**: Generate demo-shop traffic, query `caretta_links_observed{client_namespace="robot-shop"}` for the traffic period (quickstart step 3a) — expect ≥1 link series. The panel itself is never edited; feeding Caretta delivers it.

Coverage note: the existing caretta scrape job in the shared prometheus-values file already works untouched (research.md Finding 3) — no overlay scrape task is needed for US1.

### Implementation for User Story 1

- [ ] T004 [US1] Create `infra/azure/chart-values/caretta.yaml` — AKS-only Caretta values per research.md Finding 3: `resources.limits.memory: 512Mi` (chart-default 300 Mi OOMKilled the fleet on live AKS), `victoria-metrics-single.enabled: false` and `grafana.enabled: false` (one Prometheus, one Grafana — principle III), `prometheusPort: 7117`, tolerations `[{operator: Exists}]` (covers every pool taint AND the spot taint `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`; no nodeSelector — Caretta must land on the label-less system pool too, FR-013).
  Verify: `helm template caretta groundcover/caretta --version 0.0.16 -f infra/azure/chart-values/caretta.yaml >/tmp/c.yaml` — grep `/tmp/c.yaml` for `512Mi` (memory limit), `operator: Exists` in the DaemonSet tolerations, and zero `victoria-metrics`/Grafana subchart manifests.
  Note: if `helm pull groundcover/caretta --version 0.0.16` fails on the GitHub-CDN fetch (known flakiness, research.md Finding 3), fall back to the locally cached tarball — the pin does not move.

- [ ] T005 [US1] Add `setup-aks-caretta` to makefile (next to the existing EKS/local `setup-caretta` at makefile:126, AKS pattern follows `setup-aks-loki` at makefile:189): `helm repo add groundcover https://helm.groundcover.com/` (skips on re-add; keeps the target self-sufficient), then `helm upgrade --install caretta groundcover/caretta --version 0.0.16 --values ./infra/azure/chart-values/caretta.yaml -n $(MONITORING_NS) --create-namespace`. Append `setup-aks-caretta` to the `setup-aks-o11y` dependency chain at makefile:187 (after `setup-dashboards`). The EKS/local `setup-caretta` stays untouched (FR-007).
  Verify: `make -n setup-aks-caretta | grep groundcover/caretta` prints the pinned install command, `sed -n '187p' makefile` shows `setup-aks-caretta` in the chain, and `grep -n "setup-caretta\|setup-aks-caretta" makefile` shows both targets distinct (EKS/local unchanged).
  Live acceptance [FR-010, SC-001]: on the cluster, two successive `make setup-aks-caretta` runs both exit 0 with the release unchanged (`helm list -n monitoring | grep caretta` shows one release, same chart), then `kubectl get pods -n monitoring -l app=caretta -o wide` shows one ready pod per node across every pool (9 nodes), including spot nodes — quickstart step 2 placement + FR-013.

**Checkpoint**: US1 is functional when the caretta release is up at chart 0.0.16 with 512Mi limits, the DaemonSet covers every node in every pool (system + spot included), and under a recorded traffic window `caretta_links_observed{client_namespace="robot-shop"}` returns ≥1 series — which automatically delivers the existing `Service Map ☸️` panel (it queries that metric; the dashboard file is never edited). US1 does not wait on US2/US3: its only shared prerequisite is the foundational stack (T002/T003); its chain slot after tempo/beyla is bookkeeping, not a data dependency.

---

## Phase 4: User Story 2 — Inspect recorded requests (Priority: P1)

**Goal**: Traces of demo-shop traffic are findable and openable in the dashboards app's Tempo datasource (FR-003). Data path: Beyla (eBPF) → OTLP `http://tempo.monitoring:4318` → Tempo → Grafana's Tempo datasource at `:3200` (the `:3200` datasource fix from T002 is a prerequisite — Beyla ships spans with nowhere to go until Tempo exists, and Tempo is invisible to users until the datasource URL is right).

**Independent Test**: Generate demo-shop traffic, run TraceQL `{resource.service.name="catalogue" && name="GET /products"}` over the traffic window in Explore (quickstart step 3b) — expect ≥1 result, and open it — expect multiple spans of recorded request work. Beyla supplies the traces; Tempo supplies storage; US3 does not gate this.

Coverage notes: the datasource URL fix and its make target are done in T002/T003 (foundational). Tempo's known upstream idle-poll noise (tempo issue #7666, research.md Finding 1) is recorded in research — no task for it.

### Implementation for User Story 2

- [ ] T006 [P] [US2] Create `infra/azure/chart-values/tempo.yaml` — AKS-only Tempo values for `grafana-community/tempo` chart 3.1.0, monolithic single-binary (data-model.md entity 1): fresh settings, never reusing `monitoring/chart-values/tempo.yaml` (that file pins image `main-63562bc`, a dev build — FR-008). Placement: on `workload=o11y` with BOTH tolerations — the pool taint (`key: o11y, operator: Equal, value: "true", effect: NoSchedule`, pattern from `infra/azure/chart-values/loki.yaml`) and the spot taint (`key: kubernetes.azure.com/scalesetpriority, operator: Equal, value: spot, effect: NoSchedule`) — every node carries the spot taint (plan, verified live). Placement keys verified live just now: chart 3.1.0 takes **top-level** `nodeSelector:` and `tolerations:` (`helm show values grafana-community/tempo --version 3.1.0 | grep -E "^nodeSelector|^tolerations"` → both at top level, `replicas: 1` default = single StatefulSet). Use exactly those keys — do NOT copy loki's `singleBinary.*` nesting (different chart). OTLP/gRPC receivers stay at chart defaults (proven live: OTLP on 4318 answered `200`); storage stays chart-default ephemeral (accepted demo shape, no new StorageClass — principle V).
  Verify: `helm template tempo grafana-community/tempo --version 3.1.0 -f infra/azure/chart-values/tempo.yaml >/tmp/t.yaml` — grep `/tmp/t.yaml` for `workload: o11y` in nodeSelector (zero `app|persistent|loadgen` nodeSelectors), both toleration keys on the Tempo pod, no persistent volume claim rendered, and no `main-63562bc` image anywhere.

- [ ] T007 [US2] Add `setup-aks-tempo` to makefile (next to `setup-aks-loki` at makefile:189, same shape): `helm repo add grafana-community https://grafana-community.github.io/helm-charts` (self-sufficiency; loki precedent), then `helm upgrade --install tempo grafana-community/tempo --version 3.1.0 --values ./infra/azure/chart-values/tempo.yaml -n $(MONITORING_NS) --create-namespace --timeout 10m`. **Never reduce the `--timeout 10m`** — the first live install exceeded helm's 5-minute default and left no release (`release not found`, research.md Finding 1; contract make-targets.md). Append `setup-aks-tempo` to the `setup-aks-o11y` chain at makefile:187, positioned after `setup-dashboards` and BEFORE `setup-aks-beyla` (OTLP endpoint must exist when Beyla starts). No istio reference anywhere in the target (FR-006).
  Verify: `make -n setup-aks-tempo | grep tempo` prints the pinned command WITH `--timeout 10m`, `sed -n '187p' makefile` shows `setup-aks-tempo` in the chain before `setup-aks-beyla`, and `grep -ci istio <(make -n setup-aks-tempo)` returns 0.
  Live acceptance [FR-010]: two successive runs both succeed, `helm list -n monitoring | grep tempo` shows one release at chart 3.1.0, and `kubectl get pod -n monitoring` shows `tempo-0` on an o11y node (`kubectl get pod -n monitoring -o wide | grep tempo` — node name contains `o11y`, not `app/persistent/loadgen/nodepool1`).

- [ ] T008 [P] [US2] Create `infra/azure/chart-values/beyla.yaml` — AKS-only Beyla values, chart `grafana/beyla` 1.16.11 (data-model.md entity 2, research.md Finding 2):
  * `config.data.otel_traces_export.endpoint: http://tempo.monitoring:4318` (US2 trace path; the peer default in the chart is `grafana-agent:4318` — verified live via `helm show values grafana/beyla --version 1.16.11`, values block `config.data`).
  * `config.data.prometheus_export` — defaults are already `port: 9090, path: /metrics` (verified same block); keep nothing to change unless steering, but US3's node-IP scrape (next story) depends on this endpoint existing.
  * `service.enabled: false` (chart default, verified live — keeps Beyla on hostNetwork-style node-IP metrics, no Service object).
  * Tolerations `[{operator: Exists}]` and NO nodeSelector — Beyla must land on every node in every pool including the label-less system pool and every spot node (FR-013; the trial ran 9/9 with exactly this, Finding 2).
  * `/sys/fs/bpf` hostPath mount via the chart's top-level `volumes` + `volumeMounts` lists (both keys verified live at the values top level) so pinned-map features load (Finding 2 quirk 2).
  * Chart default already renders `hostNetwork: true` on the DaemonSet — verified offline on chart templates: `daemon-set.yaml:47` gates it on `preset == "network"` or `.Values.config.data.network` or `.Values.contextPropagation.enabled`, and `contextPropagation.enabled` is `true` by default (values.yaml:77). No extra values key; the node-IP metrics contract (US3) is safe.
  Verify: `helm template beyla grafana/beyla --version 1.16.11 -f infra/azure/chart-values/beyla.yaml >/tmp/b.yaml` — grep `/tmp/b.yaml` for `tempo.monitoring:4318`, `operator: Exists` in tolerations, a `/sys/fs/bpf` hostPath volume+mount pair, NO nodeSelector in the DaemonSet, and `hostNetwork: true` in the daemon-set spec.

- [ ] T009 [US2] Add `setup-aks-beyla` to makefile (next to `setup-aks-tempo`, same shape as T007's target): `helm repo add grafana https://grafana.github.io/helm-charts` (self-sufficiency; the repo is shared with EKS/local but adding it is a no-op when already present), then `helm upgrade --install beyla grafana/beyla --version 1.16.11 --values ./infra/azure/chart-values/beyla.yaml -n $(MONITORING_NS) --create-namespace`. Append `setup-aks-beyla` to the `setup-aks-o11y` chain at makefile:187, immediately AFTER `setup-aks-tempo` (T007 places tempo first). No istio reference (FR-006). The existing EKS/local `setup-beyla` target stays untouched (FR-007).
  Verify: `make -n setup-aks-beyla | grep grafana/beyla` prints the pinned install with the AKS values file, `sed -n '187p' makefile` shows `setup-aks-tempo setup-aks-beyla` adjacent and in that order, and `grep -n "setup-beyla\|setup-aks-beyla" makefile` shows both distinct.
  Live acceptance [FR-010 + US2 path]: run `make setup-aks-beyla` twice (both exit 0, one release, same chart), then `kubectl get ds -n monitoring` shows `beyla` READY = 9 (one per node, including spot and system pool); a quickstart step 3b shape on a fresh traffic window — TraceQL `{resource.service.name="catalogue" && name="GET /products"}` returns ≥1 openable trace — completes the US2 test (run at verification, quickstart.md).

**Checkpoint**: US2 is functional when the tempo and beyla releases are up, the datasource URL is `:3200` (T002/T003), TraceQL returns an openable trace under fresh traffic, and Beyla runs one pod per node (9/9). US1 and US2 do not depend on each other — either story's checkpoint can pass without the other being installed.

---

## Phase 5: User Story 3 — Find automatically collected application measurements (Priority: P1)

**Goal**: Automatically collected app measurements are queryable without a separate install step (FR-004). Data path: Beyla's `http_server_request_duration_seconds` etc. (`prometheus_export`, :9090 on every node IP — T008) → a Prometheus scrape config → Grafana Explore/Prometheus.

**Independent Test**: Under a recorded traffic window, query `sum(increase(http_server_request_duration_seconds_count{service_namespace="robot-shop"}[$__range]))` in Explore (quickstart step 3c) — expect ≥1. No new install: the collector was installed by US2; this story only makes its measurements visible in the monitoring system.

Coverage notes: the promotion of Beyla (chart) and its placement are done in US2 (T008/T009). What remains here is only the scrape wiring in the AKS prometheus-stack overlay. The chart offers only a `serviceMonitor` — service-level scrape doesn't fit `service.enabled: false` + hostNetwork (research.md Finding 2 quirk 3); a node-IP scrape config is the overlay's job.

### Implementation for User Story 3

- [ ] T010 [US3] Amend `infra/azure/chart-values/prometheus-stack.yaml` (created in T002): redefine `prometheus.prometheusSpec.additionalScrapeConfigs` with TWO jobs — (a) the caretta job, written with a correct pod-label regex (the shared file's `__meta_kubrnetes_` typo at monitoring/chart-values/prometheus-values.yaml:344 is out of scope and stays untouched; the AKS job uses the correct spelling), (b) a NEW beyla job scraping `http://$(NODE_NAME):9090` across all nodes (hostNetwork DaemonSet — targets are node IPs, not pod IPs; a kubernetes-nodes relabel or static config; per data-model.md entity 6). This overlay definition replaces the whole `additionalScrapeConfigs` list for the AKS install; the shared file stays untouched (FR-008).
  Verify: `helm template prom prometheus-community/kube-prometheus-stack --version 52.0.0 -f monitoring/chart-values/prometheus-values.yaml -f infra/azure/chart-values/prometheus-stack.yaml >/tmp/p.yaml && grep -c "caretta\|beyla" /tmp/p.yaml` shows both names; no `__meta_kubrnetes` string appears anywhere in the rendered secrets.

- [ ] T011 [US3] Re-apply the stack so the amended overlay takes effect: `make setup-aks-prometheus-stack` (helm `upgrade --install` — idempotent by construction, FR-010), then verify the scrape wiring live. Mechanism verified in the chart source (chart 52.0.0, `templates/prometheus/additionalScrapeConfigs.yaml`): the inline `additionalScrapeConfigs` list is rendered into a **Secret** `prometheus-stack-…-prometheus-scrape-confg` (key `additional-scrape-configs.yaml`, base64), and the Prometheus CR references it (`prometheus.yaml`:309-313). So: `helm upgrade` succeeds with revision incremented and unchanged chart pin; `kubectl get secrets -n monitoring | grep scrape-confg` finds the secret; `kubectl -n monitoring get secret prometheus-stack-prometheus-scrape-confg -o jsonpath='{.data.additional-scrape-configs\.yaml}' | base64 -d` — (if the secret name differs, take the exact one from `helm get manifest prometheus-stack -n monitoring` — the chart's `fullname` helper decides the prefix) — and the decoded YAML shows both `caretta` and `beyla` job blocks; also `kubectl get prometheus -n monitoring prometheus-stack-kube-prom-prometheus -o yaml | grep -c scrape-confg` returns ≥1 (CR-side reference present). Then scrape health: fill `http://<an-o11y-node-IP>:9090/metrics` from a node of any pool: `kubectl -n monitoring get pod prometheus-stack-kube-prom-prometheus-0 -o jsonpath='{.status.hostIP}'`+ port-forward shape from quickstart step 3a proves the beyla job `up == 1`.
  Live acceptance [FR-004, SC-002]: run the quickstart step-3 shape — under a recorded traffic window, `sum(increase(http_server_request_duration_seconds_count{service_namespace="robot-shop"}[$__range]))` returns ≥1. Research Finding 2 recorded 47 such observations on the trial cluster; this is the live version of that number.

**Checkpoint**: US3 passes when Beyla's automatic measurements are visible in the monitoring system under fresh traffic with no install step beyond what T003–T009 already ran. It rides US2's Beyla and the founding stack — if US2's checkpoint fails, US3's fails at the scrape layer with an empty series, which is the diagnostic distinction between "trace path broken" (US2) and "scrape path broken" (this story).

---

## Phase 6: User Story 4 — Keep existing monitoring usable (Priority: P1)

**Goal**: The three added capabilities change nothing else — existing Azure panels stay live under equivalent traffic (FR-005), monitoring setup succeeds without a service mesh (FR-006), EKS/local workflows stay byte-identical (FR-007), Azure settings live only in `infra/azure/` (FR-008), and the per-node placement rule holds with the amended exception list (FR-013).

**Independent Test**: Four checks with no dedicated failure mode of their own: (1) error-producing traffic shows the request-errors/volume/success-rate/error-logs panels still painting (quickstart step 4); (2) a full monitoring-chain run SUCCEEDS with no istio control plane present in the cluster (executable proof lives in T016 clause (a); the touched targets contain zero istio references as the static guard); (3) `git diff` on the PR shows no EKS/local file touched; (4) `agent/scripts/verify-aks-observability.sh` passes on the live cluster with Beyla and Caretta accepted as per-machine helpers — the check's own conformance test keeps proving that offline.

Coverage notes: panels are untouched by design (data-model.md entity 4) — the checks are regression guards, not build work. Spec scenario 4.4's "amended exception list" refers to this script: it classifies only `alloy`/`node-exporter` as per-machine helpers today (agent/scripts/verify-aks-observability.sh:97), so Beyla and Caretta pods count as o11y-violating stragglers until the script's helper list grows.

### Implementation for User Story 4

- [ ] T012 [US4] Amend the per-machine helper list in `agent/scripts/verify-aks-observability.sh`: extend the DaemonSet-name match (currently `ds == "alloy" or "node-exporter" in ds`, script line ~97) with `beyla` and `caretta`, and extend the expected-helpers tuple (currently `("alloy", "node-exporter")`, script line ~125) to all four collectors; update the header comment (lines 10-12) and the "Per-machine helpers" comment block (line 78) to name four helpers. Beyla/Caretta pods then stop FAILing as o11y-violating stragglers and start being checked for full-pool coverage (FR-013, SC-011 — their coverage gap cases start failing the check as designed, which is the point).
  Verify: `bash agent/scripts/verify-aks-observability.sh --help 2>/dev/null; grep -n "beyla\|caretta" agent/scripts/verify-aks-observability.sh` shows four helper names in both the matcher and the expected tuple.

- [ ] T013 [P] [US4] Update the offline conformance fixtures in `agent/tests/azure/check-verify-observability-offline.sh` (and its pod fixture lines inside `agent/tests/azure/fake-kubectl.sh`) to the four-helper world: (a) cases that previously fed only `alloy`/`node-exporter` pod lines gain `beyla:...` and `caretta:...` lines covering every pool, so existing happy-path assertions stay exit-0; (b) the `helper-absent` case keeps asserting the `no pods found` FAIL naming an expected helper; (c) ADD one new case: a dataset where beyla pods miss one pool, expecting `FAIL per-machine helper beyla: not running on every node pool (missing: …)` — proving the amended helpers are enforced for coverage, not merely whitelisted out of the o11y-only rule. Both files are outside protected paths.
  Verify: `bash agent/tests/azure/check-verify-observability-offline.sh` exits 0 with the new case's PASS line visible in its output (the check self-reports each `check` line), and the new FAIL-string case appears in the run list.

**Checkpoint**: US4 passes when all four of its acceptance scenarios hold: (1) error-producing traffic leaves the four Application Dashboard panel groups painting (FR-005 — no task edits anything they read); (2) `make setup-aks-o11y` succeeds with the mesh absent — the executable no-mesh run is T016 clause (a) (FR-006 — no touched target references istio, EC-002 keeps this a setup-level requirement, not a full-deploy one); (3) `git diff main...HEAD -- monitoring/chart-values/ 'makefile'` shows zero EKS/local-file hunks beyond the AKS-only target additions already specified in T003/T005/T007/T009 (FR-007 files verified untouched: `setup-kube-prometheus-stack`, `setup-observability`, `setup-local-o11y`, `setup-tempo`, `setup-beyla`, `setup-caretta`, `monitoring/chart-values/`); (4) `agent/scripts/verify-aks-observability.sh` passes live with four helpers each covering every pool and Tempo/others on o11y (SC-011). The offline conformance test (T013) is the CI-reachable version of check (4).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, repo-wide gates, and the repeat-run evidence trail that closes FR-012, FR-010, FR-011, SC-007–SC-010.

- [ ] T014 [P] Update the Azure deployment instructions in `README.md` (the `make setup-aks-o11y` / `make setup-aks` block at README.md:139-147 is the target, FR-012): describe that the monitoring chain now also installs Tempo, Beyla, and Caretta (three capabilities, one chain, no extra steps — FR-011), that re-running setup is safe with unchanged settings (FR-010), and how a reviewer generates demo-shop traffic and confirms the three results (service-map links, openable trace, automatic measurements — point at `specs/005-aks-observability-parity/quickstart.md` steps 3a/3b/3c as the walk-through rather than duplicating it). Keep the existing AKS password one-liner and endpoints text as-is.
  Verify: `sed -n '130,160p' README.md` shows the amended block; the quickstart path referenced exists (`ls specs/005-aks-observability-parity/quickstart.md`).

- [ ] T015 Run the repo's gates and attach the actual output to the PR (`evidence:attached`, plan verification strategy step 1): prerequisites first — hooks enabled (`make install-check`, then `make hooks`/`make install` if needed, per AGENTS.md); then `make lint`; then re-check that every makefile target name cited in tasks.md still matches the implemented makefile (`grep -n "^setup-aks" makefile`); the per-file content proof is each values file's `helm template` render from its own task (T002/T006/T008/T010) — this task is the aggregate gate run, paste the `make lint` output block and the four-target dry-run proof into the PR.
  Verify: `make lint` exits 0 with its output attached, and the four new targets each print their pinned install referencing the right values file via `make -n setup-aks-tempo setup-aks-beyla setup-aks-caretta setup-aks-prometheus-stack | grep -c "chart-values"` (expect 4 — one per target; the render-level greps of T002/T006/T008/T010 remain the styled proof of each file's content, this is the aggregate wiring gate).

- [ ] T016 Repeat-run ledger + no-mesh proof + full quickstart validation on a live AKS cluster, output attached to the PR. PREREQUISITE: a re-provisioned cluster — the research cluster was deleted; NOTHING here can run without one. Gates in order: (a) NO-MESH EXECUTION [FR-006, SC-004, EC-002]: provision the plain AKS cluster first (infra/azure cluster step, without the istio step — `setup-aks` installs istio mid-chain, so do NOT use it for this prefix), run `make setup-aks-o11y` with no istio control plane in the cluster — expect success; prove the mesh is truly absent first with `kubectl get ns istio-system` (empty result). Record both outputs. (b) Then complete the standard flow: install the mesh (`make setup-istio`, the AKS chain's own step — makefile:89) and the remaining `setup-aks` chain steps, then two successive runs of BOTH, with outputs attached: two `make setup-aks-o11y` runs AND two `make setup-aks` runs (one-command shape — mandatory, SC-009 requires it), each pair both exit 0, with `helm list -n monitoring --no-headers | grep -E "^tempo|^beyla|^caretta|^prometheus-stack"` after each showing exactly one release per capability at the same pins (FR-010, SC-008, SC-009). (c) Execute `specs/005-aks-observability-parity/quickstart.md` steps 2-5 end-to-end during ONE recorded loadgen window (traffic generated per A-002, error-producing traffic included for the panel checks per A-003): the placement counts (step 2), the three results (steps 3a/3b/3c), the panel regression (step 4), and the fresh-window repeat (step 5) — each step's command output pasted into the PR as the acceptance evidence (SC-001–SC-004, SC-008–SC-011).
  Verify: the PR carries (i) the no-mesh evidence — `kubectl get ns istio-system` empty, followed by the successful `make setup-aks-o11y` output (G1's executable proof), (ii) four run outputs (two × setup-aks-o11y, two × setup-aks) plus the release listings showing zero duplicate installations at unchanged pins, (iii) quickstart step-3 outputs (`caretta_links_observed` > 0 links, one openable trace from TraceQL, `http_server_request_duration_seconds_count` increase > 0), (iv) the step-2 pod-per-node table naming pools incl. system + spot and o11y-only for everything else.

- [ ] T017 [P] Add the two story-specific notes to the PR description: (a) the latest-stable pins evidence table copied from `specs/005-aks-observability-parity/research.md` Findings 1–3 — chart, version, app version, and the live verification date (2026-10-09) for Tempo, Beyla, Caretta (FR-009, SC-007), plus the `--timeout 10m` note for Tempo and the 512 Mi note for Caretta as the two settings the research justified; (b) the chart-CDN limitation note per plan.md verification strategy item 7: `groundcover/caretta` fetches its release tarball from a GitHub release-asset CDN that flaked twice during research (Finding 3) — if it flakes during implementation, the fallback is the vendored tarball, the pin does not move; state this explicitly so the choice is visible in review, not buried.
  Verify: the PR text contains both notes verbatim from this task's sources (`sed -n '96,120p' specs/005-aks-observability-parity/research.md` for the pins rows, plan.md verification strategy item 7 for the fallback sentence) — a reviewer can trace each PR line back to its doc.

## Dependencies & Execution Order

### Phase dependencies
- **Phase 1 (T001)**: no prerequisites — evidence gathering, no file writes.
- **Phase 2 (T002–T003)**: needs T001's repo availability result; blocks everything below (the overlay + its target are the install surface for both later stories' data flows).
- **Phase 3 (US1: T004–T005)**: needs T003's target surface.
- **Phase 4 (US2: T006–T009)**: needs T002/T003 (datasource `:3200` + stack target); T007 needs T006; T009 needs T007 and T008.
- **Phase 5 (US3: T010–T011)**: needs T002 (overlay file exists) and T008/T009 (Beyla on every node with `:9090`); T011 needs T010.
- **Phase 6 (US4: T012–T013)**: needs T008/T009 (the Beyla/Caretta DaemonSets exist to be classified); independent of Phase 5's outcome (guards, not data path).
- **Phase 7 (T014–T017)**: needs all prior phases — docs describe the finished chain, the ledger runs it, the PR notes cite the research used to build it.

### User story dependencies
- **US1 (Caretta/service map)** — independent: needs only foundational.
- **US2 (Tempo traces)** — needs foundational only; Beyla serves both US2 and US3 but installs once (US2).
- **US3 (Beyla measurements)** — conceptually rides US2's Beyla; its OWN tasks depend only on the overlay and the DaemonSet running. If US2's install works, US3 is a wiring amendment (T010–T011).
- **US4 (keep working)** — verification story; its scripted tasks (T012–T013) only require the helper DaemonSets to exist (T004/T008), not the traffic results to pass.

## Parallel opportunities

- Within phases: T006 and T008 are flagged `[P]` (different files, distinct verifications). T013 and T014 are `[P]` against each other and against the cluster work — one touches test fixtures, one touches the README, no shared file. T017 is `[P]`, it is a PR annotation.
- Across stories: after Phase 2 (T002/T003) completes, US1 (T004–T005) and US2's values files (T006/T008) can proceed in parallel — different files, distinct charts. US2's make-target tasks and US1's are chain-append operations on the SAME makefile dependency line — run those sequentially (T005, then T007, then T009, then US3's T010, so the `setup-aks-o11y` dependency edit at line 187 has an unambiguous running order).

## Notes
- Every live `kubectl`/`helm` output pasted into the PR is acceptance evidence (`evidence:attached`); planning-time examples in research.md (e.g. 47 Beyla measurements, 42 robot-shop links) are history, not IMs, and are NOT acceptable substitutes for live runs during this story's verification.
- The chain edits at makefile line 187 are the one shared file contention point — keep task sequencing there (T003 → T005 → T007 → T009) and never pair them in a parallel batch.
- The Tempo `--timeout 10m` and the Caretta `512Mi` settings are the two "always carry these forward" constants; both trace to research demos and to PR-note task T017.


---

