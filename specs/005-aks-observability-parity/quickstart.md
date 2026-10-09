# Quickstart — validate Complete Azure Application Observability

Reviewer runbook proving the three added capabilities end-to-end: service
map links (US-1), findable traces (US-2), automatic app measurements
(US-3), plus setup-keeps-working checks (US-4). Every expectation traces to
`data-model.md` and `research.md`; numbers in brackets cite SC/FR ids.

## Prerequisites

- A live AKS cluster built by this repo (`make setup-aks`) or one already
  running: `.env` has `STACK_MODE=aks`, your kubeconfig points at it.
- `kubectl`, `helm` installed locally.
- Grafana admin password: `kubectl get secret prometheus-stack-grafana -n
  monitoring -o jsonpath='{.data.admin-password}' | base64 -d`.
- **Traffic timing note**: the load generator is run deliberately at step 3
  (A-002). Traffic produced before setup makes the map/trace/check windows
  harder to select.

## 1. Install

```sh
make setup-aks-o11y
```

Expect success with no service mesh installed or required (SC-004; the
chain's targets contain no istio reference). If the cluster already ran
setup before, re-running converges (FR-010) — proceeds to step 3 directly.

## 2. Confirm the three capabilities landed

```sh
helm list -n monitoring --no-headers | grep -E "^tempo|^beyla|^caretta"
```

Expect three releases at the pinned charts: `tempo-3.1.0` (app 3.1.0),
`beyla-1.16.11` (app 3.32.0), `caretta-0.0.16` [FR-009].

```sh
kubectl get ds -n monitoring --no-headers
kubectl get pods -n monitoring -o wide --no-headers \
  | grep -E "beyla|caretta" | awk '{print $7}'
```

Expect `beyla` and `caretta` DaemonSets at READY = every node count, with
one pod per node across **all** pools (app, persistent, o11y, loadgen, and
the system pool), including spot-tainted nodes [SC-011, FR-013].

```sh
kubectl get pods -n monitoring -o wide --no-headers \
  | awk '{print $7}' | grep -vE "aks-(app|persistent|o11y|loadgen|nodepool1)" # empty
kubectl get pods -n monitoring -o wide --no-headers \
  | grep -E "tempo|prometheus-stack|loki|opentelemetry" | awk '{print $7}'
```

Expect every other added monitoring workload (tempo, the prometheus stack,
loki, otel collector) on `o11y`-pool nodes only [FR-013].

## 3. Generate traffic and check the three results

Start the bundled load generator and record the start time:

```sh
kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f scenarios/load-gen/load.yaml
date -u   # ← record this: __START__
```

Wait ~5 minutes, then set the window [SC-002]:

```sh
__END=$(date -u +%s)000; __START=$(date -u -d '5 minutes ago' +%s)000
```

### 3a. Service Map (US-1)

Open Grafana → **Application Dashboard** → `Service Map ☸️` panel with the
time range set to the recorded window. Expect ≥1 live edge between
application services (e.g. `cart → mysql`, `catalogue → user`
neighborhoods). Data flows via `caretta_links_observed` [FR-002]; a smoke
check from the CLI:

```sh
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode "query=caretta_links_observed{client_namespace=\"robot-shop\"}" \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']['result']), 'links')"
```

Expect `> 0` (research.md Finding 3 observed 42 such links under probe
traffic).

### 3b. Traces (US-2)

Open Grafana → Explore → select the **Tempo datasource** (the one whose
URL ends in `:3200`) and the recorded window, then run this TraceQL:

```
{resource.service.name="catalogue" && name="GET /products"}
```

Expect ≥1 result [FR-003]. Open the returned
trace — expect multiple spans with recorded request work (research.md
Finding 2 observed 3-span traces). If two Tempo sources appear, the one
still pointing at `:3100` outside this story's cluster would be stale
infrastructure — report it, do not work around it.

### 3c. Automatic app measurements (US-3)

Grafana → Explore → select **Prometheus** → query over the same window:

```promql
sum(increase(http_server_request_duration_seconds_count{service_namespace="robot-shop"}[$__range])) > 0
```

Expect ≥1 (research.md Finding 2 observed 47 recorded requests under probe
traffic) [FR-004].

## 4. Existing monitoring keeps working (US-4)

With equivalent traffic (including error-producing traffic — A-003:
success-only runs cannot prove error panels live) confirm the
Application Dashboard's **request errors, request volume, success rate,
and error logs** panels still show their data [SC-003, FR-005]. Nothing in
this story touched those panels or their metric sources.

## 5. Safe repeat runs [FR-010 / FR-011]

```sh
make setup-aks-o11y    # second run
helm list -n monitoring --no-headers | grep -E "^tempo|^beyla|^caretta"
```

Expect all three releases still present, then REPEAT step 3 on a FRESH
traffic window (restart the loadgen for a clean window). Both runs succeed,
one installation of each remains, and the three traffic results confirm
again. Optionally re-run the full `make setup-aks` for the SC-009 shape.

## 6. What this quickstart cannot verify here (handed off)

- EKS/local findings: `monitoring/chart-values/`, shared make targets, and
  `setup-observability` remain untouched — this is a PR-diff review check
  [SC-005, FR-007].
- Azure settings isolation: PR review finds zero new Azure settings inside
  shared values files [SC-006, FR-008].
- Latest-stable evidence: chart pins with their verification dates are
  recorded in `research.md` Findings 1–3 [SC-007].
