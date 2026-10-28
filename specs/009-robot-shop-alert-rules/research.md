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

**Failure, not explained.** The status command exited with `Error 1` right after the revert. My command printed only the last line, so the script's own message was cut off. A re-run a minute later printed `RESULT: fault not active`. The cause was not investigated at the time.

**Failure, explained later (2026-10-27, same session).** The same `Error 1` came back when the status command was run again with the fault off. Five more runs, printing the full output on failure:

```
run 1 rc=0
run 2 rc=0
run 3 rc=0
run 4 rc=0
run 5 rc=2
bash infra/azure/scenario-03/db-latency.sh status
RESULT: fault not active, but the lookups are slow for another reason: shipping 2.6s, ratings 0.3s
make: *** [makefile:282: aks-db-latency-status] Error 1
```

With no fault active, one shipping test request took 2.6 seconds, above the 2-second limit the 008 spec uses for "slow". The status command treats that as a failure. So shipping is occasionally slower than 2 seconds on a healthy shop (consistent with its normal p95 of about 1 s above). A shipping slow-request limit of 2 seconds sits inside its normal slow tail; the plan has to choose the limit and the wait time with that in mind.

**What it means.**
- Ratings is the clearest signal: p95 about 0.14 s normally, about 1.5 s during the fault. Shipping p95 rose from about 1.0 s to about 4.8 s; its normal p95 is already about 1 s because of a slow tail (its typical request is 13 ms). Payment did not react to the database fault (p95 went from 1.9 s down to 1.0 s).
- These are single samples of 1 to 2 requests a second each; they are not a proven normal range.
- **Decision (developer, 2026-10-27): the slow-request alert covers shipping and ratings, not payment.** This departs from story #122, which names payment. The spec states the departure so that `/speckit-analyze` and `/speckit-converge` do not flag it as a gap. Thresholds are tuned in the plan from a longer quiet run, with the 008 spec's own values (shipping over 2 s, ratings over 0.5 s) as the starting point.

## Finding 5 — What does a healthy shop look like over 30 minutes?

**Question.** With the load generator running and no fault, what do shipping latency, ratings latency and the share of server errors do over 30 minutes? Which limits would stay quiet?

**Setup (2026-10-28).** The cluster was started with `az aks start` (stopped since the day before). Every pod in `robot-shop` and `monitoring` showed Ready at 13:06:25. The load generator was already running (`deployment.apps/load unchanged`). A sampler script (kept outside the repo) read Prometheus once a minute from 13:07 to 13:37. It used 5-minute windows, destination side, `namespace="robot-shop"`, and printed the shipping and ratings p95 in milliseconds, their requests per second, restarts in the last 30 minutes, unavailable replicas, and the highest 5xx share of any service. At the end it printed whole-run figures.

**Output, pasted unchanged from the sampler file:**

```
start 13:07:03
{"t": "13:07:03", "ship_p95_ms_5m": "none", "rate_p95_ms_5m": "none", "ship_rps": "none", "rate_rps": "none", "restarts_30m": "0.000", "unavail": "2.000", "share5xx_max": "0.4090"}
{"t": "13:08:03", "ship_p95_ms_5m": "none", "rate_p95_ms_5m": "none", "ship_rps": "none", "rate_rps": "none", "restarts_30m": "0.000", "unavail": "2.000", "share5xx_max": "0.4020"}
{"t": "13:09:03", "ship_p95_ms_5m": "none", "rate_p95_ms_5m": "none", "ship_rps": "none", "rate_rps": "none", "restarts_30m": "0.000", "unavail": "2.000", "share5xx_max": "0.3959"}
{"t": "13:10:04", "ship_p95_ms_5m": "none", "rate_p95_ms_5m": "none", "ship_rps": "none", "rate_rps": "none", "restarts_30m": "0.000", "unavail": "2.000", "share5xx_max": "0.4034"}
{"t": "13:11:04", "ship_p95_ms_5m": "none", "rate_p95_ms_5m": "none", "ship_rps": "none", "rate_rps": "none", "restarts_30m": "0.000", "unavail": "2.000", "share5xx_max": "0.4025"}
{"t": "13:12:04", "ship_p95_ms_5m": "none", "rate_p95_ms_5m": "none", "ship_rps": "none", "rate_rps": "none", "restarts_30m": "0.000", "unavail": "2.000", "share5xx_max": "0.4015"}
{"t": "13:13:05", "ship_p95_ms_5m": "2200.000", "rate_p95_ms_5m": "94.126", "ship_rps": "0.229", "rate_rps": "0.141", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.2822"}
{"t": "13:14:05", "ship_p95_ms_5m": "1557.143", "rate_p95_ms_5m": "99.921", "ship_rps": "0.601", "rate_rps": "0.376", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.1592"}
{"t": "13:15:05", "ship_p95_ms_5m": "3500.000", "rate_p95_ms_5m": "150.084", "ship_rps": "0.943", "rate_rps": "0.600", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0810"}
{"t": "13:16:06", "ship_p95_ms_5m": "3953.125", "rate_p95_ms_5m": "181.881", "ship_rps": "1.248", "rate_rps": "0.804", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0340"}
{"t": "13:17:06", "ship_p95_ms_5m": "3166.667", "rate_p95_ms_5m": "168.463", "ship_rps": "1.584", "rate_rps": "0.977", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0009"}
{"t": "13:18:07", "ship_p95_ms_5m": "3772.727", "rate_p95_ms_5m": "184.265", "ship_rps": "1.723", "rate_rps": "1.098", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:19:07", "ship_p95_ms_5m": "3261.364", "rate_p95_ms_5m": "163.900", "ship_rps": "1.716", "rate_rps": "1.067", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:20:07", "ship_p95_ms_5m": "2781.250", "rate_p95_ms_5m": "186.518", "ship_rps": "1.733", "rate_rps": "1.112", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:21:08", "ship_p95_ms_5m": "2261.364", "rate_p95_ms_5m": "150.714", "ship_rps": "1.782", "rate_rps": "1.168", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:22:08", "ship_p95_ms_5m": "2255.147", "rate_p95_ms_5m": "143.571", "ship_rps": "1.825", "rate_rps": "1.239", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:23:08", "ship_p95_ms_5m": "2027.273", "rate_p95_ms_5m": "99.470", "ship_rps": "1.860", "rate_rps": "1.196", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:24:09", "ship_p95_ms_5m": "1805.000", "rate_p95_ms_5m": "92.016", "ship_rps": "1.870", "rate_rps": "1.204", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:25:09", "ship_p95_ms_5m": "1589.286", "rate_p95_ms_5m": "94.025", "ship_rps": "1.968", "rate_rps": "1.270", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:26:09", "ship_p95_ms_5m": "1499.038", "rate_p95_ms_5m": "92.318", "ship_rps": "1.919", "rate_rps": "1.277", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:27:10", "ship_p95_ms_5m": "1562.500", "rate_p95_ms_5m": "88.750", "ship_rps": "1.909", "rate_rps": "1.204", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:28:10", "ship_p95_ms_5m": "1636.000", "rate_p95_ms_5m": "93.026", "ship_rps": "1.968", "rate_rps": "1.263", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:29:10", "ship_p95_ms_5m": "1709.821", "rate_p95_ms_5m": "92.206", "ship_rps": "1.972", "rate_rps": "1.246", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:30:11", "ship_p95_ms_5m": "1511.957", "rate_p95_ms_5m": "87.436", "ship_rps": "1.723", "rate_rps": "1.119", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:31:11", "ship_p95_ms_5m": "1797.727", "rate_p95_ms_5m": "123.750", "ship_rps": "1.768", "rate_rps": "1.130", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:32:12", "ship_p95_ms_5m": "1639.130", "rate_p95_ms_5m": "128.846", "ship_rps": "1.811", "rate_rps": "1.168", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:33:12", "ship_p95_ms_5m": "1759.783", "rate_p95_ms_5m": "119.091", "ship_rps": "1.698", "rate_rps": "1.102", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:34:12", "ship_p95_ms_5m": "2191.346", "rate_p95_ms_5m": "183.289", "ship_rps": "1.709", "rate_rps": "1.102", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:35:13", "ship_p95_ms_5m": "2329.310", "rate_p95_ms_5m": "152.059", "ship_rps": "1.716", "rate_rps": "1.140", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
{"t": "13:36:13", "ship_p95_ms_5m": "2063.636", "rate_p95_ms_5m": "108.382", "ship_rps": "1.814", "rate_rps": "1.196", "restarts_30m": "0.000", "unavail": "0.000", "share5xx_max": "0.0000"}
end 13:37:13
whole-run shipping p0.5 ms: 23.006
whole-run shipping p0.95 ms: 2099.315
whole-run shipping p0.99 ms: 8527.778
whole-run ratings p0.5 ms: 27.759
whole-run ratings p0.95 ms: 118.618
whole-run ratings p0.99 ms: 240.665
whole-run payment p0.5 ms: 723.504
whole-run payment p0.95 ms: 2237.172
whole-run payment p0.99 ms: 3725.009
whole-run 5xx share catalogue: 0.00000
whole-run 5xx share mysql: 0.00000
whole-run 5xx share rabbitmq: 0.00000
whole-run 5xx share web: 0.02532
whole-run 5xx counts: {"web": 336.8067226890756}
whole-run request counts: {"cart": 4016, "catalogue": 4412, "payment": 669, "ratings": 1734, "shipping": 2678, "user": 2344, "mysql": 61, "rabbitmq": 61, "web": 13302}
```

**The first 6 minutes were not quiet.** Until 13:12 the sampler printed no latency data (`none`), 2 unavailable replicas, and a highest 5xx share of about 0.40. The 5xx share fell to 0.0000 at 13:18 and stayed there. The sampler did not record which service the early errors or the 2 unavailable replicas belonged to, and I do not know why `kubectl` showed every pod Ready while this metric showed 2 unavailable replicas. A late metrics scrape after the start is a guess and was not checked. The whole-run web figure (337 errors out of 13,302 requests, share 0.02532) comes from this start-up period, so it is misleading as a measure of a healthy shop.

**What it means.**
- Ratings: the 5-minute p95 stayed between 87 and 187 ms. Whole run: p50 28 ms, p95 119 ms, p99 241 ms. A limit of 0.5 s is safe. Finding 4 showed about 1.5 s during the fault.
- Shipping: the 5-minute p95 was above 2 s in 13 of the 24 samples from 13:13 on, and in 6 of the 16 samples from 13:21 on. Whole run: p50 23 ms, p95 2,099 ms, p99 8,528 ms. The 2-second limit from story 008 would fire on a healthy shop. Finding 4's fault sample showed a shipping p95 of about 4.8 s while its p50 hardly moved (9.6 ms), so a plain p95 limit separates the fault from normal poorly. The choice is left to the plan.
- Server errors: after start-up the highest 5xx share was 0.0000 in every sample from 13:18, with 0 restarts and 0 unavailable replicas from 13:13. The first minutes after a cluster start are not quiet (spec EC-002 already says so).
- Payment, whole run: p50 724 ms, p95 2,237 ms, p99 3,725 ms. This is the same shape as Finding 4 and supports dropping payment.
- This is one 30-minute run on one day. It is not proof of a normal range.

**Correction (2026-10-28, found later the same day while replaying the rules against Prometheus for the plan).** The part above that says the cause was not found, and that every pod showed Ready at 13:06:25, was wrong. Replaying `kube_deployment_status_replicas_unavailable` by deployment showed the 2 unavailable replicas were `catalogue` (unavailable until 13:12:00) and `payment` (until 13:12:30). `cart`, `dispatch`, `web`, `ratings` and `shipping` had cleared by 13:06:30. The current catalogue and payment pods were created at 13:12:03 and became Ready at 13:12:12 and 13:12:28 (`kubectl get pod -o jsonpath`, converted from UTC to IST). My 13:06:25 pod listing printed 10 pods and had no catalogue or payment pod, and my readiness check only counted the pods that were listed, so two shop services had no running pod and I called the shop ready. Why those two pods did not exist until 13:12:03 is not known. `web` depends on them and returned 5xx (a share above 5% over 5 minutes until 13:15:45). So the shop was fully up at about 13:12:30, not 13:06:25. The steady figures from 13:18 on are not affected. What it means: the spec's wording "counts from the moment every shop service is ready" (EC-002) is correct, and the readiness check must look at every deployment and stateful set, not at a pod list.

## Finding 6 — Does a normal redeploy of a shop service stay quiet?

**Question.** When a shop service is replaced on purpose, do the restart, unavailable-replica or server-error conditions show up? (Spec EC-007.)

**Failures first.** The first attempt (13:42 to 13:53, 2026-10-28) restarted nothing. Both restart commands failed:

```
(eval):3: command not found: kubectl --context sre-stack-452138 -n robot-shop
```

zsh does not split a variable that holds a command into words. The flat output of that run (everything available, no errors) is not evidence about redeploys and is not used. A second attempt failed at once:

```
(eval):1: defining function based on alias `k'
parse error near `()'
```

`k` is an alias in the developer's shell. Nothing ran. The third attempt used a bash script file (kept outside the repo) and worked. Both pod names changed (`before: cart-6cffbd788-m5nkr`, `after: cart-66484b4799-w5rjs`, and the same for shipping), so the restarts really happened.

**Run.** A sampler read Prometheus every 15 seconds (destination side, `namespace="robot-shop"`, 2-minute windows). The script restarted `cart` at 13:55:02 and `shipping` at 13:58:12 with `kubectl rollout restart`, with the load generator running. Both deployments have 1 replica and the default rolling update (25% unavailable, 25% surge); cart has no readiness probe.

**Output, pasted unchanged. First the script's event log:**

```
before: cart-6cffbd788-m5nkr 2/2 Running 17h
before: shipping-5897dc57b5-rq4wq 2/2 Running 17h
13:55:02 restart cart
deployment.apps/cart restarted
Waiting for deployment "cart" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "cart" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "cart" rollout to finish: 1 old replicas are pending termination...
deployment "cart" successfully rolled out
13:55:12 cart rollout finished
13:58:12 restart shipping
deployment.apps/shipping restarted
Waiting for deployment "shipping" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "shipping" rollout to finish: 1 old replicas are pending termination...
deployment "shipping" successfully rolled out
13:59:17 shipping rollout finished
after: cart-66484b4799-w5rjs 2/2 Running 10m
after: shipping-869c77dccc-g4vgt 2/2 Running 7m3s
```

**Then the sampler file:**

```
start 13:54:04
{"t": "13:54:04", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:54:19", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:54:34", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:54:49", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:55:05", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:55:20", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.0035}}
{"t": "13:55:35", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.0038}}
{"t": "13:55:50", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.0041}}
{"t": "13:56:06", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.0039}}
{"t": "13:56:21", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.0036}}
{"t": "13:56:36", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.004}}
{"t": "13:56:51", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {"web": 3.4286}, "5xx_share_2m>0": {"web": 0.0039}}
{"t": "13:57:07", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:57:22", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:57:37", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:57:52", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:58:08", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:58:23", "unavailable>0": {"shipping": 1.0}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:58:38", "unavailable>0": {"shipping": 1.0}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:58:53", "unavailable>0": {"shipping": 1.0}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:59:09", "unavailable>0": {"shipping": 1.0}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:59:24", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:59:39", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "13:59:55", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:00:10", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:00:25", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:00:40", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:00:56", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:01:11", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:01:26", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:01:41", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:01:57", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:02:12", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:02:27", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:02:42", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:02:58", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:03:13", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:03:28", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:03:43", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:03:59", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:04:14", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:04:29", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:04:44", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
{"t": "14:05:00", "unavailable>0": {}, "available": {"cart": 1.0, "shipping": 1.0}, "restarts_5m>0": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}}
end 14:05:15
```

**What it means.**
- Cart redeploy: the rollout took 10 s. Unavailable replicas never rose above 0. `web` returned about 3 server errors (a share of 0.35% to 0.41% in a 2-minute window), gone by 13:57:07. The restart counter did not move.
- Shipping redeploy: the rollout took 65 s. Unavailable replicas showed 1 in four samples (13:58:23 to 13:59:09) and was 0 again at 13:59:24, so it lasted between about 46 and 76 s. The available count stayed at 1.0 the whole time: the old pod kept serving while the new one started. No server errors were seen. The restart counter did not move.
- A restart condition based on how much the restart counter rises does not fire on a redeploy, because new pods start at 0.
- A condition based on unavailable replicas fires during a normal rollout, although a working copy exists. It needs a wait of more than about 80 s, or it should compare the available count to the wanted count. The plan decides which.
- About 3 failed requests out of web's traffic is far below any share limit worth setting, but it is only quiet if the rule ignores services with very few requests.
- Only cart and shipping were tested, one run each, with 1 replica each. Slower services such as the databases were not tested.

## Finding 7 — Does the slow-database fault raise the other alerts' conditions?

**Question.** While the slow-database fault (story 008) runs, do server errors, restarts, unavailable replicas or memory kills show up? (Spec SC-005.)

**Run (2026-10-28).** The load generator was running. A sampler (kept outside the repo) read Prometheus every 15 seconds from 14:09:00 (destination side, `namespace="robot-shop"`, 2-minute windows). A bash script (also outside the repo) waited 60 s, ran `make aks-db-latency-start`, held the fault for 5 minutes, ran `make aks-db-latency-revert`, and ran `make aks-db-latency-status` at the end. All three commands returned 0.

**Output, pasted unchanged. First the script's event log:**

```
14:09:59 fault start
bash infra/azure/scenario-03/db-latency.sh start
Installing the Rewriter plugin in mysql-0...
Adding the three rules and loading them...
Waiting up to 30s for the lookups to turn slow...
RESULT: fault active (shipping lookup 3.7s, ratings lookup 1.0s)
14:10:12 fault start command returned rc=0
14:15:12 fault revert
bash infra/azure/scenario-03/db-latency.sh revert
Disabling the rules...
Waiting up to 30s for the lookups to turn normal...
RESULT: fault removed (shipping lookup 1.1s, ratings lookup 0.2s)
14:15:32 fault revert command returned rc=0
14:19:05 final status
bash infra/azure/scenario-03/db-latency.sh status
RESULT: fault not active
14:19:09 final status returned rc=0
```

**Then the sampler file:**

```
start 14:09:00
{"t": "14:09:00", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 116, "shipping": 2157}}
{"t": "14:09:16", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 96, "shipping": 2044}}
{"t": "14:09:31", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 96, "shipping": 1525}}
{"t": "14:09:46", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 1562, "ratings": 149}}
{"t": "14:10:02", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 118, "shipping": 1742}}
{"t": "14:10:17", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 700, "shipping": 1867}}
{"t": "14:10:32", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 917, "shipping": 3786}}
{"t": "14:10:48", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 953, "shipping": 4654}}
{"t": "14:11:03", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 965, "shipping": 4724}}
{"t": "14:11:18", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 4784, "ratings": 973}}
{"t": "14:11:33", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 4958, "ratings": 978}}
{"t": "14:11:49", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 983, "shipping": 4898}}
{"t": "14:12:04", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 4804, "ratings": 979}}
{"t": "14:12:19", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 975, "shipping": 4724}}
{"t": "14:12:35", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 4663, "ratings": 975}}
{"t": "14:12:50", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 975, "shipping": 4723}}
{"t": "14:13:05", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 4763, "ratings": 975}}
{"t": "14:13:21", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 975, "shipping": 4650}}
{"t": "14:13:36", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 975, "shipping": 4769}}
{"t": "14:13:59", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 975, "shipping": 4718}}
{"t": "14:14:14", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 975, "shipping": 4866}}
{"t": "14:14:29", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 980, "shipping": 4793}}
{"t": "14:14:44", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 985, "shipping": 4808}}
{"t": "14:15:00", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 990, "shipping": 4810}}
{"t": "14:15:15", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 991, "shipping": 4824}}
{"t": "14:15:30", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 989, "shipping": 4703}}
{"t": "14:15:46", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 982, "shipping": 4692}}
{"t": "14:16:01", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 976, "shipping": 4406}}
{"t": "14:16:16", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 953, "shipping": 4288}}
{"t": "14:16:32", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 909, "shipping": 4017}}
{"t": "14:16:47", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 817, "shipping": 3562}}
{"t": "14:17:02", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 325, "shipping": 3089}}
{"t": "14:17:17", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 96, "shipping": 1928}}
{"t": "14:17:33", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 1412, "ratings": 86}}
{"t": "14:17:48", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 105, "shipping": 1840}}
{"t": "14:18:03", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 168, "shipping": 2390}}
{"t": "14:18:19", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 158, "shipping": 2312}}
{"t": "14:18:34", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"shipping": 3825, "ratings": 212}}
{"t": "14:18:49", "unavailable>0": {}, "restarts_5m>0": {}, "oomkilled": {}, "5xx_2m>0": {}, "5xx_share_2m>0": {}, "p95_ms_2m": {"ratings": 212, "shipping": 3562}}
end 14:19:05
```

**Revert check.** The revert command reported `fault removed (shipping lookup 1.1s, ratings lookup 0.2s)` and the final status reported `fault not active`. Ratings p95 fell to 86 to 212 ms after the revert. No separate manual query against MySQL was run.

**Shipping went back up with the fault off.** From 14:18:03 to 14:18:49 the shipping p95 was 2,390, 2,312, 3,825 and 3,562 ms while the status check said no fault. This is the healthy shop's slow tail (Finding 5).

**What it means.**
- SC-005 holds for this run: during the fault there were no server errors, no restarts, no unavailable replicas and no memory-killed container in any sample. The slow-request alerts are the only conditions this fault should raise.
- Ratings: a limit of 0.5 s separates cleanly. The healthy 2-minute p95 was at most 212 ms in this run; during the fault it was 917 to 991 ms (700 ms in the first sample after the start). Finding 4 saw about 1.5 s, so the size of the effect varies between runs.
- Shipping: separation is thin. The healthy 2-minute p95 reached 3.8 s with no fault; the fault held at about 4.4 to 5.0 s. A plain p95 limit would need to sit near 4 to 4.5 s, with little room on either side. Together with Finding 5, shipping needs a careful choice in the plan; none is made here.
- Timing: ratings crossed 0.5 s within about 5 s of the fault starting. It was back under 0.5 s (325 ms) at 14:17:02, about 1 minute 50 seconds after the revert began, because the window is 2 minutes long.
- This is one run, and 2-minute windows are noisy at about 1 to 2 requests per second.

## Finding 8 — How big are the cart-fault numbers, and do the candidate rules fire in time and clear?

**Question.** The plan has to choose the server-error limit and the wait times from measured behaviour (FR-012). The cart-fault numbers from 2026-10-27 were no longer available: Prometheus on this cluster has no persistent storage (the `prometheus` object has no `storage` setting, and the only PVCs are Loki's and the Grafana database's), so its history starts at about 13:10 on 2026-10-28. How big are the numbers during the cart fault, and would the candidate rules fire in time and clear?

**Run (2026-10-28).** The load generator was running. A bash script (kept outside the repo) waited 2 minutes, ran `make aks-cart-oom-start`, held the fault 8 minutes, ran `make aks-cart-oom-revert`, waited 12 minutes, and ran `make aks-cart-oom-status`. The numbers were then read back from Prometheus with range queries. The six candidate rules were kept in a scratch file outside the repo; `promtool check rules` on it printed `SUCCESS: 6 rules found`. They were replayed over everything Prometheus holds from 13:18 to 14:56: a "fires" time means the condition stayed true for the whole wait before firing, simulated at 15-second steps; the rules are evaluated every 30 s (`evaluation_interval: 30s` from the Prometheus config).

**Output, pasted unchanged. First the script's event log:**

```
14:32:37 baseline begins
14:34:37 fault start
bash infra/azure/scenario-02/cart-oom-kill.sh start
Lowering the cart memory allowance to 24Mi (cart container only)...
deployment.apps/cart resource requirements updated
deployment.apps/cart annotated
Waiting up to 60s for the cluster to kill the cart container for running out of memory...
RESULT: fault active (cart container was killed for running out of memory within 60s)
14:34:47 fault start command returned rc=0
14:42:47 fault revert
bash infra/azure/scenario-02/cart-oom-kill.sh revert
Restoring the cart memory allowance the shop is installed with (requests 50Mi, limits 100Mi)...
deployment.apps/cart resource requirements updated
deployment.apps/cart annotated
Waiting up to 60s for cart to run cleanly...
RESULT: fault reverted (cart runs at the allowance the shop is installed with, no further out-of-memory kills)
14:42:56 fault revert command returned rc=0
14:54:56 final status
bash infra/azure/scenario-02/cart-oom-kill.sh status
RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)
14:54:58 final status returned rc=0
```

**Then the numbers and the replays (one file, four parts: A the cart-fault numbers, B the six rules replayed, C the restarting rule with and without a pod-exists condition, D the slow-request signals replayed from the Finding 5 and Finding 7 windows):**

```
### A. Cart fault numbers from Prometheus (minute of the hour, 14:xx). Fault 14:34:37 -> revert 14:42:47
-- cart restart counter, one series per pod, once a minute
uid=24990092-52c3-4f33-91f6-0a83d7de6beb 44=0 45=0 46=0 47=0 48=0 49=0 50=0 51=0 52=0 53=0 54=0 55=0
uid=290c0c3b-3b44-4120-98c4-914cefe8a9e0 32=0 33=0 34=0 35=0
uid=0d3a03db-3116-45a9-a3a0-b51d7f571fa3 35=1 36=3 37=4 38=4 39=5 40=5 41=6 42=6 43=6
5xx share 5m             web   32=0.000 33=0.000 34=0.000 35=0.000 36=0.040 37=0.089 38=0.139 39=0.195 40=0.239 41=0.237 42=0.235 43=0.236 44=0.178 45=0.126 46=0.080 47=0.033 48=0.000 49=0.000 50=0.000 51=0.000 52=0.000 53=0.000 54=0.000 55=0.000
5xx share 2m             web   32=0.000 33=0.000 34=0.000 35=0.000 36=0.120 37=0.241 38=0.239 39=0.237 40=0.237 41=0.232 42=0.234 43=0.237 44=0.095 45=0.000 46=0.000 47=0.000 48=0.000 49=0.000 50=0.000 51=0.000 52=0.000 53=0.000 54=0.000 55=0.000
requests per 5m          web   32=2603 33=2655 34=2528 35=2656 36=2506 37=2490 38=2384 39=2247 40=2140 41=2052 42=1933 43=2016 44=2122 45=2304 46=2559 47=2511 48=2586 49=2456 50=2558 51=2505 52=2516 53=2535 54=2574 55=2428
5xx count per 5m         web   32=0 33=0 34=0 35=0 36=101 37=221 38=331 39=438 40=511 41=486 42=454 43=476 44=377 45=290 46=205 47=82 48=0 49=0 50=0 51=0 52=0 53=0 54=0 55=0
5xx share 5m             cart  32=0.000 33=0.000 34=0.000 35=0.000 36=0.012 37=0.027 38=0.039 39=0.113 40=1.000 41=1.000 42=1.000 43=1.000 44=0.005 45=0.003 46=0.000 47=0.000 48=0.000 49=0.000 50=0.000 51=0.000 52=0.000 53=0.000 54=0.000 55=0.000
5xx share 2m             cart  32=0.000 33=0.000 34=0.000 35=0.000 36=0.049 37=1.000 38=1.000 39=1.000 41=1.000 42=1.000 44=0.000 45=0.000 46=0.000 47=0.000 48=0.000 49=0.000 50=0.000 51=0.000 52=0.000 53=0.000 54=0.000 55=0.000
requests per 5m          cart  32=849 33=858 34=817 35=846 36=664 37=522 38=344 39=171 40=18 41=13 42=7 43=1 44=193 45=368 46=558 47=707 48=849 49=811 50=804 51=821 52=823 53=808 54=826 55=774
5xx count per 5m         cart  32=0 33=0 34=0 35=0 36=7 37=13 38=13 39=19 40=18 41=13 42=7 43=1 44=1 45=1 46=0 47=0 48=0 49=0 50=0 51=0 52=0 53=0 54=0 55=0

### B. The six candidate rules replayed over 13:18-14:56 (wait before firing as in the rule)
events (IST): redeploys cart 13:55:02 shipping 13:58:12 | db fault 14:09:59-14:15:12 | cart fault 14:34:37-14:42:47
## RobotShopContainerOOMKilled, wait 1m
   series namespace=robot-shop,service=cart | fires 14:36:30
     true: 14:35:30-14:43:15
## RobotShopContainerRestarting, wait 1m
   series namespace=robot-shop,service=cart | fires 14:36:30
     true: 14:35:30-14:50:15
## RobotShopReplicasUnavailable, wait 2m
   series namespace=robot-shop,service=cart | fires 14:37:30
     true: 14:35:30-14:43:15
   series namespace=robot-shop,service=shipping | fires NO
     true: 13:58:30-13:59:15
## RobotShopHTTPErrors, wait 2m
   series destination_workload=cart,namespace=robot-shop,service=cart | fires NO
     true: 14:38:15-14:39:30
   series destination_workload=web,namespace=robot-shop,service=web | fires 14:38:15
     true: 14:36:15-14:46:45
## RobotShopShippingSlowRequests, wait 2m
   series namespace=robot-shop | fires 14:13:00
     true: 14:11:00-14:16:00
## RobotShopRatingsSlowRequests, wait 2m
   series namespace=robot-shop | fires 14:12:30
     true: 14:10:30-14:16:45

### C. Restarting rule: range window only, and with 'the pod still exists' added
range window only:
  restarting, wait 1m                namespace=robot-shop,service=cart        fires=14:36:30  true=14:35:30-14:50:15
with the pod still exists:
  restarting, wait 1m                namespace=robot-shop,service=cart        fires=14:36:30  true=14:35:30-14:43:15

### D. Slow-request signals, replayed from the Finding 5 and Finding 7 windows (minimum / median / maximum of the share of requests slower than the limit, 2-minute and 5-minute windows)
== healthy 13:20-13:37
  shipping >2.5s [2m]                                         n=35 min=0.005155 med=0.02756 max=0.06436
  shipping >5s   [2m]                                         n=35 min=0 med=0.0119 max=0.03723
  ratings  >0.5s [2m]                                         n=35 min=0 med=0 max=0.007752
  shipping >2.5s [5m]                                         n=35 min=0.016 med=0.02874 max=0.05383
  shipping >5s   [5m]                                         n=35 min=0.003711 med=0.01341 max=0.02899
  ratings  >0.5s [5m]                                         n=35 min=0 med=0 max=0.003155
== db fault 14:10:30-14:15:10
  shipping >2.5s [2m]                                         n=10 min=0.07143 med=0.232 max=0.2416
  shipping >5s   [2m]                                         n=10 min=0.02151 med=0.03371 max=0.04734
  ratings  >0.5s [2m]                                         n=10 min=0.2091 med=1 max=1
  shipping >2.5s [5m]                                         n=10 min=0.04407 med=0.1509 max=0.2383
  shipping >5s   [5m]                                         n=10 min=0.01186 med=0.02414 max=0.03486
  ratings  >0.5s [5m]                                         n=10 min=0.06183 med=0.5957 max=1
== after revert 14:18-14:19:30 (5m windows still hold fault data)
  shipping >2.5s [2m]                                         n=4 min=0.04566 med=0.06977 max=0.07389
  shipping >5s   [2m]                                         n=4 min=0.02283 med=0.03965 max=0.04651
  ratings  >0.5s [2m]                                         n=4 min=0 med=0 max=0
  shipping >2.5s [5m]                                         n=4 min=0.0674 med=0.1035 max=0.112
  shipping >5s   [5m]                                         n=4 min=0.02444 med=0.0255 max=0.03125
  ratings  >0.5s [5m]                                         n=4 min=0.07781 med=0.264 max=0.3524
```

**What it means.**
- SC-001: all four cart-fault alerts fire within 5 minutes of the fault starting: out of memory 1m53s, restarting 1m53s, no ready copy 2m53s, server errors 3m38s, which leaves 1m22s to spare on the slowest. Nothing came back during the 13 minutes after the revert.
- Server-error limit: more than 5% of a service's requests answered with a 5xx over 5 minutes, with at least 30 requests in that window and a 2-minute wait. It stayed quiet on every healthy and redeploy window (the highest share seen was about 0.4%, Finding 6). `web` reached about 24% during the fault, nearly five times the limit. A higher limit would only fire later.
- The server-error alert fires for `web` only. Cart's own share is 100% from 14:40 to 14:43, but only 18, 13, 7 and 1 requests per 5 minutes reached a dead cart, so the "few requests" rule ignores it (EC-005). The spec's story says "the shop's website returning server errors", which is `web`. The earlier note that the alert "shows for `cart` and for `web`" came from the Finding 3 counts, not from an alert result.
- The restarting alert stayed on for 7m19s after the revert (until 14:50:15). The cause: `increase(...[10m])` keeps returning a value for a replaced pod until its last sample leaves the 10-minute window. Requiring the pod to still exist (part C) makes it fire at the same time and clear at 14:43:15, 28 seconds after the revert. The out-of-memory and no-ready-copy alerts read the pod's current state and cleared at 14:43:15 too.
- Slow-request signals (part D). Shipping: the share of requests slower than 2.5 s, over 2 minutes, was 0.5% to 6.4% when healthy (13:20 to 13:37) and 4.6% to 7.4% after the revert, against 7% to 24% during the fault (about 23% once it settled). Over 5 seconds the two cannot be told apart (healthy up to 3.7%, fault up to 4.7%). Ratings: the share over 0.5 s was at most 0.8% when healthy and 100% during the fault once it settled. The replay of today's database fault fires the shipping alert at 14:13:00 and the ratings alert at 14:12:30 (limits of 15% and 10%, 2-minute window, 2-minute wait), clears them at 14:16:00 and 14:16:45, and never fires them on the quiet windows 13:18 to 13:55 and 14:19 to 14:30. Part D was computed after Findings 5 and 7 were approved, from the same recorded windows, with new queries.
- The shipping redeploy (13:58:30 to 13:59:15 unavailable) does not fire a 2-minute wait, as Finding 6 predicted.
- The stateful-set branch of the no-ready-copy rule (mysql and redis) could not be run live without stopping the database. It was checked only with a local `promtool test rules` unit test on made-up numbers (not in the repo), which passed.
- This is one cart-fault run on one day. The 24% depends on this shop's traffic mix.

## Finding 9 — Do all six alerts fire when both faults run together?

**Question.** Check 9 (EC-006) expected all six alerts to fire within 5 minutes of starting the cart memory fault and the slow-database fault together.

**What happened** (run started 18:38:06, both faults active by 18:38:25; `evidence/both-faults-result.txt` and `evidence/both-faults-poll.txt`):
- `RobotShopContainerOOMKilled` and `RobotShopContainerRestarting` (cart): firing at 18:40:26, 2m20s after the start.
- `RobotShopReplicasUnavailable` (cart): firing at 18:40:56, 2m50s. It dropped back to pending once before 18:43:58.
- `RobotShopRatingsSlowRequests` (ratings): firing at 18:41:26, 3m20s after the start.
- `RobotShopHTTPErrors` (web): firing at 18:42:26, 4m20s after the start.
- `RobotShopShippingSlowRequests`: never went pending or firing.

**Why shipping stayed quiet.** Shipping only receives requests through cart. With cart down (0/1 ready), the request count for shipping over 2 minutes was 0 at 18:44:35 (`sum(increase(istio_request_duration_milliseconds_count{destination_workload="shipping"}[2m]))`). The share of slow requests was NaN, because it divides by zero. The shipping rule needs at least 30 requests in its 2-minute window (the minimum-request guard, EC-005), so with 0 requests it cannot fire. Ratings still received about 162 requests in the same 2 minutes, because the ratings lookup does not go through cart.

**Shipping alone still works.** In the slow-database run alone (start 17:37:56), shipping fired at 17:41:27, 3m31s after the start (Finding 8).

**Decision.** The developer accepted five of six for the both-faults check on 2026-10-28. The check and the plan's departure list are updated to match (`plan.md` "Departures and follow-ups", `quickstart.md` check 9, `tasks.md` T027). The rule itself is unchanged.

**Limit of this finding.** This is one run of the both-faults case. The shipping result depends on the cart being down. If the cart fault ever stops killing the cart container, shipping traffic would return and this could need a fresh look.
