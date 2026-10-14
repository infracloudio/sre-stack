# Research — 005-aks-observability-parity

**Method** (constitution principle VIII): live run against the real AKS cluster
`sre-stack-452138` (southindia, Kubernetes 1.34.11), provisioned by the
developer on 2026-10-09. Every output block below is pasted verbatim from
that session; nothing written from memory. Findings proposed one at a time,
approved by the developer before the next was started. One self-caught error
recorded under Finding 1.

**Verbatim policy note (analysis run 2026-10-09)**: the trial cluster
`sre-stack-452138` was deleted the evening of 2026-10-09. Some "Live-run
record" lines below summarize session output without the full pasted block
(analysis finding C3). Each such claim carries a `Reproduce:` command;
implementation re-runs them live and pastes fresh output into the PR
evidence before the story merges. Claims whose sessions already carry
paste-verbatim blocks are unaffected.

---

## Finding 1 (approved) — Tempo on AKS 1.34: current charts deprecated, community chart works

**Decision**: trace backend = `grafana-community/tempo` chart **3.1.0**
(app 3.1.0), monolithic single-binary, pinned, with a new Azure values file
(`infra/azure/chart-values/tempo.yaml`). The `grafana/tempo` chart is
deprecated and MUST NOT be used even though it is the newest entry in the
`grafana` repo (FR-009 requires the latest stable release; the release line
continues in the community repo — the same repo `setup-aks-loki` already
uses, makefile:190).

Chart-version evidence (verbatim):

```
$ helm search repo grafana/tempo --versions | head -3
NAME                CHART VERSION  APP VERSION  DESCRIPTION
grafana/tempo       1.24.4         2.9.0        Grafana Tempo Single Binary Mode
grafana/tempo       1.24.3         2.9.0        Grafana Tempo Single Binary Mode

$ helm template tempo grafana/tempo --version 1.24.4 ...
WARNING: This chart is deprecated

$ helm show chart grafana/tempo --version 1.24.4 | grep deprecated
deprecated: true

$ helm search repo grafana-community/tempo --versions | head -3
NAME                                CHART VERSION  APP VERSION  DESCRIPTION
grafana-community/tempo             3.1.0          3.1.0        Grafana Tempo Single Binary Mode
grafana-community/tempo             3.0.0          3.0.3        Grafana Tempo Single Binary Mode
grafana-community/tempo             2.4.0          2.10.8      Grafana Tempo Single Binary Mode
```

Live-run record (2026-10-09):

- First install attempt with default helm timeout: timed out at 120 s and
  created **no release** (`helm status: release not found`). Retry with
  `--timeout 10m` succeeded. **The make target must set a long timeout.**
  Reproduce: `helm upgrade --install tempo grafana-community/tempo --version 3.1.0 -n monitoring --create-namespace` (observe default-timeout failure), then rerun with `--timeout 10m`; `helm status tempo -n monitoring` before/after.
- Install (chart defaults) → `STATUS: deployed`,
  pod `tempo-0 1/1 Running` on AKS 1.34.11.
  Reproduce: `helm list -n monitoring | grep tempo; kubectl get pod -n monitoring | grep tempo`.
- Synthetic OTLP/HTTP span (`POST :4318/v1/traces`) → `200`.
- Trace-by-ID lookup → `200`, full span returned.
- TraceQL search with an explicit time window → returns the trace.
- `GET :3200/ready` → `ready`; `/api/echo` → `echo`.
  Reproduce (all three): probe pod —
  `kubectl run tempo-probe --rm -it --image=curlimages/curl --restart=Never -- curl -s -X POST http://tempo.monitoring:4318/v1/traces -o /dev/null -w '%{http_code}'` and `curl -s http://tempo.monitoring:3200/ready`.

Failures and quirks recorded:

1. **Zipkin receiver not enabled by default** — `POST :9411` gave
   `Connection refused`. Receivers in the rendered config: OTLP
   (4317/4318) and Jaeger only. Beyla speaks OTLP, so unaffected.
2. **Old EKS/local values are a trap**: `monitoring/chart-values/tempo.yaml:18`
   pins image `tag: "main-63562bc"` (a dev build) and rendered against chart
   3.1.0 would produce `grana/tempo:main-63562bc`. AKS gets fresh values
   (required by FR-008 anyway).
3. **Grafana's provisioned Tempo datasource is the broken trace source** the
   issue reports; it points at `http://tempo.monitoring:3100`
   (provisioned by `monitoring/chart-values/prometheus-values.yaml:193`,
   documented as accepted-broken in story 002's plan). Tempo 3.x serves
   HTTP on **3200**; nothing listens on 3100:
   - datasource health probe: `{"message":"Not found","traceID":""}`
   - probe pod from monitoring ns: `curl http://tempo.monitoring:3200/ready`
     → `200`
   The datasource is Helm-provisioned, so the Grafana API refuses edits
   (`"Cannot update read-only data source"`, `403`). Fix belongs in values:
   an AKS-only prometheus-stack values overlay (Finding 4).
4. **Known upstream bug**: pods log `error calling scheduler err="rpc error:
   code = NotFound desc = no jobs found"` at error level every minute —
   upstream tempo issue #7666 (open), idle-poll noise only. Nothing to fix;
   record so nobody mistakes it for a live fault.
5. Chart defaults give Tempo no PVC (ephemeral storage) and no placement
   constraints. For this demo stack, ephemeral trace storage is accepted
   (same shape as the EKS/local `setup-tempo` chain); Placement on
   `workload=o11y` is **required** by spec FR-013 and set in the AKS values.

Error caught by the method, not by luck: the first synthetic span was given
`startTimeUnixNano=1760032800…` — a **2025** timestamp written from memory.
It made TraceQL search look broken ("search returns empty") until re-run
with the real current timestamp. Recorded here so the failure survives: no
Timestamp in research or verification may be invented from memory.

---

## Finding 2 (approved) — Beyla 1.16.11: traces + automatic app measurements work

**Decision**: `grafana/beyla` chart **1.16.11** (app 3.32.0), DaemonSet,
hostNetwork, new Azure values `infra/azure/chart-values/beyla.yaml`.
Beyla delivers User Story 2 (traces into Tempo) and User Story 3
(automatic application measurements) on AKS.

Version evidence (verbatim):

```
$ helm search repo grafana/beyla --versions | head -3
NAME                    CHART VERSION  APP VERSION  DESCRIPTION
grafana/beyla           1.16.11        3.32.0       eBPF-based autoinstrumentation ...
grafana/beyla           1.16.10        3.25.0       eBPF-based ...
```

Live-run record (2026-10-09):

- Trial install (chart defaults + `config.data.otel_traces_export.endpoint:
  http://tempo.monitoring:4318` + tolerations) → **9/9 pods Running, one on
  every node in every pool** (app×3, persistent×2, o11y×2, loadgen×1,
  system×1) including the spot-tainted nodes.
  Reproduce: `kubectl get pod -n monitoring -o wide | grep beyla`.
- eBPF attached to: istio-proxy/envoy/pilot-agent, node(web, NodeJS),
  java(shipping), hotrod. Log (verbatim, prefix trimmed):
  `msg="instrumenting process" ... cmd=/go/bin/hotrod-linux ... type=go` —
  no instrumentation errors.
  Reproduce: `kubectl logs -n monitoring ds/beyla | grep "instrumenting process" | head`.
- Generated fresh shop traffic (45 requests via the shop's service DNS:
  catalogue `/products`, user/cart `/health`; **all 200**).
  Reproduce: the traffic runbook (quickstart step 3) — generate, then
  `curl -s -o /dev/null -w '%{http_code}' http://catalogue:80/products`.
- Beyla captured real measurements: `http_server_request_duration_seconds`
  count `47` with `http_route="/*"`,
  `db_client_operation_duration_seconds` 46 `SELECT` observations.
  Reproduce: Grafana Explore/Prometheus —
  `sum(increase(http_server_request_duration_seconds_count{service_namespace="robot-shop"}[$__range]))` over the traffic window.
- Traces landed in Tempo: TraceQL
  `{resource.service.name="catalogue" && name="GET /products"}` over the
  traffic window → **15 traces**, root service `catalogue`, multi-span
  (3 spans in the inspectable trace). By-ID lookup works.
  Reproduce: Grafana Explore/Tempo TraceQL over the same window; open a returned trace.

Failures and quirks recorded:

1. **Chart default has zero tolerations** — the rendered DaemonSet would
   schedule only on the untainted system pool, violating FR-013. Explicit
   tolerations are mandatory, spot taint included (developer requirement).
2. **`bpffs` not mounted** warning (`mkdir /sys/fs/bpf/otel: no such file or
   directory`) — pinned-map features (log enricher, profile correlation)
   disabled. Fix: hostPath mount of `/sys/fs/bpf` in the AKS values.
3. No `Service` object by default (`service.enabled: false`), Beyla runs
   `hostNetwork: true` — its Prometheus endpoint (port 9090,
   `prometheus_export`) is reachable on node IPs. Metrics visibility in the
   monitoring system therefore needs a node-level scrape job (Finding 4
   overlay), not a ServiceMonitor-oriented scrape (the chart only offers
   `serviceMonitor` and no pod monitor).

---

## Finding 3 (approved) — Caretta 0.0.16: OOM-until-memory-raised, then Service Map data path works

**Decision**: `groundcover/caretta` chart **0.0.16** (app v0.0.16) stays the
Service Map source. The existing `Service Map ☸️` panel on the Application
Dashboard queries `caretta_links_observed` from Prometheus
(`monitoring/dashboards/application.yaml:91`, flagship expr verbatim:
`increase((sum by (id, source, target, mainStat) ...caretta_links_observed...)
)[$__range:$__interval]) > 0`), so the panel's data path is caretta's — Beyla
does not emit a `caretta_links_observed` equivalent. Caretta pinned as-is
with a raised memory limit.

Version evidence (verbatim):

```
$ helm search repo groundcover/caretta --versions | head -3
NAME                        CHART VERSION  APP VERSION  DESCRIPTION
groundcover/caretta         0.0.16         v0.0.16      A helm chart for Caretta service map.
groundcover/caretta         0.0.15         v0.0.15      A helm chart for Caretta service map.
```

Live-run record (2026-10-09):

- Install with chart-default resources → DaemonSet 9/9 at start, **but the
  fleet then crash-looped**: OOMKilled (~17 s runtime, exit 137, no error
  logs in the pod), `caretta_polls_made` stuck at `0`, and
  **`caretta_links_observed` produced zero series despite generated traffic**.
  Reproduce: install with chart defaults (no values file), watch
  `kubectl get pod -n monitoring | grep caretta`, then
  `kubectl describe pod | grep -A3 "Last State"` → exit 137.
- Re-install with `resources.limits.memory: 512Mi` +
  `tolerations: [{operator: Exists}]` → **all 9 pods stable** (zero restarts
  past 90 s, where defaults crashed at 17 s) and
  **`caretta_links_observed` = 729 series**, including
  **42 links in the robot-shop namespace** (ratings→mysql,
  cart/user/catalogue→…, services→istiod). The Service Map panel's data
  source is live on AKS.
  Reproduce: apply the AKS caretta values, wait 90 s
  (`kubectl get pod -n monitoring | grep caretta` — zero restarts), then query
  Prometheus: `count(caretta_links_observed{client_namespace="robot-shop"})`.
- The shared `prometheus-values.yaml:330` caretta scrape job already exists
  and worked untouched — targets came up and metrics flowed.

Failures and quirks recorded:

1. **Chart fetch flakiness**: `groundcover/caretta`'s release URLs point at
   `github.com/groundcover-com/helm-charts` (the project org moved; the
   original `github.com/groundcover/caretta` is deleted → 404). Two
   `helm upgrade --install` attempts from the repo index failed with
   `context deadline exceeded` against the GitHub release-asset CDN; the
   chart tarball (cached locally, 60 KB) installed cleanly from file. The
   make target keeps the repo install (pinned); if the CDN stays flaky the
   implementation falls back to vendoring the tarball (note for tasks).
2. **Memory limit 300 Mi (chart default) kills pods on AKS 1.34** → 512 Mi
   required and recorded in the Azure values.
3. Chart default deploy includes VictoriaMetrics + a Grafana subchart — must
   be disabled (`victoria-metrics-single.enabled: false`,
   `grafana.enabled: false`) to keep using the main Prometheus/Grafana (One
   Configuration Surface, principle III).
4. Shared `prometheus-values.yaml` has a stray typo relabel
   (`__meta_kubrnetes_pod_label_`, line 344). Left untouched: the job works
   (proven live: 8/9 targets up immediately; 9/9 after caretta stabilized),
   and the shared file is outside this story's scope (FR-007/FR-008). If it
   ever matters, it becomes its own cleanup story. The AKS-side job (written
   in the Finding-4 overlay) uses the correct regex.

---

## Finding 4 (approved) — Makefile wiring + Prometheus/Grafana overlay (design)

Verified by repo checks (`grep -n"^setup-aks\|^setup-tempo..." makefile`,
`ls infra/azure/chart-values/`) plus the live trials above. Decisions:

1. Three new AKS targets + three AKS values files under
   `infra/azure/chart-values/`:

   | Target | Chart (pinned) | Values file | Key settings |
   |---|---|---|---|
   | `setup-aks-tempo` | `grafana-community/tempo` 3.1.0 | `tempo.yaml` | fresh values (no `main-63562bc` image), `--timeout 10m`, nodeSelector `workload=o11y` + tolerations |
   | `setup-aks-beyla` | `grafana/beyla` 1.16.11 | `beyla.yaml` | `otel_traces_export: http://tempo.monitoring:4318`, tolerations `app|o11y|persistent|loadgen` + spot, `/sys/fs/bpf` hostPath, `service.enabled: false` |
   | `setup-aks-caretta` | `groundcover/caretta` 0.0.16 | `caretta.yaml` | `memory 512Mi`, `victoria-metrics-single.enabled: false`, `grafana.enabled: false`, `prometheusPort: 7117`, tolerations + spot |

2. **Chain amendment** — `setup-aks-o11y` (makefile:187) appends the three
   targets; `setup-aks` unchanged and flows through (FR-011). All installs
   are pinned `helm upgrade --install` → idempotent (FR-010): caretta
   re-upgrade went `REVISION: 2` cleanly on the live cluster.
3. **Prometheus-stack overlay** — new `setup-aks-prometheus-stack` step in
   the chain: chart 52.0.0 (unchanged pin), two values files
   (`monitoring/chart-values/prometheus-values.yaml`
   + `infra/azure/chart-values/prometheus-stack.yaml`). The shared file
   stays untouched (FR-007/FR-008). The overlay redefines:
   - `grafana.additionalDataSources`: Tempo URL `:3100` → `:3200`
     (fixes the datasource Finding 1 proved broken),
   - `prometheus.prometheusSpec.additionalScrapeConfigs`: redefine with the
     caretta job (correct regex) + a new beyla job (hostNetwork scrape,
     port 9090). Rejected alternative: a second datasource ConfigMap — it
     would leave the broken 3100 datasource in place as a duplicate.
4. **Dashboards unchanged**: `setup-dashboards` AKS branch and
   `monitoring/dashboards/application.yaml` untouched; the Service Map
   panel keeps its query and now receives data.

Not yet executed live (honestly flagged): the overlay's beyla scrape job,
the `:3200` datasource overlay, and Tempo-on-o11y placement. Designed from
verified facts; proving them live is implementation verification
(`helm template`, then a traffic check), not more research trials today.
