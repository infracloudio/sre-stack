# Make-target contract — 005-aks-observability-parity

The makefile is this repo's user-facing interface. Targets installed or
changed by this story promise the behavior below. Commands are the
developer-facing surface; charts and values paths are pinned (principle II),
settings come from `.env`/values files (principle III).

## Targets added

### `setup-aks-tempo`

- Installs: `grafana-community/tempo` chart **3.1.0**, release `tempo`,
  ns `$(MONITORING_NS)` (normally `monitoring`), values
  `infra/azure/chart-values/tempo.yaml`.
- Repo: adds/updates `grafana-community` (same repo `setup-aks-loki`
  already uses).
- **Timeout**: `--timeout 10m` — the first live install failed at helm's
  default 5 m (research.md Finding 1). Never reduce.
- Idempotency: re-run with unchanged settings exits 0 and creates nothing
  new (FR-010).
- Mesh: no istio reference (FR-006). Safe to run standalone.

### `setup-aks-beyla`

- Installs: `grafana/beyla` chart **1.16.11**, release `beyla`, ns
  `$(MONITORING_NS)`, values `infra/azure/chart-values/beyla.yaml`.
  Repo: `grafana` (already config'd by existing targets).
- Idempotency + no-mesh: same rules as above.
- Chained after `setup-aks-tempo` so the OTLP endpoint exists when beyla

### `setup-aks-caretta`

- Installs: `groundcover/caretta` chart **0.0.16**, release `caretta`, ns
  `$(MONITORING_NS)`, values `infra/azure/chart-values/caretta.yaml`.
- Repo: `groundcover` (`https://helm.groundcover.com/`) — already added by
  `setup-caretta` for EKS/local; same repo here.
- Known fetch flakiness: index → GitHub release assets CDN (the project
  org moved; research.md Finding 3). Within a story timebox, if the CDN
  still blocks the install, vendoring the chart tarball is the fallback;
  the pin does not move.
- Idempotency + no-mesh: same rules as above.

### `setup-aks-prometheus-stack`

- Installs: `prometheus-community/kube-prometheus-stack` chart **52.0.0**
  (unchanged AKS pin), release `prometheus-stack`, ns `$(MONITORING_NS)`
  — with TWO values files in order:
  `monitoring/chart-values/prometheus-values.yaml` then
  `infra/azure/chart-values/prometheus-stack.yaml`. The second file
  redefines `grafana.additionalDataSources` (Tempo → `:3200`) and
  `prometheus.prometheusSpec.additionalScrapeConfigs` (caretta + beyla
  jobs).
- Shared file definition: the shared prometheus-values file is NOT edited
  by this story (FR-007/FR-008).
- Idempotency: same rules as above.

## Targets changed

### `setup-aks-o11y` (makefile:187)

- New chain: `setup-db-grafana-psql` → `setup-aks-prometheus-stack` (new)
  → `setup-aks-loki` → `setup-aks-log-shipper` → `setup-aks-o11y-routes`
  → `setup-dashboards` → `setup-aks-tempo` → `setup-aks-beyla` →
  `setup-aks-caretta`.
- `setup-kube-prometheus-stack` is no longer called on the AKS branch —
  the whole cluster's kube-prometheus-stack install on AKS flows through
  the overlay. On EKS/local nothing changes (FR-007).
- `setup-dashboards` unchanged; runs before the source installs so panels
  exist when data arrives — no failure if a source is missing (Grafana
  renders the panel empty until data flows).

### `setup-aks` (makefile:213) — unchanged

- Already calls `$(MAKE) setup-aks-o11y`; the three new capabilities ride
  along (FR-011). Its double-run promise reads unchanged; each sub-step is
  itself idempotent.

## Guardrails

- `setup-aks` keeps its `STACK_MODE=aks` guard (makefile:214). New targets
  are AKS-only by name (`*-aks-*`) and refuse conceptually to install
  Azure-specific values elsewhere; nothing writes to EKS/local settings.
- Existing `setup-tempo`/`setup-beyla`/`setup-caretta` shared targets are
  NOT touched by this story (FR-007).
- Secrets: none introduced; admin password retrieval stays the documented
  Grafana-secret one-liner (AGENTS.md).
