# Evidence — 002-azure-observability-stack

**Date**: 2026-10-05 · **Cluster**: `sre-stack-d6d56b` (AKS, eastus2, regular
pool mode) · **Branch**: `002-azure-observability-stack`

All outputs below are verbatim from the live cluster built and exercised for
this story. Nothing here is projected or "expected" output.

---

## 1. Cluster and node pools

```
### nodes
NAME                                 STATUS   ROLES    AGE    VERSION   WORKLOAD
aks-app-38663686-vmss000000          Ready    <none>   112m   v1.34.11   app
aks-app-38663686-vmss000001          Ready    <none>   112m   v1.34.11   app
aks-app-38663686-vmss000002          Ready    <none>   112m   v1.34.11   app
aks-loadgen-42931919-vmss000000      Ready    <none>   105m   v1.34.11   loadgen
aks-nodepool1-34308273-vmss000000    Ready    <none>   115m   v1.34.11
aks-o11y-58501446-vmss000000         Ready    <none>   107m   v1.34.11   o11y
aks-o11y-58501446-vmss000001         Ready    <none>   107m   v1.34.11   o11y
aks-persistent-31791686-vmss000000   Ready    <none>   110m   v1.34.11   persistent
aks-persistent-31791686-vmss000001   Ready    <none>   110m   v1.34.11   persistent
```

## 2. Workload placement (FR-002, SC-002)

`verify-aks-observability.sh` (created by this story, FR-012):

```
### verify-aks-observability.sh
PASS create-grafana-database-7wxpp: on o11y pool
PASS kiali-8965797f8-jb28g: on o11y pool
PASS loki-0: on o11y pool
PASS opentelemetry-collector-6f657f68b9-zcmg9: on o11y pool
PASS postgresql-psql-0: on o11y pool
PASS prometheus-prometheus-stack-kube-prom-prometheus-0: on o11y pool
PASS prometheus-stack-grafana-69cf49f45b-88p84: on o11y pool
PASS prometheus-stack-grafana-69cf49f45b-9vhkw: on o11y pool
PASS prometheus-stack-kube-prom-operator-7dbf86959d-dqfbb: on o11y pool
PASS prometheus-stack-kube-state-metrics-6df79dfc85-kt5tm: on o11y pool
PASS per-machine helper alloy: running on every node pool (app, loadgen, o11y, persistent, system)
PASS per-machine helper prometheus-stack-prometheus-node-exporter: running on every node pool (app, loadgen, o11y, persistent, system)
PASS datasource Prometheus: healthy (Grafana reports OK)
PASS datasource loki: reachable (query answered; /health route unavailable in this Grafana version)
observability verification: 0 failure(s)
```

Every monitoring/Kiali workload is on an `o11y` node; the two per-machine
helpers (Alloy, node-exporter) run on all five pools — the Clarification
2026-10-05 decision.

## 3. Endpoints and reachability (FR-004, FR-005, SC-003)

```
### get-service-endpoints
---------------------------- Azure AKS service endpoints -------------------------------
Visit Grafana dashboard http://4.153.46.236/grafana
Visit Prometheus http://4.153.46.236/prometheus
Visit Istio kiali http://4.153.46.236/kiali
-----------------------------------------------------------------------------------------

### HTTP checks (LB=4.153.46.236)
/grafana   : 302
/prometheus: 200
/kiali/    : 200
```

`/grafana` returns 302 → `/grafana/login` (Grafana's login redirect); the
login page itself returns 200.

## 4. Loki receives logs, with the labels the dashboards expect (FR-002, FR-006)

```
### Loki label set
{"status":"success","data":["__stream_shard__","app","container","instance","job","namespace","node","pod","service_name"]}

### Loki app label values
["alloy","cart","catalogue","defender-k8s-sensor","dispatch","grafana",
 "istio-ingressgateway","istiod","kiali","kube-state-metrics","load","loki",
 "mongodb","mysql","opentelemetry-collector","payment","prometheus",
 "prometheus-node-exporter","rabbitmq","ratings","redis","shipping","user","web"]
```

Sample line (from pod `cart-777874dd44-bdxqc`, `namespace=robot-shop`), with
the full label set Alloy attaches (`namespace`/`pod`/`container`/`node`/`app`/`job`):

```json
{"level":"info","time":1791212763418,"pid":1,"hostname":"cart-777874dd44-bdxqc","req":{...}}
```

## 5. Grafana datasources (FR-006)

- Prometheus: `healthy (Grafana reports OK)` via `/api/datasources/uid/prometheus/health`
- Loki: reachable — a query through Grafana answered with real frames. On
  this Grafana (10.1.5) the Loki plugin exposes no `/health` route (returns
  404 "Not found"), so the verifier falls back to a query probe.

## 6. Kiali traffic graph (FR-018, FR-019)

```
### Kiali version
Kiali v2.32.0 state= running

### Kiali graph robot-shop
nodes 14 edges 17
apps ['cart', 'catalogue', 'dispatch', 'load', 'mongodb', 'mysql', 'rabbitmq',
      'ratings', 'redis', 'shipping', 'unknown', 'user', 'web']
```

## 7. Deployment check (FR-011) — `make lint`

```
make lint
...
PASS infra/azure/chart-values/loki.yaml
PASS infra/azure/chart-values/alloy.yaml
PASS infra/azure/chart-values/otel-collector.yaml
PASS monitoring/chart-values/prometheus-values.yaml
PASS infra/azure/kiali/kiali.yaml
placement check: all files select and tolerate the o11y pool correctly
speckit-version: artifacts match installer pin v1.0.4
loom: check clean — adapters match regeneration
```

(The four `loom` warnings are pre-existing: the spec packs are 32 days old,
unrelated to this story.)

## 8. Offline chart renders (T003, T004)

```
### helm render loki (chart 18.13.7)
kind: Service
  name: "loki"
kind: StatefulSet
  name: "loki"
  replicas: 1
        workload: o11y

### helm render alloy (chart 1.13.0)
kind: DaemonSet
        - operator: Exists
```

## 9. Application traffic (Robot Shop + HotROD + load generator)

Robot Shop (12 workloads) and HotROD deployed to give the dashboards data.
The load generator drove a happy path at ~205 requests/minute, 0 failures,
and Prometheus scraped 61 targets with `istio_requests_total ≈ 24 req/s`.
The load generator was deleted after the evidence run (namespace `loadgen`
removed).

Error-Logs panels, `{app="<svc>"}` vs the panel filter `|~ `(?i)error``
(30-minute window):

```
web        all=  100  error-filter=  100
cart       all=  100  error-filter=    0
catalogue  all=  100  error-filter=    0
payment    all=  100  error-filter=    0
user       all=  100  error-filter=    0
ratings    all=  100  error-filter=  100
dispatch   all=  100  error-filter=  100
shipping   all=  100  error-filter=  100
```

The four services with `error-filter=0` (cart, catalogue, payment, user) are
empty because they logged no errors during the happy-path load — correct
behaviour for "Error Logs" panels, not a defect.

---

## 10. Findings fixed during implementation

The plan assumed three things that the live cluster disproved. Each was
fixed with an AKS-specific file under `infra/azure/`, leaving the shared
EKS/local files untouched (FR-017).

### 10.1 Alloy config crash-loop (FR-002)

The initial Alloy values used `regex = "(?s.*)"` in a `discovery.relabel`
rule. Go's RE2 engine rejects that Perl syntax, so every Alloy pod
crash-looped at config parse:

```
Error: /etc/alloy/config.alloy:48:21: `(?s.*)` error parsing regexp:
invalid or unsupported Perl syntax: `(?s.`
```

Fix: removed the regex line (the rule needs no regex). Alloy then ran 2/2 on
all nine nodes and logs flowed.

### 10.2 Kiali 1.63 graph API crash against Kubernetes 1.34 (FR-018/FR-019)

The shared v1.63 manifest produced a healthy pod but its graph API panicked
on the `Endpoints` API shape change:

```
{"error":"json: cannot unmarshal object into Go value of type
 []*kubernetes.RegistryEndpoint", ...}
```

Fix: rendered `kiali-server` 2.32.0 to `infra/azure/kiali/kiali.yaml`;
`setup-kiali-aks` applies it. Verified: graph API returns real nodes/edges,
UI 200. EKS/local keep the shared v1.63 manifest.

### 10.3 Optional collector crash-loop (FR-010)

`setup-optional-otel` never pinned its chart, so it floated to latest
(0.175.0) while the shared values pin image 0.94.0. The newer chart emits
component names (`file_log`/`k8s_attributes`/`otlp_grpc`) and config keys
(`memory_ballast`, `service.telemetry.metrics.address`) the old image
rejects:

```
error decoding 'receivers': unknown type: "file_log" ...
error decoding 'processors': unknown type: "k8s_attributes" ...
extensions' unknown type: "memory_ballast" ...
```

Fix: chart pinned to 0.81.2 (whose app version *is* 0.94.0), values at
`infra/azure/chart-values/otel-collector.yaml`, behind a `STACK_MODE=aks`
branch in `setup-optional-otel`. Verified: 1/1 Running.

```
### otel collector
POD                                        IMAGE
opentelemetry-collector-6f657f68b9-zcmg9   otel/opentelemetry-collector-contrib:0.94.0
```

### 10.4 Application Dashboard Error-Logs panels — label mismatch

The dashboards query `{app="<service>"}`, but Alloy only set `app` from
`app.kubernetes.io/name`, which Robot Shop pods do not carry (they label
`service=<name>`). Before the fix `{app="ratings"}` returned 0 rows while
`{container="ratings"}` returned 100. Fixed with a `service` → `app`
fallback relabel rule in `infra/azure/chart-values/alloy.yaml`. All eight
Robot Shop services now resolve `{app="<svc>"}` (section 9).

### 10.5 RDS dashboard removed on AKS

`setup-dashboards` applied the whole shared folder, including the AWS RDS
CloudWatch dashboard, which is meaningless on AKS. An AKS branch now skips
it:

```
configmap/app-dashboards unchanged
configmap/mysql-dashboards unchanged
configmap/rabbitmq-dashboards unchanged
skipping rds.yaml (AWS RDS dashboard, not applicable on AKS)
```

The already-installed `rds-cloudwatch-dashboards` ConfigMap was deleted from
the cluster. EKS/local still apply it.

---

## Caveats

- The two Grafana pods are a pre-existing consequence of Grafana's HA
  setting; both are on `o11y` and healthy.
- The Service Map panel on the Application Dashboard is intentionally empty
  on AKS: it queries `caretta_links_observed`, and Caretta is out of scope
  (not installed). Recorded, not removed.
- The Tempo datasource provisioned by the shared `prometheus-values.yaml`
  is broken on AKS because Tempo is out of scope — accepted in AD-006.
