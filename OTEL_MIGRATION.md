# OpenTelemetry Migration — Demo Guide

This document covers the full OTel migration scope added to `sre-stack`:
a two-script demo that shows the observability stack **before** and **after** migrating
to OpenTelemetry Collector, with Robot Shop + HotROD running on a local k3d cluster.

---

## Scope

| Signal | Before | After |
|--------|--------|-------|
| **Logs** | Promtail → Loki 2.x (no trace correlation) | filelog (OTel agent) → OTel gateway → Loki 3.x (OTLP, structured metadata, trace\_id on every log) |
| **Metrics** | Prometheus scraping only (no host/kubelet metrics) | hostmetrics + kubeletstats (OTel agent) + k8s\_cluster (gateway) → Prometheus remote\_write |
| **Traces** | Istio ingress hops only (1–2 spans, no app-level detail) | App OTLP → OTel agent → gateway → Tempo (full span tree: frontend / DB / Redis calls) |
| **Prometheus scraping** | ServiceMonitor-based | OTel gateway prometheusreceiver with kubernetes\_sd\_configs |
| **K8s enrichment** | None | k8sattributes processor stamps `k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name` + all pod labels on every signal |

---

## Architecture

### Before

```
Robot Shop pods ──► Promtail ──────────────────► Loki 2.x
HotROD          ──► Jaeger endpoint (Istio)  ──► Tempo  (1-2 spans)
All pods        ──► Prometheus scraping       ──► Prometheus
                    (no host/kubelet metrics)
```

### After

```
                    ┌─────────────────────────────────────────────┐
                    │  OTel Agent DaemonSet (one pod per node)    │
Robot Shop pods ───►│  filelog | hostmetrics | kubeletstats        │
HotROD          ───►│  k8sattributes processor                    │
                    └──────────────┬──────────────────────────────┘
                                   │ OTLP gRPC
                                   ▼
                    ┌─────────────────────────────────────────────┐
                    │  OTel Gateway Deployment (o11y nodes)       │
                    │  k8sobjects | k8s_cluster | prometheus rcvr │
                    │  k8sattributes + resource processors        │
                    └───┬──────────────┬────────────┬────────────┘
                        │              │            │
                        ▼              ▼            ▼
                     Tempo          Prometheus   Loki 3.x
                  (full traces)  (remote_write) (OTLP ingest)
```

---

## New Files

| File | Purpose |
|------|---------|
| `demo-1-before.sh` | Builds the "before" state: k3d cluster + Istio + Prometheus + Loki 2.x + Tempo + Robot Shop + HotROD |
| `demo-2-migrate-otel.sh` | Runs the full 8-step OTel migration live |
| `app/robot-shop/robot-shop-local-values.yaml` | Helm overrides for the 4-node k3d cluster (single app node, no persistent node) |
| `monitoring/chart-values/otel-agent-values.yaml` | OTel Agent DaemonSet — filelog, hostmetrics, kubeletstats |
| `monitoring/chart-values/otel-gateway-values.yaml` | OTel Gateway Deployment — OTLP fan-out to Tempo + Prometheus + Loki |
| `monitoring/chart-values/otel-gateway-prom-scrape-values.yaml` | Gateway with added prometheusreceiver (kubernetes\_sd\_configs) |
| `monitoring/chart-values/loki-v3-values.yaml` | Loki 3.x (grafana/loki 7.0.0) — OTLP ingest, tsdb schema, allow\_structured\_metadata |

---

## Prerequisites

- Docker Desktop (≥ 8 GB RAM allocated)
- k3d ≥ 5.6
- kubectl
- helm ≥ 3.12
- istioctl (for `make setup-istio`)
- Ports 8080 and 18080 free on localhost

---

## Running the Demo

### Step 1 — Build the "before" state

```bash
./demo-1-before.sh
```

This script:
1. Deletes any existing `sre-stack-local` k3d cluster and creates a fresh 4-node one
2. Labels nodes: `agent-0/1` → `workload=o11y` (tainted), `agent-2` → `workload=app`
3. Installs: kube-prometheus-stack, Loki 2.x + Promtail, Tempo, Istio
4. Deploys Robot Shop (with Istio sidecar injection) and HotROD
5. Starts port-forwards: `localhost:8080` (Grafana + Robot Shop via Istio) and `localhost:18080` (HotROD)
6. Sends 30 warmup requests to populate Istio metrics

**Access:**
- Grafana: `http://localhost:8080/grafana` (admin / prom-operator)
- Robot Shop: `http://localhost:8080`
- HotROD: `http://localhost:18080`

**What to show (before — limitations):**

| Check | Result |
|-------|--------|
| Application Dashboard → Service Map | ✅ Istio request rates visible |
| Explore → Prometheus → `system_cpu_time_seconds_total` | ❌ No data — no host metrics |
| Explore → Prometheus → `k8s_deployment_desired` | ❌ No data — no cluster-state metrics |
| Explore → Tempo → Search | ❌ 1–2 Istio ingress spans only; no Redis/DB call visibility |
| Explore → Loki → `{namespace="robot-shop"}` | ❌ Logs exist but no `trace_id` field |

---

### Step 2 — Run the OTel migration

```bash
./demo-2-migrate-otel.sh
```

Eight steps, each idempotent:

| Step | What happens |
|------|-------------|
| 1 | Helm repo setup (open-telemetry, grafana, prometheus-community) |
| 2 | Enable Prometheus `remote_write` receiver |
| 3 | Uninstall loki-stack (Loki 2.x + Promtail) → install grafana/loki 7.0.0 (Loki 3.x, OTLP) |
| 4 | Deploy OTel Gateway — receives OTLP from agents, fans out to Tempo / Prometheus / Loki |
| 5 | Deploy OTel Agent DaemonSet — filelog + hostmetrics + kubeletstats on every node |
| 6 | Rewire HotROD: remove `JAEGER_ENDPOINT`, set `OTEL_EXPORTER_OTLP_ENDPOINT=gateway:4318` |
| 7 | Generate traffic: 40 Robot Shop requests + 20 HotROD dispatches |
| 8 | Upgrade gateway to add prometheusreceiver (kubernetes\_sd\_configs scraping) |

---

## What to Validate After Migration

### Logs (Loki 3.x)

```
Explore → Loki → {k8s_namespace_name="robot-shop"}
```
- Every log line has `k8s.pod.name`, `k8s.namespace.name`, `trace_id` as structured metadata
- `trace_id` is clickable → jumps to the exact trace in Tempo

### Traces (Tempo)

```
Explore → Tempo → Search → Service: hotrod
```
- Each dispatch shows 5+ spans: `frontend` → `customer` → `driver` → `route` → `redis`
- Click any span → `k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name` visible
- Click "Logs for this span" → correlated Loki logs for that pod/time window

### Metrics (Prometheus)

```
Explore → Prometheus → system_cpu_time_seconds_total   # host metrics (OTel agent)
Explore → Prometheus → k8s_deployment_desired          # cluster state (OTel gateway)
Explore → Prometheus → container_cpu_usage_seconds_total # kubeletstats
Explore → Prometheus → up{job="grafana"}               # OTel Prometheus scraping
```

### Application Dashboard

- Service Map still populated (Istio `istio_requests_total` metrics continue)
- Service Error Log panels now query Loki by pod name — no "No data"

---

## Key Design Decisions

### Two-tier collector architecture

The **agent** runs as a DaemonSet with `tolerations: [{operator: Exists}]` so it collects
from every node including tainted o11y nodes. It only ships `filelog`, `hostmetrics`,
and `kubeletstats` — node-local signals. Everything is forwarded via OTLP gRPC to the
**gateway** Deployment which runs on the o11y nodes and handles enrichment and fan-out.

This avoids giving every agent pod the RBAC rights needed to talk to Loki/Prometheus/Tempo,
keeps exporter retry logic in one place, and lets you scale the gateway independently.

### k8sattributes processor

Both agent and gateway run `k8sattributes` with `extractAllPodLabels: true`. This stamps
`k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name`, and every pod label on every span,
metric, and log record. This is the single key that enables cross-signal correlation in Grafana
without any application-side instrumentation changes.

### Loki 3.x + OTLP ingest

`loki-stack` (Loki 2.9) has no OTLP endpoint. `grafana/loki 7.0.0` (Loki 3.6.7) adds
`/otlp/v1/logs` and `allow_structured_metadata: true`, which stores OTel attributes
(including `trace_id`) alongside log lines as indexed structured metadata rather than
requiring label cardinality to blow up.

### `resource/loki-labels` processor

Loki OTLP ingest won't index resource attributes as stream labels unless you tell it which
ones to use. The `resource/loki-labels` processor inserts a `loki.resource.labels` hint:

```yaml
resource/loki-labels:
  attributes:
    - action: insert
      key: loki.resource.labels
      value: service.name,k8s.namespace.name,k8s.pod.name,k8s.container.name,app
```

This keeps stream label cardinality low while making the labels the dashboard queries need
available for filtering.

### Local cluster overrides (`robot-shop-local-values.yaml`)

The upstream Robot Shop chart targets a multi-node EKS cluster with separate persistent
and app node groups. For the 4-node k3d demo cluster:

- All `workload=persistent` nodeSelectors are redirected to `workload=app`
- All replica counts reduced to 1 (avoids required podAntiAffinity on a single app node)
- `affinity: null` (not `{}`) — Helm merges maps, so an empty map leaves base affinity
  unchanged; `null` explicitly deletes the key

---

## Cluster Node Layout

```
k3d-sre-stack-local-server-0    control-plane
k3d-sre-stack-local-agent-0     workload=o11y  (taint: o11y=true:NoSchedule)
k3d-sre-stack-local-agent-1     workload=o11y  (taint: o11y=true:NoSchedule)
k3d-sre-stack-local-agent-2     workload=app
```

OTel agents run on all 4 nodes (toleration: `Exists`).
OTel gateway, Loki, Prometheus, Tempo, Grafana run on agent-0/1 (o11y nodes).
Robot Shop and HotROD run on agent-2 (app node).
