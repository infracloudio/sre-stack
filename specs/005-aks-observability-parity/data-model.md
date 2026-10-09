# Data Model — 005-aks-observability-parity

This repo installs no application code; the entities of this story are the
installed capabilities, their configuration surfaces, and how work flows
between them. Facts below are grounded in `research.md` (live cluster
`sre-stack-452138`, Kubernetes 1.34.11, 2026-10-09) — line references point
into the repo or that document.

## Entities

### 1. AKS Tempo release

- **What it is**: Helm release `tempo`, ns `monitoring`, chart
  `grafana-community/tempo` **3.1.0** (app 3.1.0), monolithic single-binary.
- **Validation rules**:
  - Chart version pinned explicitly; never the deprecated `grafana/tempo`
    chart (research.md Finding 1; FR-009).
  - Azure-specific values in `infra/azure/chart-values/tempo.yaml`, never
    reusing `monitoring/chart-values/tempo.yaml` (that file pins image
    `main-63562bc`; FR-008).
  - Node placement: `nodeSelector workload=o11y` + tolerated taints —
    FR-013 (the trial defaulted to the system pool; the values must not).
  - Reachability contract: OTLP receiver at `http://tempo.monitoring:4318`
    (Beyla's trace sink); HTTP API/Grafana datasource at
    `http://tempo.monitoring:3200` (port 3100 broken — Finding 1).
  - Re-run safe: `helm upgrade --install` with long `--timeout` (first
    live install timed out at helm's default; FR-010).
- **Storage**: chart-default ephemeral (accepted for the demo shape, same
  as the EKS/local chain); no new StorageClass (principle V).

### 2. Beyla DaemonSet

- **What it is**: Helm release `beyla`, chart `grafana/beyla` **1.16.11**
  (app 3.32.0), hostNetwork eBPF DaemonSet.
- **Validation rules**:
  - Pinned version (FR-009); values in `infra/azure/chart-values/beyla.yaml`
    (FR-008).
  - Runs on **every node in every pool** — system (`nodepool1`, no
    workload label), app×3, persistent×2, o11y×2, loadgen×1 (live count:
    9/9). Tolerations list MUST cover `app|persistent|o11y|loadgen` and the
    spot taint `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`
    (FR-013; chart default tolerations is empty and would violate it).
  - Traces export: `otel_traces_export.endpoint =
    http://tempo.monitoring:4318`.
  - `/sys/fs/bpf` hostPath so pinned-map features load (Finding 2 warning).
  - Metrics export: Prometheus endpoint on node IP `:9090`
    (`service.enabled: false`, `hostNetwork: true`).
  - Re-run safe (FR-010).

### 3. Caretta DaemonSet

- **What it is**: Helm release `caretta`, chart `groundcover/caretta`
  **0.0.16** (app v0.0.16) — the Service Map data source.
- **Validation rules**:
  - Pinned version (FR-009); values in
    `infra/azure/chart-values/caretta.yaml` (FR-008).
  - `resources.limits.memory: 512Mi` — the chart-default 300 Mi produced
    OOMKilled crash-loops fleet-wide and zero link metrics (Finding 3).
  - Subcharts `victoria-metrics-single.enabled: false`,
    `grafana.enabled: false` (one Grafana, one Prometheus — principle III).
  - Per-node coverage with tolerations like Beyla's, spot included
    (FR-013); exposes `caretta_links_observed` on `:7117`
    (`prometheusPort`).
  - Re-run safe (FR-010).

### 4. Application Dashboard "Service Map ☸️" panel

- **What it is**: existing panel, file untouched:
  `monitoring/dashboards/application.yaml` (panel title at :92).
- **Validation rules**:
  - Its query reads `caretta_links_observed` from Prometheus (expr at
    :91); the panel is delivered by feeding Caretta, not by editing the
    dashboard (FR-002). The FR-005 panel groups stay untouched, as do the
    MySQL/RabbitMQ/istio dashboards (spec out-of-scope).

### 5. Grafana Tempo datasource

- **What it is**: Helm-provisioned datasource inside kube-prometheus-stack
  (uid `EbPG8fYoz`, API-refuses-edit: "Cannot update read-only data
  source").
- **Validation rules**:
  - URL must become `http://tempo.monitoring:3200` via the AKS
    prometheus-stack values overlay, not by hand-editing the cluster
    (FR-003, principle III).

### 6. AKS prometheus-stack values overlay

- **What it is**: new `infra/azure/chart-values/prometheus-stack.yaml`
  applied by a new `setup-aks-prometheus-stack` target: chart
  **52.0.0** (existing AKS pin unchanged), two values files — shared
  `monitoring/chart-values/prometheus-values.yaml` + this overlay.
- **Validation rules**:
  - Shared file untouched (FR-007/FR-008; research.md Finding 3 keeps the
    pre-existing `__meta_kubrnetes` relabel typo out of scope).
  - Overlay redefines `grafana.additionalDataSources` (Tempo → :3200) and
    `prometheus.prometheusSpec.additionalScrapeConfigs` (caretta scrape
    job with correct regex + beyla node-IP :9090 job).
  - Overlay defines its own `podMonitorSelectorNilUsesHelmValues`-only as
    far as needed for the above; everything else inherits the shared file.

### 7. Make targets

- **What they are**: `setup-aks-tempo`, `setup-aks-beyla`,
  `setup-aks-caretta`, `setup-aks-prometheus-stack`, all chained into
  `setup-aks-o11y` (makefile:187). `setup-aks` unchanged — flows through
  the chain (makefile:213).
- **Validation rules**:
  - Idempotent re-runs (FR-010): every target is `helm upgrade --install`
    with explicit `--version`; live proof: caretta re-upgrade went
    `REVISION: 2` cleanly (research.md Finding 3).
  - No mesh prerequisite: none of the targets references istio (FR-006);
    FR-011 integration is via the chain only.

## State relationships (all traced live on 2026-10-09)

```text
demo-shop traffic
   ├─→ Beyla eBPF ──traces──→ Tempo :4318 ──→ Grafana Tempo datasource :3200
   │                                             └─→ trace search / trace open
   ├─→ Beyla ──metrics(9090/node)──→ Prometheus (beyla scrape job)
   │                                   └─→ Grafana Explore: app measurements
   └─→ Caretta ──caretta_links_observed(:7117)──→ Prometheus (existing caretta job)
                                                  └─→ Service Map ☸️ panel
```

Each arrow was exercised on the live cluster during research: 45 requests
produced 15 searchable traces, 47 HTTP-request measurements, and 42
robot-shop service links (research.md Findings 1–3). Nothing here requires
a service mesh: the mesh exists on the cluster but no arrow depends on it
(FR-006).
