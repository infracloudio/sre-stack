# Research: Alert Rules for the Demo Shop on Azure

Live run against AKS cluster `sre-stack-452138` (southindia), kube context `sre-stack-452138`, 2026-10-27. Every output block below is pasted from the terminal. Findings are added one at a time, each approved by the developer before the next (constitution principles VIII and IX).

## Finding 1 — Does Prometheus pick up a rule labelled `release: prometheus-stack`?

**Question.** The story says rules go in a PrometheusRule with the label `release: prometheus-stack`. Will Prometheus load it? What rules exist today?

**Failure first — the cluster was down.** The kube context pointed at a cluster that did not resolve:

```
Unable to connect to the server: dial tcp: lookup sre-stack--rijo-john-improv-674579-mb9wxcdx.hcp.southindia.azmk8s.io on 127.0.0.53:53: no such host
```

`az aks list` showed the cluster was stopped, not deleted:

```
Name              Power    State      K8s
----------------  -------  ---------  -----
sre-stack-452138  Stopped  Succeeded  1.34
```

It was restarted with `az aks start` (about 5 minutes). All Helm releases from 14–23 October were still there, and every pod in `monitoring` and `robot-shop` became Ready. Lesson for the demo: a stopped cluster is a normal state between sessions; start it before any live check.

**Run 1 — The rule selector on the Prometheus object, and the existing rules.**

```
prometheus-stack-kube-prom-prometheus
ruleSelector={"matchLabels":{"release":"prometheus-stack"}}
ruleNamespaceSelector={}
ruleSelectorNilUsesHelmValues-equivalent: serviceMonitorSelector={"matchLabels":{"release":"prometheus-stack"}}
```

```
NAMESPACE    NAME                              AGE
monitoring   kube-prometheus-stack-rule-name   13d
```

The one existing rule is the Bookinfo rule the story says to leave alone (first lines):

```
  labels:
    app: kube-prometheus-stack
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 52.0.0
    chart: kube-prometheus-stack-52.0.0
    heritage: Helm
    release: prometheus-stack
  name: kube-prometheus-stack-rule-name
  namespace: monitoring
...
spec:
  groups:
  - name: GroupA
    rules:
    - alert: reviewsHTTPError
```

**Run 2 — Is there an Alertmanager?**

```
No resources found
```

(`kubectl get alertmanager -A`; no Alertmanager pod in `monitoring` either.)

**What it means.**
- A PrometheusRule with `release: prometheus-stack` is loaded from any namespace (`ruleNamespaceSelector` is empty). The story's assumption holds.
- The chart's default Kubernetes rule packs are off. The only PrometheusRule is the Bookinfo one. All five alerts must be written from scratch.
- No Alertmanager exists. Alerts can only be seen as firing on the Prometheus Alerts page. That is enough for this story; Alertmanager is story 2.

## Finding 2 — Do the OOM kill, restart and unavailable-replica metrics appear during the cart fault?

**Question.** Which metrics show an OOM kill, a container restart and an unavailable replica, and do they carry a usable `service` label (the story requires `namespace` and `service` on every alert)?

**Run 1 — Before any fault** (`kube_pod_container_status_restarts_total{namespace="robot-shop"}`): 10 series, one per container (cart, mongodb, mysql, mysql-exporter, payment, ratings, redis, shipping, user, web), all 0. Each series has `container`, `namespace` and `pod`. It also has a `service` label, but its value is the monitoring tool, not the shop service:

```
{'__name__': 'kube_pod_container_status_restarts_total', 'container': 'cart', 'endpoint': 'http', 'instance': '10.244.4.229:8080', 'job': 'kube-state-metrics', 'namespace': 'robot-shop', 'pod': 'cart-6cffbd788-mnbxf', 'service': 'prometheus-stack-kube-state-metrics', 'uid': '59a5c6b7-5961-4cef-9f17-f2f2ff7ce113'} 0
```

`kube_pod_container_status_last_terminated_reason{namespace="robot-shop"} == 1` and the `terminated_reason ... reason="OOMKilled"` query both returned `success 0 series`.

A first attempt at these queries failed with `json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)`. The local connection to Prometheus was not listening yet when the queries went out. Fixed with a proper wait, not a cluster problem.

**Run 2 — The fault.** Load generator started (`kubectl apply -f infra/azure/load-gen/load.yaml`, pod `load-cb796c98b-qdbdt` Running). Then:

```
bash infra/azure/scenario-02/cart-oom-kill.sh start
Lowering the cart memory allowance to 24Mi (cart container only)...
deployment.apps/cart resource requirements updated
deployment.apps/cart annotated
Waiting up to 60s for the cluster to kill the cart container for running out of memory...
RESULT: fault active (cart container was killed for running out of memory within 60s)
```

45 seconds later, Prometheus returned:

```
### kube_pod_container_status_restarts_total{namespace="robot-shop",container="cart"}
{'__name__': 'kube_pod_container_status_restarts_total', 'container': 'cart', 'namespace': 'robot-shop', 'pod': 'cart-6cffbd788-mnbxf'} 0
{'__name__': 'kube_pod_container_status_restarts_total', 'container': 'cart', 'namespace': 'robot-shop', 'pod': 'cart-769b547b68-5z7gq'} 2
### kube_pod_container_status_last_terminated_reason{namespace="robot-shop"} == 1
{'__name__': 'kube_pod_container_status_last_terminated_reason', 'container': 'cart', 'namespace': 'robot-shop', 'pod': 'cart-769b547b68-5z7gq', 'reason': 'OOMKilled'} 1
### kube_pod_container_status_terminated_reason{namespace="robot-shop",reason="OOMKilled"} == 1
{'__name__': 'kube_pod_container_status_terminated_reason', 'container': 'cart', 'namespace': 'robot-shop', 'pod': 'cart-769b547b68-5z7gq', 'reason': 'OOMKilled'} 1
```

`container_oom_events_total{namespace="robot-shop"}` returned 53 series and every value was 0, including both cart pods. It did not move during a real OOM kill.

**Run 3 — Unavailable replicas, while the fault was active.**

```
[('__name__', 'kube_deployment_status_replicas_unavailable'), ('container', 'kube-state-metrics'), ('deployment', 'cart'), ('endpoint', 'http'), ('instance', '10.244.4.229:8080'), ('job', 'kube-state-metrics'), ('namespace', 'robot-shop'), ('pod', 'prometheus-stack-kube-state-metrics-d9476887b-bvbg6'), ('service', 'prometheus-stack-kube-state-metrics')] 1
```

(My own first print of this query dropped the `deployment` label, so the cart was not visible; I re-ran it with all labels.) `kube_deployment_labels{...,deployment="cart"}` returned 0 series.

**Revert.**

```
Waiting up to 60s for cart to run cleanly...
RESULT: fault reverted (cart runs at the allowance the shop is installed with, no further out-of-memory kills)
RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)
```

**What it means.**
- Restart alert: `kube_pod_container_status_restarts_total`, using how much it rose in a window. The count is per pod, and the fault replaced the pod.
- OOM alert: `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`. `terminated_reason` shows the same but is only the current state. Do not use `container_oom_events_total`.
- Unavailable-replica alert: `kube_deployment_status_replicas_unavailable`; it showed 1 for the cart during the fault.
- The ready-made `service` label always names the monitoring tool. On the pod metrics, the shop service name is in `container`; on the deployment metric it is in `deployment`. Each rule builds `service` itself.
- The metrics were in Prometheus within 45 seconds of the fault starting.
- The OOM, restart and unavailable-replica alerts have not been proven to fire yet, because the rules do not exist. That check belongs to the verification run.

## Finding 3 — Which metric shows 5xx responses, and when did they happen?

**Question.** Which request metric can drive the "high share of 5xx responses" alert, does it carry a usable `service` value, and is there any 5xx when no fault runs?

**Run 1 — Request-count metrics that exist.** Two sources:

```
http_server_request_duration_seconds_count   (Beyla)
istio_requests_total                         (Istio sidecars)
```

**Run 2 — Istio, per destination workload, 5xx only** (`reporter="destination"`):

```
cart      response_code 503   6
rabbitmq  response_code 503   1
web       response_code 503   117
```

Labels on the cart 503 series include `destination_workload="cart"`, `destination_service_name="cart"`, `namespace="robot-shop"`, `reporter="destination"`, `response_code="503"`, `response_flags="URX,UF"`. There is no `service` label on this metric.

**Run 3 — Beyla, 5xx only**, summed by `service_name`:

```
{'http_response_status_code': '503', 'service_name': 'envoy'} 234
{'http_response_status_code': '503', 'service_name': 'cart'} 6
{'http_response_status_code': '503', 'service_name': 'web'} 117
{'http_response_status_code': '500', 'service_name': 'shipping'} 1
```

`http_server_request_duration_seconds_count{k8s_namespace_name="robot-shop"}` returned 280 series, split per route (`http_route`), and every series I looked at had `k8s_container_name="istio-proxy"`, so Beyla is reading the Istio sidecar. It adds an `envoy` service that is not a shop service. The first two outputs here were far too long to read; later queries were limited to a few lines.

**Run 4 — When did the 5xx happen?** `increase(...[2m])` over the last hour, steps of 2 minutes, printing only values above 0.5:

```
cart
rabbitmq
web
   18:43:02 75.4
now: 18:45:02
```

The only burst is at 18:43, the minutes when the cart fault ran. There was none during the cluster start-up at about 18:25.

**What it means.**
- Use `istio_requests_total` with `reporter="destination"`; the service name is `destination_workload`. Beyla is noisier and repeats Istio.
- Use the share of failed requests (5xx out of all requests), and ignore services with very few requests; rabbitmq's single 503 would otherwise look like a failure.
- The cart fault also makes `web` return 503, so the 5xx alert fires for `web` too.
- No 5xx was seen outside the fault in the last hour. A clean 30-minute run is not proven; the verification run proves it.

## Finding 4 — Which service gives a usable "slow request" signal?

**Question.** Story #122 says the slow-request alert fires "only if latency goes over the tuned payment threshold". The earlier Keep try-out used `payment p95 > 1s` and noted it stayed firing 8 minutes after the fix (`keep-tryout-findings.md` line 75: "threshold may sit close to payment's normal p95 under loadgen"). Is payment the right service?

**Run 1 — Payment latency, last 50 minutes, load generator running** (Istio p95 in ms, Istio p50 in ms, requests per second, Beyla p95 in s; 5-minute steps):

```
### Istio payment p95 (ms)
   18:43=1581.78 18:48=4982.14
### Istio payment p50 (ms)
   18:43=620.24 18:48=952.83
### Istio payment requests/s
   18:43=0.17 18:48=0.48
### Beyla payment p95 (s)
   18:28=0.01 18:33=0.00 18:38=0.00 18:43=0.73 18:48=2.39
```

Beyla's near-zero values before 18:43 were almost no traffic, not a real "normal" (payment only gets about 0.5 requests a second). The cart had recovered (`cart-6cffbd788-gt272   2/2   Running   0   6m43s`). Payment p95 by minute after the cart fault was reverted at about 18:43, 2-minute windows:

```
### Istio payment p95 ms, 2m window
   41=1978.3 42=1525.0 43=1325.0 44=5166.7 45=5666.7 46=7125.0 47=6937.5 48=2350.0
### payment req/s, 2m window
   41=0.0 42=0.2 43=0.5 44=0.6 45=0.5 46=0.5 47=0.5 48=0.5
```

Payment is slow and noisy by itself (typical request about 0.6 to 1.0 s, p95 1.3 to 7 s) and was no worse during the cart fault than outside it.

**Run 2 — The database fault of story 008, shipping, ratings and payment** (`make aks-db-latency-start`, load generator running, Istio, destination side, 2-minute windows):

```
RESULT: fault not active
=== BASELINE before fault (18:51:47)
  shipping p50 ms: 13.3
  shipping p95 ms: 1037.5
  shipping req/s: 2.29
  ratings p50 ms: 41.3
  ratings p95 ms: 136.7
  ratings req/s: 1.54
  payment p50 ms: 725.6
  payment p95 ms: 1867.9
  payment req/s: 0.56
=== start
Installing the Rewriter plugin in mysql-0...
Adding the three rules and loading them...
Waiting up to 30s for the lookups to turn slow...
RESULT: fault active (shipping lookup 3.3s, ratings lookup 1.1s)
=== DURING fault (18:53:39)
  shipping p50 ms: 9.6
  shipping p95 ms: 4765.6
  shipping req/s: 1.41
  ratings p50 ms: 765.0
  ratings p95 ms: 1468.7
  ratings req/s: 1.1
  payment p50 ms: 645.8
  payment p95 ms: 983.3
  payment req/s: 0.35
=== revert
Disabling the rules...
Waiting up to 30s for the lookups to turn normal...
RESULT: fault removed (shipping lookup 1.2s, ratings lookup 0.3s)
make: *** [makefile:282: aks-db-latency-status] Error 1
```

**Failure, not explained.** The status command exited with `Error 1` right after the revert. My command printed only the last line, so the script's own message was cut off. A re-run a minute later printed `RESULT: fault not active`. The cause was not investigated.

**What it means.**
- Ratings is the clearest signal: p95 about 0.14 s normally, about 1.5 s during the fault. Shipping p95 rose from about 1.0 s to about 4.8 s; its normal p95 is already about 1 s because of a slow tail (its typical request is 13 ms). Payment did not react to the database fault (p95 went from 1.9 s down to 1.0 s).
- These are single samples of 1 to 2 requests a second each; they are not a proven normal range.
- **Decision (developer, 2026-10-27): the slow-request alert covers shipping and ratings, not payment.** This departs from story #122, which names payment. The spec states the departure so that `/speckit-analyze` and `/speckit-converge` do not flag it as a gap. Thresholds are tuned in the plan from a longer quiet run, with the 008 spec's own values (shipping over 2 s, ratings over 0.5 s) as the starting point.
