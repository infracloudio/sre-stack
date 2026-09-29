# Team Demo — OTel Collector as Unified Ingestion Backbone

A 20–25 minute walkthrough. Talking points on the left, commands to run on the
right. Keep Grafana (http://localhost:3000) open in one tab and a Terminal
window visible.

Before starting:

```bash
# Make sure the demo is currently emitting telemetry — run this fresh
# 60 seconds before the demo so trace data is current
kubectl delete -f 06-validation/demo.yaml ; sleep 2
kubectl apply -f 06-validation/demo.yaml
```

---

## Part 1 — The problem we're solving (3 min)

> *"Today every signal in our observability stack has its own ingestion path.
> Metrics go through Prometheus scraping, logs go through Promtail, traces
> come into Tempo via the OTel Collector, AWS metrics go through YACE, and
> Kubernetes events aren't really collected at all. Five separate pipelines,
> five places to configure metadata enrichment, redaction, and sampling.
> When something breaks, we can't easily jump from a trace to its logs
> because each tool labels pods differently."*

Show the **before** diagram from `docs/architecture.md`.

> *"The industry direction is clear — the OTel Collector becomes the single
> ingestion backbone, every signal flows through it, and we get consistent
> Kubernetes metadata across the board. This means: one place to redact
> sensitive fields, one place to sample, and **cross-signal correlation
> actually works** because every signal carries the same `service.name`,
> `k8s.pod.name`, and `k8s.namespace.name` attributes."*

---

## Part 2 — What we deployed (5 min)

Show the **after** diagram from `docs/architecture.md`.

> *"We deployed the collector in two tiers, which is the standard pattern."*

```bash
kubectl -n observability get pods -l app.kubernetes.io/name=opentelemetry-collector
```

Point at the output:

- **Agent (DaemonSet)** — one pod per node, runs everything that needs
  node-local access (filesystem, kubelet API, host /proc and /sys).
- **Gateway (Deployment)** — central pod, runs everything that's
  cluster-wide (Kubernetes events, cluster-level metrics) plus cross-cutting
  processing like tail sampling, redaction, and routing.

```bash
# Show what the agent collects locally
kubectl -n observability exec ds/otel-agent-agent -- ls /var/log/pods | head
```

> *"That's `filelogreceiver` tailing real pod logs on disk. No Promtail.
> Same collector also runs `hostmetricsreceiver` (CPU, memory, disk, network
> from /proc) and `kubeletstatsreceiver` (per-pod CPU/memory from the
> kubelet)."*

```bash
# Show the gateway receivers
kubectl -n observability get cm otel-gateway -o yaml | grep -E "k8s_cluster|k8sobjects|otlp" | head -10
```

> *"The gateway has `k8s_cluster` (cluster-level resource metrics), `k8sobjects`
> (Kubernetes events as log records), and the OTLP receiver where apps and
> agents send everything else."*

---

## Part 3 — Show each signal flowing (8 min)

### 3a. Traces

Open Grafana → Explore → Tempo → Search → Service Name: `demo-app` → Run.

> *"This is `demo-app`, our load generator. Each trace flows: app → agent's
> OTLP receiver → gateway → Tempo. Click on any trace."*

Click a trace, then click on the `okey-dokey-0` span.

> *"Look at the Resource attributes panel — every span carries
> `service.name`, `k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name`.
> Those were not in the app's code — they were added by the
> `k8sattributes` processor in the collector pipeline."*

### 3b. Logs

Switch data source to Loki. Code mode. Paste:

```
{k8s_namespace_name="demo"}
```

> *"Same `k8s_namespace_name` label. These logs came from `filelogreceiver`
> on the agent, with `k8sattributes` enrichment applied identically to how
> it was applied to traces. Same processor, same pipeline pattern, same
> labels."*

### 3c. Kubernetes events

In the same Loki view, paste:

```
{k8s_resource_name=~".+"}
```

> *"These are Kubernetes events — pod creates, container starts, schedule
> decisions — coming in as log records from the gateway's `k8sobjects`
> receiver. Previously we weren't collecting these at all. Now they're a
> first-class signal in the same backend as application logs."*

### 3d. Infrastructure metrics

Switch data source to Prometheus. Paste:

```
system_cpu_load_average_1m
```

> *"Host metrics from the agent's `hostmetricsreceiver`."*

```
k8s_pod_cpu_usage{k8s_namespace_name="demo"}
```

> *"Per-pod metrics from `kubeletstatsreceiver`, filtered to our demo
> namespace using the **same** `k8s_namespace_name` label that's on the
> logs and traces."*

```
k8s_pod_phase
```

> *"Cluster-level state from `k8sclusterreceiver` on the gateway. None of
> this needs Prometheus to scrape anything — it all flows OTLP → gateway
> → `prometheusremotewrite` → Prometheus."*

---

## Part 4 — The payoff: cross-signal correlation (4 min)

> *"The whole point of unifying ingestion: every signal carries the same
> identifying labels, so we can pivot across them. Let me show you the
> same pod three ways."*

Pick one demo-logger pod name:

```bash
kubectl -n demo get pods -l app=demo-logger -o name
```

Copy the pod name (e.g. `demo-logger-xxxxx`). Then in Grafana:

**Logs** — in Loki:

```
{k8s_namespace_name="demo", k8s_pod_name="demo-logger-xxxxx"}
```

**Metrics** — in Prometheus:

```
k8s_pod_cpu_usage{k8s_namespace_name="demo", k8s_pod_name="demo-logger-xxxxx"}
```

**Traces** — in Tempo Search → Service Name `demo-app` → Tags → `k8s.pod.name` = `demo-logger-xxxxx` (or the demo-traces pod).

> *"Same `k8s_pod_name` label across all three. That's not magic — it's the
> `k8sattributes` processor running identically on every pipeline. If we'd
> have used five different collectors, getting consistent labeling would
> have been a per-tool config exercise."*

---

## Part 5 — What's next (3 min)

> *"What's in scope but we haven't done yet — and what we'd tackle next:"*

1. **Migrate Prometheus scraping into the collector** — the `prometheusreceiver`
   with a target-allocator lets the collector take over scrape jobs incrementally,
   one ServiceMonitor at a time. The skeleton is in `07-prometheus-scrape-migration/`.

2. **Decide YACE's fate.** Either keep YACE (simpler, writes to Prometheus
   directly) or move CloudWatch into the collector via `awscloudwatchreceiver`
   (unified config, same redaction pipeline, but heavier per-namespace
   config). Both options are stubbed in `08-yace-decision/`.

3. **Tail sampling & redaction** — the gateway is the natural place for both.
   We'd add `tail_sampling` processor (drop healthy traces, keep errors) and
   `transform` processor (redact PII fields) before exporters.

4. **App SDK instrumentation** — out of scope for this work but the obvious
   complement; once apps emit OTLP directly, we delete the Prometheus
   scraping step entirely.

> *"What's explicitly out of scope: replacing Prometheus with Mimir,
> removing Grafana Beyla (keep it as an eBPF source feeding the same
> collector), and the app SDK instrumentation."*

---

## Q&A preparation — likely questions and answers

**"Why two tiers and not one?"**
> Agent runs on every node so it can read local files and the kubelet API.
> Gateway is cluster-wide so we have one place to do tail sampling, redaction,
> and routing decisions — those things make no sense to do per-node.

**"What if the gateway is down — do we lose telemetry?"**
> Agent has a configurable send queue and retries. With persistent queue
> enabled (`file_storage` extension), it survives gateway outages of minutes
> to hours. The trade-off is disk on every node.

**"How much overhead does the collector add?"**
> In our lab, the agent runs ~50–100MB RAM per node and the gateway ~200MB
> for our workload. The receivers + k8sattributes are the heaviest pieces.
> In production we'd resource-cap aggressively and rely on tail sampling
> to limit egress volume.

**"Why OTLP into Loki and not the dedicated `loki` exporter?"**
> The `loki` exporter was deprecated in favor of OTLP. Loki 3.x natively
> ingests OTLP at `/otlp/v1/logs`, and uses the same attribute-to-label
> rules across our whole pipeline. One protocol everywhere.

**"What does this cost us to migrate?"**
> Pure YAML/Helm work — no application code changes. Each signal type
> migrates as a separate PR. Rollback is `helm rollback`. That's why we
> can phase it (logs first, then metrics, then optionally Prom scraping).

**"What if we want to add a new backend later — say, Datadog?"**
> Add the exporter to the gateway. The receivers and processors don't
> change. Vendor swap = config diff, not a re-platforming exercise. That's
> the architectural value over the fragmented approach.

---

## Backup commands for "show me the YAML" moments

```bash
# Show the actual rendered collector config (the source of truth)
kubectl -n observability get cm otel-gateway -o yaml | yq '.data."relay.yaml"'
kubectl -n observability get cm otel-agent-agent -o yaml | yq '.data."relay.yaml"'

# Verify what's actually been deployed
helm -n observability list
helm -n observability get values otel-gateway
helm -n observability get values otel-agent
```
