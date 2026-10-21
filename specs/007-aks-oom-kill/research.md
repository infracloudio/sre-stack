# Phase 0 Research — Out-of-Memory Kill of the Cart Pod on Azure

Live run on AKS cluster `sre-stack-452138` (southindia, Kubernetes `1.34.11`),
subscription `Pune - Sandbox (TPM)`, on 2026-10-21. The cluster was stopped when
the story started and was started on the developer's go-ahead
(`az aks start -g rijo-john-improving-com-aks-452138 -n sre-stack-452138`).

Shop state at the start: `kubectl get pods -n robot-shop` showed every service
`2/2 Running` except `shipping` at `1/2` (a known fresh-setup condition named in
story 006's plan), and the load generator had not been started.

Each finding was proposed to the developer on its own, with the output below
pasted from the terminal, and approved before the next was run.

---

## Finding 1 — Cart's real memory use, and the allowance that kills it

**The question.** Register 1 in Technical Context: cart runs at `100Mi`. What
does it actually use, and how far down must the allowance go to kill it within
60 s (SC-001) and three times within 3 minutes (SC-002) without the shop being
dead before the demo starts?

**Step 1 — per-container use with the shop idle, allowance still at `100Mi`.**

```
$ kubectl top pod -n robot-shop --containers
POD                          NAME             CPU(cores)   MEMORY(bytes)   
cart-6cffbd788-pzd2j         cart             1m           31Mi            
cart-6cffbd788-pzd2j         istio-proxy      2Mi          54Mi            
```

The `100Mi` allowance applies to the `cart` container only; the `istio-proxy`
sidecar is injected at pod creation and keeps its own (unset) limit. So the
number that matters is `31Mi`, not the pod's `85Mi` total.

**Step 2 — start the load generator** (developer's go-ahead: "do it as per your
discretion"). `infra/azure/load-gen/load.yaml` sends traffic to
`http://web.robot-shop.svc.cluster.local:8080` with `NUM_CLIENTS=10`.

```
$ kubectl apply -f infra/azure/load-gen/load.yaml
deployment.apps/load configured
$ kubectl get pods -n loadgen
NAME                   READY   STATUS    RESTARTS   AGE
load-cb796c98b-kbqfn   1/1     Running   0          20s
```

**Step 3 — cart's use under traffic, four samples 20 s apart.**

```
$ for i in 1 2 3 4; do kubectl top pod -n robot-shop --containers | grep -E "^\S+ +cart "; sleep 20; done
cart-6cffbd788-pzd2j         cart             1m           31Mi            
cart-6cffbd788-pzd2j         cart             1m           31Mi            
cart-6cffbd788-pzd2j         cart             1m           31Mi            
cart-6cffbd788-pzd2j         cart             3m           33Mi            
```

Cart's own use is flat at `31–33Mi` against a `100Mi` allowance, so the
allowance is roughly three times what the service touches.

**Step 4 — the kill, at `24Mi`.** The request had to come down with the limit:
`50Mi` requested against a `24Mi` limit is rejected by the API server, so the
command sets both.

```
$ kubectl set resources deployment/cart -n robot-shop --requests=memory=8Mi --limits=memory=24Mi
deployment.apps/cart resource requirements updated
```

Watched every 6 s (`restarts` is the `cart` container's own count):

```
16:52:31 cart-6cffbd788-pzd2j restarts=0 state={"running":...}
16:52:31 cart-769b547b68-bzsb6 restarts=0 state={"waiting":{"reason":"PodInitializing"}} last=/
16:52:37 cart-769b547b68-bzsb6 restarts=0 state={"running":{"startedAt":"2026-10-21T11:22:36Z"}} last=/
16:52:43 cart-769b547b68-bzsb6 restarts=1 state={"waiting":{"message":"back-off 10s restarting failed container=cart pod=cart-769b547b68-bzsb6_robot-shop(1b00e155-297e-4069-87d3-cbc2eb2ee96b)","reason":"CrashLoopBackOff"}} last=OOMKilled/137
16:52:56 cart-769b547b68-bzsb6 restarts=2 state={"terminated":{"exitCode":137,"finishedAt":"2026-10-21T11:22:54Z","reason":"OOMKilled","startedAt":"2026-10-21T11:22:52Z"}} last=OOMKilled/137
16:53:08 cart-769b547b68-bzsb6 restarts=2 state={"waiting":{"message":"back-off 20s restarting failed container=cart ...","reason":"CrashLoopBackOff"}} last=OOMKilled/137
16:53:27 cart-769b547b68-bzsb6 restarts=3 state={"terminated":{"exitCode":137,"finishedAt":"2026-10-21T11:23:25Z","reason":"OOMKilled","startedAt":"2026-10-21T11:23:23Z"}} last=OOMKilled/137
16:53:40 cart-769b547b68-bzsb6 restarts=3 state={"waiting":{"message":"back-off 40s restarting failed container=cart ...","reason":"CrashLoopBackOff"}} last=OOMKilled/137
16:54:17 cart-769b547b68-bzsb6 restarts=4 state={"terminated":{"exitCode":137,"finishedAt":"2026-10-21T11:24:15Z","reason":"OOMKilled","startedAt":"2026-10-21T11:24:13Z"}} last=OOMKilled/137
16:54:30 cart-769b547b68-bzsb6 restarts=4 state={"waiting":{"message":"back-off 1m20s restarting failed container=cart ...","reason":"CrashLoopBackOff"}} last=OOMKilled/137
```

What that shows:

- First kill **15 s** after the change (`16:52:28` → `16:52:43`), inside
  SC-001's 60 s.
- `OOMKilled` with exit code `137`, which is the status the spec talks about,
  and the container is started again by the cluster every time.
- Third kill at `16:53:27`, **44 s** after the first, inside SC-002's 3 minutes.
- The wait between restarts grows `10s → 20s → 40s → 1m20s`, which is EC-007
  seen live: by four kills the counter is climbing in bigger steps.
- **Two cart pods existed for about 40 s.** The rollout put a new pod beside
  the old one, and the old one outlived the change while the new one was not
  yet ready (`cart-6cffbd788-pzd2j` still `restarts=0` at `16:52:31`). Anything
  that asks "is the fault on" has to tolerate more than one cart pod.

**Step 5 — revert, at `16:56:57`.**

```
$ kubectl set resources deployment/cart -n robot-shop --requests=cpu=100m,memory=50Mi --limits=cpu=200m,memory=100Mi
deployment.apps/cart resource requirements updated
$ kubectl get pods -n robot-shop -l service=cart
NAME                   READY   STATUS    RESTARTS   AGE
cart-6cffbd788-wlgzj   2/2     Running   0          109s
$ kubectl top pod -n robot-shop -l service=cart --containers
POD                    NAME          CPU(cores)   MEMORY(bytes)   
cart-6cffbd788-wlgzj   cart          9m           31Mi            
cart-6cffbd788-wlgzj   istio-proxy   6m           49Mi            
```

Revert is a rollout, not an in-place edit: the failing ReplicaSet is replaced,
the new pod starts its life at `restarts=0`, and cart is back to `31Mi`. The
count therefore *resets* rather than *flattens* — the guide must say so, or a
presenter will read "0" as "nothing happened".

**Answer.** `24Mi` (with `8Mi` requested) kills cart in 15 s and three times in
44 s, on a service that idles at `31–33Mi` against a `100Mi` allowance. Revert
restores `100Mi` / `50Mi` and a fresh pod at `31Mi`.

---

## Finding 2 — What is already visible, and what the new panel must show

**The question.** Register 2 in Technical Context: do the dashboards the Azure
monitoring setup installs already show an out-of-memory kill and a restart
count a presenter can point at?

**Negative half — checked against the live Grafana instance, not files.**
Port-forwarded to `http://localhost:13000`, read with the admin password from
`kubectl get secret prometheus-stack-grafana`:

```
total dashboards in Grafana: 31
=== scan each dashboard JSON for restart/OOM mentions ===
--- done (no HIT lines = no dashboard mentions them) ---
```

All 31 dashboards were downloaded through `/api/dashboards/uid/<uid>` — the
same JSON the UI renders — and scanned for `OOMKilled`, `restarts_total` and
`restart count`. Not one panel on any dashboard mentions them. This includes
the Application Dashboard used by story 006's guide, the RabbitMQ dashboard
built for the EKS memory-squeeze family (its closest panel is "Memory available
before publishers blocked"), and every chart-shipped Kubernetes dashboard.
The repo's own files agree: `grep -rn OOMKilled` over the tree hits no
dashboard YAML, and the live Pod dashboard `prometheus-stack-kube-prom-k8s-resources-pod`
offers CPU Usage, Memory Usage (WSS), network and I/O panels — no restarts.

Why this is new information rather than an EC note: story 006's fault made
requests fail, which the Application Dashboard shows as errors. An
out-of-memory kill makes no such panel change; the kill's own evidence lives
in the container status, which no dashboard here has ever tracked — on EKS or
Azure.

**Positive half — the panel queries work on the live cluster.** Fault re-started
at `17:15:24` with the Finding 1 change (`24Mi` / `8Mi` requested):

```
17:15:37 cart-769b547b68-mpchh:1 
17:15:49 cart-769b547b68-mpchh:2 
17:16:20 cart-769b547b68-mpchh:3 
17:17:04 cart-769b547b68-mpchh:4 
```

Query 1 (restart count), Query 2 (out-of-memory reason), both against
Prometheus at `prometheus-operated:9090`:

```
=== QUERY 1 raw values (fault on) ===
cart-769b547b68-mpchh = 4
=== QUERY 2 raw values (fault on) ===
cart-769b547b68-mpchh = 1
```

Re-start at `17:18:11` (the Finding 5 revert values, `100Mi` / `50Mi`),
observed 50 s later:

```
=== QUERY 1 raw values (fault off) ===
cart-6cffbd788-h8cxm = 0
=== QUERY 2 raw values (fault off) ===
no series
```

What a new panel must handle — all seen in this run:

1. **The reason signal is absent, not zero, on a healthy container.** After the
   revert there is `no series` for `OOMKilled`, because the fresh pod has
   nothing to report. A panel that expects a number must treat absent as `0`
   (Grafana query: `… or vector(0)`), or it will show "No data" where the
   guide needs "0 kills".
2. **During the rollout two cart pods exist** (Finding 1's surprise 2), and
   `sum by (pod)` correctly produces one series per pod, the healthy old pod at
   `0` and the new one climbing. The panel should sum across pods, or scope
   itself to the Deployment, so the presenter always sees one number.
3. The Application Dashboard runs on the `.data` datasource `{type:
   "prometheus", uid: "prometheus"}`, so the new panels need no new data
   source — the same instance Prometheus already plug into every panel there.

**The two queries as written into the dashboard** (story task T006, panels
"Cart restarts" and "Cart killed for running out of memory" in the new
"Restarts" row of the Application Dashboard):

```
sum(kube_pod_container_status_restarts_total{namespace="robot-shop",container="cart"}) or vector(0)
sum(kube_pod_container_status_last_terminated_reason{namespace="robot-shop",container="cart",reason="OOMKilled"}) or vector(0)
```

**Addendum 2026-10-21 (task T012): every pod, 5-minute window.** The two cart-only queries above were replaced so any pod shows. `kube_pod_container_status_last_terminated_reason` is a gauge that stays at 1 after a pod recovers ([Elastic](https://www.elastic.co/observability-labs/blog/promql-kubernetes-oomkilled-crashloopbackoff)), so the stat only counts a pod whose last kill was `OOMKilled` and that also restarted in the last 5 minutes. The kubelet backs off at most 5 minutes between restarts, so a pod that is still failing shows at least one restart in most 5-minute windows; one that has stopped clears within 5 minutes. The queries now in the dashboard:

```
sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total[5m])) > 0
count((max by (namespace, pod, container) (kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}) == 1) and on (namespace, pod, container) (sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total[5m])) > 0)) or vector(0)
```

The table's two queries are the per-container forms of these.

`or vector(0)` turns the absent series of point 1 into `0`; `sum` gives one
number while a rollout leaves two cart pods (point 2). The label filters in
these panels get their first run in the live evidence run (task T010).

**Answer.** No dashboard the setup installs can show this fault today, on EKS
or Azure. A panel added to an existing dashboard can show it with the two
queries above, against the datasource every shop panel already uses.

---

## Finding 3 — A shop redeploy clears the fault; a second revert changes nothing

**The question.** Register 3 in Technical Context: does `make setup-robot-shop`
during an active fault restore the chart's allowance and clear the fault, the
way EC-002 expects FR-008 to tolerate? And does the revert action stay safe to
run when nothing is wrong (FR-005, SC-008)?

**Step 1 — fault on.** At `17:29:34` the Finding 1 change was re-applied
(`24Mi` limit, `8Mi` requested) and confirmed:

```
NAME                    READY   STATUS      RESTARTS      AGE
cart-769b547b68-ljkl6   1/2     OOMKilled   3 (32s ago)   54s
NAME                    READY   STATUS             RESTARTS      AGE
cart-769b547b68-ljkl6   1/2     CrashLoopBackOff   3 (33s ago)   84s
```

**Step 2 — redeploy while the fault is on.** `make setup-robot-shop`
(`helm upgrade --install roboshop -n robot-shop ./app/robot-shop/helm/
--values ./infra/azure/chart-values/robot-shop.yaml --set stack_mode=aks ...`,
`makefile:296`), 2026-10-21 17:31:07 → 17:31:22, `REVISION: 4`. Thirty seconds
later:

```
=== cart deployment resources after redeploy ===
{"limits":{"cpu":"200m","memory":"100Mi"},"requests":{"cpu":"100m","memory":"50Mi"}}
=== pods ===
NAME                   READY   STATUS    RESTARTS   AGE
cart-6cffbd788-drc2c   2/2     Running   0          46s
```

So the Helm release owns the Deployment and re-applies the chart's allowance on
every `upgrade --install`. EC-002 is real behaviour, not a guess: the fault
does not survive a shop redeploy — FR-008's "including when the shop was
deployed again" case is this. Consequences for the design, all downstream of
the finding:

- Revert needs the allowance the shop is **installed with now**, which is
  stable at `100Mi` / `50Mi` for this chart and overlay, not something start
  recorded.
- Start must tolerate being re-run after a redeploy reset (EC-002: "running
  the start command again restores it").
- A status command that keys on the live allowance alone agrees with reality
  here: after a redeploy the lowered allowance is genuinely gone, so "fault
  not active" is the true answer, and start restores it.

**Step 3 — revert when nothing is wrong.** The Finding 5 values were
re-applied at `17:32:27` with the shop already healthy:

```
after30s:
revision=8
cart-6cffbd788-drc2c: 0
{"limits":{"cpu":"200m","memory":"100Mi"},"requests":{"cpu":"100m","memory":"50Mi"}}
```

Identical values do not roll a new ReplicaSet: revision stayed `8`, the pod
kept running, `requests` unchanged, and the command exits `0`. SC-008's
"revert twice ends the same as once" has a mechanism behind it, not just a
requirement: `kubectl set resources` with the same values is a no-op.

**Answer.** Redeploying the shop resets the allowance to the chart's values
and clears the fault; re-running the revert action against correct values
changes nothing, which is the safe second-run behaviour FR-005 and SC-008
assume.

---

## Finding 4 — The fault marker, and where revert reads the right allowance

**The question.** Register 4 in Technical Context: how does status tell "the
cart pod is being killed because of this fault" (FR-010) from cart being
killed for its own reasons (EC-006) or the allowance having been set by
someone else (EC-008)? And where does revert read "the allowance the shop is
installed with" (FR-008)? Story 006 had no marker to copy: its faults lived
inside the routing object itself, which none of this story's checks can read
the same way.

**Step 1 — an annotation on the cart Deployment survives a shop
redeploy.** A throwaway marker was written on a healthy Deployment and the
shop redeployed (the Finding 3 action, 12 s):

```
$ kubectl annotate deployment/cart -n robot-shop sre-stack/oom-fault-test=active
deployment.apps/cart annotated
$ make setup-robot-shop   # revision 4 -> 5
$ kubectl get deploy cart -n robot-shop -o jsonpath='{.metadata.annotations}'
{"deployment.kubernetes.io/revision":"8","meta.helm.sh/release-name":"roboshop","meta.helm.sh/release-namespace":"robot-shop","sre-stack/oom-fault-test":"active"}
```

The Helm release does not strip a key it does not manage. Consequence: the
marker outlives the redeploy, so the *lowered allowance* and the *marker* can
disagree — the marker alone cannot be the answer to "is the fault active".

**Step 2 — the Helm release manifest keeps the chart's allowance while the
live Deployment is lowered.** With the fault on (live at `24Mi`/`8Mi`), the
released manifest still said what the shop was installed with:

```
$ kubectl get deploy cart -n robot-shop -o jsonpath='{.spec.template.spec.containers[0].resources}'
{"limits":{"cpu":"200m","memory":"24Mi"},"requests":{"cpu":"100m","memory":"8Mi"}}
$ helm get manifest roboshop -n robot-shop | awk '/kind: Deployment/,/^---/' | grep -E "name: cart|resources:|memory:"
        resources:
              memory: 100Mi
              memory: 50Mi
        resources:
              memory: 100Mi
              memory: 50Mi
```

(The awk above prints the resources of every Deployment in the release
manifest — the exact `cart` document is what the script will pick. The point
proven here is that the released manifest carries `100Mi` / `50Mi` while the
live object carries `24Mi` / `8Mi`.)

That answers FR-008 cleanly: "the allowance the shop is installed with" is
*read from the Helm release manifest at revert time*, so no value recorded
when the fault started is replayed and nothing depends on the two commands
running from the same shell. (The marker test annotation was removed after
this step; the chart values are back at `100Mi` / `50Mi`.)

**Status truth table — what each input separates.**

| marker set | live allowance lowered vs chart | status says |
|---|---|---|
| yes | yes | **fault active** (holds while the pod backs off — the 2026-10-21 clarification) |
| yes | no | not active — allowance is correct, marker is left over; revert clears it |
| no | yes | not active — allowance lowered but this fault did not set it (EC-008 / story 006's unowned-fault line) |
| no | no | not active — and if cart is `OOMKilled` at its own allowance, say so (EC-006) |

Without the marker, rows 2 and 3 collapse and "who lowered the allowance"
cannot be told apart, which would weaken FR-010 in convergence — the reason
it is Proposal A rather than a purely derived status.

**Cleanup.** The marker and the lowered allowance were both removed after
Step 2; the shop's cart pod was `2/2 Running`, `restarts=0` with chart values
restored.

---

## Finding 5 — Traffic reaches cart on its own, fine enough to trigger the kill

**The question.** Register 5 in Technical Context (a spec "Not yet checked"):
does the load generator's traffic actually reach cart often enough for the kill
(SC-001) to run with no traffic change?

**What the loadgen sends.** `infra/azure/load-gen/load.yaml` starts the
`robotshop/rs-load:2.1.0` Locust client pointed at
`http://web.robot-shop.svc.cluster.local:8080` with `NUM_CLIENTS=10`,
`RUN_TIME=1h` (full file read before starting it). The Azure setup prints how
to start it and does not start it itself (`makefile:273–277`).

**Evidence on the live cluster, with the fault off.** During Finding 1 the load
generator was running (started 16:50, runs for 1 h). Cart's own access log —
the shop web frontend, not a manual call — showed real shopping traffic
against cart (`python-requests/2.26.0` is the loadgen's user agent):

```
{"...","url":"/cart/anonymous-22","headers":{"host":"cart:8080",...},"res":{"statusCode":200,...},"responseTime":2,...}
{"...","url":"/add/anonymous-22/RED/1","headers":{"host":"cart:8080",...},"res":{"statusCode":200},...}
{"...","url":"/update/anonymous-22/RED/2","headers":{"host":"cart:8080",...},"res":{"statusCode":200},...}
```

and the shop mesh metric for the same window:

```
$ curl -s "http://localhost:19090/api/v1/query?query=sum(rate(istio_requests_total{destination_workload=\"cart\",destination_workload_namespace=\"robot-shop\"}[5m]))"
…
"value": [1792586416.49, "4.322807017543859"]
```

≈ 4.3 requests/s from the loadgen reach cart, while the demo must hold a
container that idles at `31–33Mi` — the kill in Finding 1 happened at the same
rate. EC-001 ("no shop traffic") stays for a cluster without loadgen; the
guide should still say how to check traffic is flowing, since with the
generator down cart may not be touched at all.

**Answer.** Confirmed: the loadgen's traffic passes through the shop
frontend into cart at a rate the Finding 1 kill comfortably exceeded.

---

## Finding 6 — Command surface and how each command reports its own result

**The question.** What shape the three commands take, how their results are
printed, and the time budget. This decides the shared `/contracts/commands.md`
in Phase 1 and the `RESULT:` style story 006 already established for Azure, so
the new commands feel like siblings of the existing ones.

**Checked (files only, no cluster):**

- Story 006's script prints exactly one `RESULT:` line per run
  (`infra/azure/scenario-01/ratings-abort.sh`; `grep -n RESULT` lists 15
  possible variants, e.g. `RESULT: fault active (10 of 10 requests to ratings
  answered with error 500)`), which is the wording the guide quotes.
- The Azure block of `makefile` holds `aks-ratings-abort-start`, `-status`,
  `-revert` at `makefile:245–252`, each one `bash infra/azure/scenario-01/….sh
  start|status|revert` plus three `help` lines at `makefile:32–34`. The new
  commands follow that pair: three targets and one script argument each, so
  the printed result is what a presenter reads.
- Time budgets from the spec: start and revert each under 90 s *including* the
  wait for their own result (SC-005); the Finding 1 run — change, first kill,
  and 3 kills — stayed inside 90 s. Status is a read; the Finding 2 and
  Finding 4 probes each answered within a couple of seconds. The 90-second
  budget is real, not aspirational.
- Exit codes: story 006's script exits `0` when the command did what it meant
  and non-zero on refusal or timeout. The new script follows the same shape so
  `make` output and CI pipelines behave identically.

**Answer.** Three make targets (`start|status|revert`) calling one
Azure-only script; one `RESULT:` line per run describing what was seen; exit
`0` on success, non-zero on refusal; the whole command including its check
inside 90 s. The exact target names, script path and wording are the
`contracts/commands.md` decision in Phase 1, not a finding here.



