# OpenTelemetry Migration

## Scope

The goal of this migration is to replace the fragmented, signal-siloed observability stack with a unified OpenTelemetry pipeline that gives full cross-signal correlation — logs, metrics, and traces enriched with the same Kubernetes context on every record.

### Problems with the existing stack

| Area | Problem |
|------|---------|
| **Logs** | Promtail ships logs to Loki 2.x with no `trace_id`. You cannot click from a log line to the trace that caused it. |
| **Metrics** | Prometheus only scrapes what has a ServiceMonitor. Host CPU, memory, disk (node-level) and pod resource usage (kubelet) are invisible. |
| **Traces** | HotROD sends to a Jaeger endpoint intercepted by Istio. Only 1–2 ingress-hop spans appear in Tempo — no Redis calls, no DB calls, no root-cause visibility. |
| **K8s context** | No signal carries `k8s.pod.name`, `k8s.namespace.name`, or `k8s.node.name`. Cross-signal correlation requires manual label matching. |
| **Prometheus scraping** | No path from OTel to Prometheus. Two separate scrape pipelines with no shared enrichment. |

---

## What was built

### Two-tier OTel Collector

The migration introduces a two-tier collector architecture:

```
[OTel Agent DaemonSet]   — one pod per node, node-local collection
        │
        │  OTLP gRPC
        ▼
[OTel Gateway Deployment] — cluster-wide aggregation and fan-out
        │
        ├──► Loki 3.x      (logs via OTLP HTTP)
        ├──► Prometheus     (metrics via remote_write)
        └──► Tempo          (traces via OTLP gRPC)
```

**Why two tiers?** The agent only needs host-level RBAC. The gateway holds all exporter config, retry logic, and enrichment in one place and can be scaled independently. This also means rotating an exporter endpoint (e.g., pointing to a different Loki) requires only a gateway change, not a DaemonSet rollout.

---

## Files and what they solve

### `monitoring/chart-values/otel-agent-values.yaml`

Deploys the OTel Collector as a DaemonSet on every node (including tainted o11y nodes via `tolerations: [{operator: Exists}]`).

**Receivers enabled:**

| Receiver | Solves |
|----------|--------|
| `filelog` | Replaces Promtail. Reads CRI-format logs from `/var/log/pods/**`, parses them, and forwards via OTLP. Logs now carry `trace_id` as structured metadata. |
| `hostmetrics` | Collects CPU, memory, disk, network per node. Previously invisible in Prometheus. |
| `kubeletstats` | Collects per-pod and per-container resource usage from the kubelet API. Previously invisible. Note: `insecure_skip_verify: true` required because k3d kubelet certs have no IP SANs. |

The `k8sattributes` preset stamps every log, metric, and trace with:
- `k8s.pod.name`
- `k8s.namespace.name`
- `k8s.node.name`
- All pod labels (via `extractAllPodLabels: true`)

This is the single change that enables cross-signal correlation without any application code changes.

---

### `monitoring/chart-values/otel-gateway-values.yaml`

Deploys the OTel Collector as a Deployment on the o11y nodes. Receives OTLP from all agents and fans out to three backends.

**Receivers enabled:**

| Receiver | Solves |
|----------|--------|
| `otlp` | Accepts signals from all agent pods |
| `k8sobjects` | Ingests Kubernetes events (CrashLoopBackOff, OOMKilled, scheduling failures) as log records → Loki. Previously these were only visible in `kubectl describe`. |
| `k8s_cluster` | Emits cluster-state metrics: deployment desired/ready replicas, pod phases, node conditions → Prometheus. Replaces kube-state-metrics for this use case. |

**Key processors:**

`resource/app-label` — synthesises an `app` resource attribute from pod labels so Loki stream labels match existing dashboard queries:
```yaml
resource/app-label:
  attributes:
    - action: insert
      key: app
      from_attribute: k8s.pod.labels.service   # Robot Shop uses service: web
    - action: upsert
      key: app
      from_attribute: k8s.pod.labels.app        # HotROD and others use app: hotrod
```

`resource/loki-labels` — tells Loki 3.x which resource attributes to index as stream labels (keeps cardinality low while making the labels dashboards need available):
```yaml
resource/loki-labels:
  attributes:
    - action: insert
      key: loki.resource.labels
      value: service.name,k8s.namespace.name,k8s.pod.name,k8s.container.name,app
```

---

### `monitoring/chart-values/loki-v3-values.yaml`

Replaces `loki-stack` (Loki 2.9, no OTLP) with `grafana/loki 7.0.0` (Loki 3.6.7).

| Change | Why |
|--------|-----|
| OTLP ingest at `/otlp/v1/logs` | OTel gateway pushes logs directly — no Promtail needed |
| `allow_structured_metadata: true` | Stores OTel attributes (`trace_id`, `k8s.pod.name`, etc.) alongside log lines as queryable structured metadata without blowing up stream label cardinality |
| tsdb/v13 schema | Required for Loki 3.x |

---

### `monitoring/chart-values/otel-gateway-prom-scrape-values.yaml`

Extends the gateway with a `prometheusreceiver` using `kubernetes_sd_configs` (endpoint discovery). This makes the OTel gateway responsible for Prometheus scraping, replacing direct ServiceMonitor-based scraping for a known target set.

Scrape targets: Grafana (`/grafana/metrics`) and Prometheus self-metrics (`/metrics`). Results are pushed to Prometheus via `prometheusremotewrite` — the same exporter used for all other metrics, so they carry the same k8s enrichment.

Additional RBAC added: the gateway's ClusterRole gets `get/list/watch` on `endpoints` and `services`, which `kubernetes_sd_configs` (role: endpoints) requires.

---

### `monitoring/dashboards/application.yaml`

Updated the Service Error Log panels to use Loki stream labels that OTel actually emits. The original queries used `{app="web"}` (Promtail-style label). Robot Shop pods carry `service: web` (not `app`), so after migration these panels showed "No data".

Fix: queries now use `k8s_namespace_name` + `k8s_pod_name` regex, which are guaranteed stream labels set by `resource/loki-labels`:

```
Before: {app="web"} |~ `(?i)error`
After:  {k8s_namespace_name="robot-shop", k8s_pod_name=~"web-.*"} |~ `(?i)error`
```

---

### `app/robot-shop/robot-shop-local-values.yaml`

The upstream Robot Shop chart targets a multi-node EKS cluster with separate `workload=persistent` and `workload=app` node pools. The local k3d demo cluster has only one app node. This override file:

- Redirects all `workload=persistent` nodeSelectors to `workload=app` (MySQL, MongoDB, Redis, RabbitMQ)
- Reduces all replicas to 1 (avoids required podAntiAffinity deadlock on a single node)
- Uses `affinity: null` (not `affinity: {}`) — Helm merges maps, so an empty map leaves the base chart's podAntiAffinity unchanged; `null` explicitly removes the key

---

## What changed in each signal after migration

### Logs
- Promtail → OTel filelog receiver
- Loki 2.x → Loki 3.x with OTLP ingest
- Every log line now carries `trace_id`, `k8s.pod.name`, `k8s.namespace.name` as structured metadata
- Kubernetes events (CrashLoopBackOff, OOMKilled) now flow into Loki as log records

### Metrics
- `system_cpu_time_seconds_total` — host CPU per node (was missing)
- `container_cpu_usage_seconds_total` — per-pod usage from kubelet (was missing)
- `k8s_deployment_desired` / `k8s_deployment_ready` — cluster state (was missing)
- All metrics carry `k8s.namespace.name`, `k8s.pod.name` etc. via `resource_to_telemetry_conversion`

### Traces
- HotROD previously sent to `JAEGER_ENDPOINT` (Istio-intercepted, 1–2 spans)
- Now sends to `OTEL_EXPORTER_OTLP_ENDPOINT=otel-gateway:4318` (direct OTLP)
- Full span tree visible: `frontend` → `customer` → `driver` → `route` → `redis`
- Every span carries `k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name`
- "Logs for this span" in Tempo jumps directly to the correlated Loki logs

---

## Demo scripts

Two scripts reproduce the before/after state on a local k3d cluster:

- `demo-1-before.sh` — provisions the full stack in the pre-migration state
- `demo-2-migrate-otel.sh` — runs the 8-step live migration

See `OTEL_MIGRATION.md` run instructions or the script headers for prerequisites and usage.
