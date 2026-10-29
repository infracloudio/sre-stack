# Implementation Plan: Alert Rules for the Demo Shop on Azure

**Branch**: `009-robot-shop-alert-rules` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-robot-shop-alert-rules/spec.md`

**Status**: Being written one section at a time (constitution principle IX). Sections not yet approved are not in this file.

## Technical Context

**Language/Version**: YAML for the Kubernetes objects, PromQL (the Prometheus query language) for the rule conditions, and bash for the makefile glue. No application code.

**Primary Dependencies**: The monitoring system already on the cluster: `kube-prometheus-stack` Helm chart pinned at 52.0.0 (`makefile:213`, inside the `setup-aks-prometheus-stack` target that starts at line 210), which brings the Prometheus Operator. The operator reads `PrometheusRule` objects (a Kubernetes object that holds alert rules). The metrics come from kube-state-metrics (pod and deployment state) and the Istio sidecars (`istio_requests_total`), per research Findings 2 and 3. Nothing new is installed and no chart pin changes.

**Storage**: N/A. The rules are Kubernetes objects stored in the cluster. Nothing is stored anywhere else.

**Testing**: Two layers. No new offline shell test is added for this story (your decision, 2026-10-28).
- Rule check with `promtool` (the Prometheus tool that checks rule syntax and can unit-test rules). It is installed on this machine only, at `~/.local/bin/promtool`, version 2.47.1 to match the Prometheus the chart deploys. I rendered the chart (`helm template` with both values files) and it printed `quay.io/prometheus/prometheus:v2.47.1`. I checked the download against the release's `sha256sums.txt` (it printed `OK`) and `promtool --version` printed `2.47.1`. It is not added to `make install`, `make setup` or any repo file; whether it should be is a later decision.
- Live, on the Azure cluster: the verification run in the spec (cart fault, slow-database fault, 30-minute quiet run). Needs the load generator.
- Other tools on this machine: `helm` v3.18.6, `kubectl`, `yq`, `shellcheck`, `yamllint`.

**Target Platform**: Azure AKS only (`STACK_MODE=aks`, the default in `.env:5`). The local k3d and AWS setups must not change (FR-013).

**Project Type**: Infrastructure glue (YAML plus makefile), matching the rest of this repo.

**Performance Goals**: Alerts firing within 5 minutes of a fault starting and clearing within 10 minutes of it ending (SC-001, SC-002, SC-004). No other performance target.

**Constraints**:
- The Prometheus object only loads rules labelled `release: prometheus-stack`, from any namespace (research Finding 1).
- The Bookinfo rule lives in the shared `monitoring/chart-values/prometheus-values.yaml` and must not be touched (FR-016). I confirmed this with a repo search for `reviewsHTTPError`.
- The existing Azure observability setup is `setup-aks-o11y` (`makefile:205`). The one-shot `setup-aks` (`makefile:295`) already calls it, so adding to `setup-aks-o11y` reaches the one-shot setup with no extra step (FR-014).
- Existing Azure-only files sit under `infra/azure/` (for example `infra/azure/dashboards/slow-requests.yaml`, a ConfigMap), which is the natural home for new Azure-only objects.
- Every script and make target must be safe to run twice (constitution principle I).

**Scale/Scope**: Six alert rules (out of memory, restarting, no ready copy, server errors, slow shipping, slow ratings) for one namespace (`robot-shop`).

**Cluster state right now**: `az aks show ... --query powerState.code` printed `Stopped`. It is not needed for this section. I will start it (`az aks start`, about 5 minutes) when a later section needs a live check, as you said I could.

## Constitution Check

Checked against `.specify/memory/constitution.md` version 1.5.0 (I read it in full for this section). This is the first pass, made before the design is written. It is checked again after Phase 1 design, as the template asks. "Pass" here means the plan as it stands does not break the rule. It does not mean the work is done.

| Principle | Result | What I checked or why |
|-----------|--------|-----------------------|
| I. Re-runnable scripts | Pass, to be proven | The plan adds only Kubernetes objects applied the normal way, which can be applied twice. Not yet proven. SC-008 proves it in the verification run. |
| II. Pinned versions | Pass | Nothing new is installed in the cluster. The chart pin (52.0.0) and the Prometheus image (v2.47.1, from `helm template`) do not change. `promtool` is a local tool pinned to 2.47.1 and is not a repo dependency. |
| III. One configuration surface | Exception, decided (Option A) | See below and the Complexity Tracking table. |
| IV. No secrets in git | Pass | The rules hold no credentials. |
| V. Workload placement | Pass | A rule is a settings object, not a workload. It has no pod, node pool or volume. |
| VI. Specs without technical detail | Pass | I searched `spec.md` for technical terms (PromQL, Prometheus, Istio, Helm, kubectl, YAML, promtool). The only matches were the branch name, the `research.md` file name and the "Finding N" pointers. |
| VII. Plain language | Pass so far | Each technical term in sections 1 and 2 is explained at first use. I keep checking this as each section is written. |
| VIII. Try it before you plan it | **Gaps, need new findings** | See below. |
| IX. Author in steps | Pass | This is section 2 of 6, proposed alone. |
| X. Converge to the agreed scope | Not applicable yet | It binds `/speckit-converge`, which comes after the build. |

**Principle III, the open point.** The principle says every tunable setting lives in `.env`. The spec asks for the slow-request and server-error limits to be tunable by changing a rule and applying it with one command (FR-015), and written down next to the rule (FR-012). Today `.env` has no latency or threshold entries (`grep -n -i "latency\|threshold\|limit\|OOM\|SLOW" .env` printed nothing). The existing 2-second shipping limit is inside `infra/azure/scenario-03/db-latency.sh`, not in `.env`. So there are two ways to follow the spec:
- **Option A, limits live in the rule file.** One file holds each limit with a comment giving its reason. It is the simplest and the file a person changing a limit would open anyway. It breaks principle III as written, so it needs an entry in the Complexity Tracking table, accepted by the Architect.
- **Option B, limits live in `.env`.** The rule file becomes a template filled in when it is applied. This follows principle III, but it adds a rendering step, and `promtool` can only check the filled-in result, not the template.

**Decision (developer, 2026-10-28): Option A.** The limits are numbers inside the rule conditions, and a template would make those conditions harder to read for little gain. The cost is that the Architect must accept a justified exception at the plan gate. It is recorded in the Complexity Tracking table below.

**Principle VIII, the gaps.** Findings 1 to 4 cover the metrics, the alert source and the payment decision. The plan still needs facts that `research.md` does not have:
- A 30-minute run with no fault, to choose the slow-request and server-error limits (the spec says they are chosen here, and Findings 3 and 4 are single short samples).
- Whether a normal redeploy of a shop service stays quiet with the wait before firing (EC-007, which the spec says the plan confirms).
- Whether the slow-database fault also raises the server-error alert (SC-005 relies on it).

None of these changes what the spec promises, so no return to the Architect is needed. Each one is a new finding in `research.md`, added one at a time with real output. They need the cluster, which is stopped. I will not guess the limits before then.

**Gate result.** One violation, principle III, is justified in the table below and waits for the Architect at the plan gate. The three research gaps must be closed before the plan fixes any limit.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle III: the alert limits live in the rule file, not in `.env` | FR-015 asks for one command to change a limit, and FR-012 asks for each limit's reason to be written next to it. A rule file with a comment per limit does both. | Keeping the limits in `.env` needs a template and a step that fills it in. `promtool` could then only check the filled-in result, and the conditions would be harder to read. |

## Phase 0 summary: what each design decision rests on

Research was done in `/speckit-specify` (principle VIII). It now has seven findings. Findings 1 to 4 were there when the spec was written. Findings 5, 6 and 7 were added on 2026-10-28 to close the three gaps named in the Constitution Check: the 30-minute quiet run, the normal redeploy, and the slow-database fault's effect on the other alerts. No section here copies their output; each decision points at the finding it rests on.

**What I re-checked today, because the cluster and chart may have moved.** Each printed what I expected:
- Make targets (`grep -n` on `makefile`): `setup-aks-o11y` at 205, `setup-aks-prometheus-stack` at 210, `setup-aks` at 295, `aks-cart-oom-start/status/revert` at 265/268/271, `aks-db-latency-start/status/revert` at 278/281/284, `setup-dashboards` at 157.
- Paths (`ls`): `infra/azure/scenario-02/cart-oom-kill.sh`, `infra/azure/scenario-03/db-latency.sh`, `infra/azure/load-gen/load.yaml` and `infra/azure/dashboards/slow-requests.yaml` all exist.
- Chart pin: `--version 52.0.0` is on `makefile:213`. On the cluster, the Prometheus object still has `ruleSelector={"matchLabels":{"release":"prometheus-stack"}}` and image `quay.io/prometheus/prometheus:v2.47.1`.
- Rules and Alertmanager: `kubectl get prometheusrule -A` still shows only `kube-prometheus-stack-rule-name`, and `kubectl get alertmanager -A` printed `No resources found`.
- The Istio duration metric used in Findings 5 to 7, `istio_request_duration_milliseconds_bucket`, exists (a count of the metric name in Prometheus's name list printed `1`).

| Decision | Rests on | What it says |
|----------|----------|--------------|
| Rules go in a `PrometheusRule` object labelled `release: prometheus-stack`, loaded from any namespace | Finding 1 | The selector label is confirmed twice, in research and again today. |
| All six rules are written from scratch, and the Bookinfo rule is left alone | Finding 1 | No ready-made rule packs are on. The only existing rule is the Bookinfo one. |
| Alerts are seen on the Prometheus alerts page only | Finding 1, AD-012 | There is no Alertmanager. Adding one is the next story (#123), not this one. |
| Each rule builds its own service label and its own "part of the cluster" label | Findings 2 and 3 | The ready-made `service` label always names the monitoring tool. The shop service name is in `container` (pod metrics), `deployment` (deployment metrics) and `destination_workload` (Istio metrics). |
| Out-of-memory alert uses `kube_pod_container_status_last_terminated_reason` with `reason="OOMKilled"` | Finding 2 | `container_oom_events_total` stayed at 0 during a real kill, so it is not used. Finding 7 saw no memory-killed container during the database fault. |
| Restart alert uses how much the restart counter rises in a window | Findings 2 and 6 | The counter belongs to each pod. A normal redeploy does not move it, so it stays quiet. |
| No-ready-copy alert uses `kube_deployment_status_replicas_unavailable`, with a wait of at least 2 minutes (my recommendation; confirmed in the limits section) | Findings 2 and 6 | It showed 1 for the cart during the fault. It also showed 1 for 46 to 76 seconds during a normal shipping redeploy, while the shop still had a working copy. A wait of 2 minutes covers that, and the metrics arrive within 45 seconds, so SC-001's 5 minutes still fits. |
| Server-error alert uses the share of 5xx replies per `destination_workload` from `istio_requests_total` (destination side), and ignores services with very few requests | Findings 3, 5, 6 and 7 | The share, not the count, because rabbitmq's single error would otherwise look like a failure. A healthy shop showed 0 server errors after start-up, a cart redeploy caused about 3 failed requests, and the database fault caused none. The cart fault also makes `web` return errors, so the alert fires for `web` too. |
| Slow-request alerts cover shipping and ratings, not payment, using the Istio duration histogram | Findings 4, 5 and 7 | Payment is slow with no fault (p95 about 2.2 s). Ratings separates cleanly. Shipping separates thinly (see below). |

**Not decided in this section.** The actual limits, the wait times and the shipping rule's shape belong to the "files to change" section, where each is written with its reason (FR-012). The findings narrow them like this:
- **Ratings:** a 0.5 s limit sits well above healthy (at most 0.21 s) and well below the fault (0.92 to 0.99 s, and 1.5 s in Finding 4).
- **Shipping:** the 2-second starting limit from story 008 would fire on a healthy shop (Findings 5 and 7). Healthy 2-minute p95 reached 3.8 s, and the fault held at 4.4 to 5.0 s, so a p95 limit has little room. The rule may need a different shape, for example the share of requests over a limit. That is for the next section.

**Still unknown, so not claimed.**
- (Resolved after approval, 2026-10-28: the 2 unavailable replicas were `catalogue` and `payment`, which had no running pod until 13:12:03. See the correction at the end of Finding 5.)
- Whether the out-of-memory alert clears on its own after the fix. The OOMKilled series belongs to a pod, and the old cart pod was replaced on revert (Finding 2), but I did not watch the series disappear. The verification run proves it (spec acceptance scenario 2 of story 1).
- Redeploys were tested for cart and shipping only, one run each, with 1 replica each. Slower services such as the databases were not tested.

**Corrected after you approved this section (2026-10-28).** I had asked you whether to define "ready" differently, because a cluster start looked not quiet for 5 to 10 minutes "even after the pods show Ready". That rested on my mistake. `catalogue` and `payment` had no running pod until 13:12:03, and my pod listing at 13:06:25 only counted the pods that existed (correction at the end of Finding 5). So the spec's wording, "counts from the moment every shop service is ready" (EC-002 and SC-003), is right as written. No spec change is needed and nothing goes to the Architect. Two things stay: the readiness check must look at every deployment and stateful set, not a pod list, and the quiet 30-minute run starts when the shop is ready and the alerts page shows nothing firing, because a start-up alert can linger a few minutes (the server-error replay in the next section was true until 13:15:45, about 3 minutes after the shop was fully up).

## Phase 1 design outputs

This section decides what the design holds and which three files record it. I have not written the three files yet. They are written only after you approve this section, and they carry its wording unchanged. This section does not set the limits, the wait times or the shipping rule's shape. Those belong to the next section (files to change), as the Phase 0 summary said.

**The three files, and why each exists.**
- `data-model.md` records the six alert rules as data: their names, the labels each one carries, its severity, and which fault should raise it. It also records the states an alert goes through (see below). It is the one place a later story looks to learn what an alert carries.
- `contracts/alert-rules.md` records the two things other people depend on: the labels every alert promises (the later Keep stories read them), and how the rules are installed and changed (the make target). Both are interfaces, so they get a contract. Nothing else here has one.
- `quickstart.md` records the runnable checks that prove the spec's success criteria, in order, with the real commands and what "pass" looks like. It does not hold the rule code.

**Decisions this section makes.**

1. **One rule object holds all six alerts.** It is one `PrometheusRule` named `robot-shop-alerts` in the `monitoring` namespace, with the label `release: prometheus-stack` (Finding 1) and one group of six rules. One object keeps the one-command apply simple (FR-015) and leaves the Bookinfo rule alone (FR-016). The path of the file is chosen in the next section.

2. **The six alert names.** Alertmanager will group by alert name and namespace later (AD-012), so the names must be unique and must not clash with the Bookinfo names. I checked the Bookinfo names with `grep -n "alert:" monitoring/chart-values/prometheus-values.yaml`: `reviewsHTTPError`, `productpageHTTPError`, `ratingsHTTPError` and `detailsHTTPError`. `ratingsHTTPError` sits close to a ratings alert of ours, so every new name starts with `RobotShop` to keep them apart. I reuse the five names from the earlier Keep try-out where the meaning is unchanged (`keep-tryout-findings.md` line 52), and split the slow-request alert in two as FR-005 asks.

| Alert name | What it says in plain words | Severity | Raised by |
|---|---|---|---|
| `RobotShopContainerOOMKilled` | A shop container was stopped for using too much memory | critical | cart memory fault |
| `RobotShopContainerRestarting` | A shop container keeps restarting | high | cart memory fault |
| `RobotShopReplicasUnavailable` | A shop service has fewer working copies than it should | warning | cart memory fault |
| `RobotShopHTTPErrors` | A high share of a service's requests got a server error | high | cart memory fault (fires for `web`; cart's own errors are ignored because too few requests reach it, Finding 8) |
| `RobotShopShippingSlowRequests` | The shipping cost lookup is slow | warning | slow-database fault |
| `RobotShopRatingsSlowRequests` | The ratings lookup is slow | warning | slow-database fault |

3. **Severities.** The spec leaves them to the plan. I use the values from the Keep try-out, which Keep accepted (`keep-tryout-findings.md` lines 47 and 52; I read them today and did not re-run the try-out): out of memory is critical, restarting and server errors are high, the rest are warning. I keep "no ready copy" at warning, not higher, because Finding 6 showed that number also rises during a normal redeploy while the shop still has a working copy, so it should not read as an outage. The levels `error` and `info` stay unused. The spec only asks that each alert carry one of the five.

4. **Labels every alert carries (FR-007, FR-008).** `severity`, `namespace` (always `robot-shop`) and `service` (the shop service the alert is about, such as `cart`). Each rule builds `service` itself from the label that holds the name on its metric (Findings 2 and 3). Keep turns Prometheus labels into top-level fields, so a Keep rule on `namespace == "robot-shop"` works (`keep-tryout-findings.md` line 58). Each alert also carries a plain-language `summary` that names the service.

5. **Alert states.** A rule condition goes from "inactive" to "pending" (true, but not for long enough) to "firing" (true for the whole wait before firing), and back to "inactive" when the condition ends. The wait is what keeps a blip quiet (FR-009). The alerts page shows these states, and the rules API at `http://20.235.19.12/prometheus/api/v1/rules` shows them as JSON. I checked that both answer today (`alerts page http 200`, and the API returned the Bookinfo group).

6. **How the rules are installed and changed (FR-014, FR-015).** One new make target, `setup-aks-alert-rules`. I ran `grep -n "alert-rules\|alert_rules\|prometheusrule" -i makefile` and it printed nothing, so the name is free. It is added to the prerequisites of `setup-aks-o11y` (line 205) after `setup-aks-prometheus-stack`, because the rule object needs the `prometheusrules.monitoring.coreos.com` definition that the chart installs. I checked that it exists on the cluster today (`kubectl get crd` printed `prometheusrules.monitoring.coreos.com`). `setup-aks` already calls `setup-aks-o11y`, so the one-shot setup gets the rules with no extra step. Running the target alone applies a changed rule with no chart upgrade. It must be safe to run twice (SC-008).

7. **What the quickstart proves, in order.** (a) Setup twice changes nothing (SC-008, SC-009). (b) The cart fault raises the four alerts, and the revert clears them (SC-001, SC-004, SC-005). (c) The slow-database fault raises the two slow-request alerts (SC-002, SC-005). (d) A quiet 30-minute run raises none (SC-003). (e) Change one limit and see it in use within 2 minutes (SC-007). (f) Nothing the local or AWS setup uses changed (SC-010). (g) `make lint` and the `promtool` rule check pass (SC-011). It uses `make aks-cart-oom-start/status/revert` and `make aks-db-latency-start/status/revert`, which I confirmed at the line numbers in the Phase 0 summary. Section 6 added checks 8 to 10 for the edge cases EC-001, EC-006 and EC-007, which had no proving check.

**A mismatch I found, for your decision.** The epic's `_bmad-output/specs/spec-keep-alert-management/SPEC.md` line 65 says the metrics come from kube-state-metrics and Beyla, and that `istio_requests_total` "has too few robot-shop series to use". Finding 3 showed the opposite: `istio_requests_total` is the better source, and Beyla repeats Istio and adds a non-shop service called `envoy`. I follow the findings, as the constitution asks. I recommend not editing `SPEC.md` in this story, writing the departure into `plan.md`'s notes at the end, and filing a one-line follow-up so the epic text is corrected. Do you agree?

## Files to change

This section lists every file the build touches, with the exact change, and the limits and wait times with the numbers behind them. Nothing here is applied to the cluster or the repo yet: a change needs `gate:plan-approved` first. The rule file below is the checked scratch copy, pasted unchanged.

**What I checked for this section** (each printed what I expected):
- `yamllint -c .yamllint.yaml` on the rule file: no findings. New files are held to the full standard, so this matters for `make lint`.
- `yq '.spec' ... | promtool check rules`: `SUCCESS: 6 rules found`.
- `kubectl apply --dry-run=server -f` on the live cluster: `prometheusrule.monitoring.coreos.com/robot-shop-alerts created (server dry run)`. A follow-up `kubectl get prometheusrule -A` still shows only `kube-prometheus-stack-rule-name`, so nothing was created.
- The final file replayed over today's recorded data (Finding 8): the same fire and clear times as the table below.
- `grep -n "makefile\|README\|AGENTS\|infra/azure\|docs/arch" agent/hooks/protected-paths.txt` printed nothing, so none of the files below is protected.
- `ls infra/azure/alert-rules` printed `No such file or directory`, so the path is free.
- `check-observability-placement.sh` reads a named list of files, not everything under `infra/azure/`, so the new file does not affect it.
- The admission webhook on `PrometheusRule` has `failurePolicy=Ignore`, so an operator that is not ready yet cannot make the apply fail. The only real dependency is the `PrometheusRule` type, which the chart's Helm install creates. So `setup-aks-alert-rules` needs no extra wait.

### The limits and waits

All times come from Finding 8 (cart fault started 14:34:37 and was removed 14:42:47; database fault started 14:09:59 and was removed 14:15:12).

| Alert | Limit | Looks back | Minimum requests | Wait | Fires after the fault starts | Clears after the fix |
|-------|-------|-----------|------------------|------|------------------------------|----------------------|
| `RobotShopContainerOOMKilled` | a restart in the window, with last stop reason OOMKilled | 10 min | none | 1 min | 1m53s | 28 s |
| `RobotShopContainerRestarting` | more than 1 restart | 10 min | none | 1 min | 1m53s | 28 s |
| `RobotShopReplicasUnavailable` | any working copy missing | now | none | 2 min | 2m53s | 28 s |
| `RobotShopHTTPErrors` | more than 5% of requests are 5xx | 5 min | 30 | 2 min | 3m38s | 3m49s |
| `RobotShopShippingSlowRequests` | more than 15% of requests slower than 2.5 s | 2 min | 30 | 2 min | 3m01s | 48 s |
| `RobotShopRatingsSlowRequests` | more than 10% of requests slower than 0.5 s | 2 min | 30 | 2 min | 2m31s | 1m33s |

Against the spec: every alert fires inside the 5 minutes of SC-001 and SC-002 (the slowest is 3m38s) and clears inside the 10 minutes of SC-004 (the slowest is 3m49s). The three tuned limits (server errors, shipping, ratings) each have their value and reason in the file's comments (SC-012). These are one run each, so the live verification run confirms them or they change with a reason written down.

**Why the shipping rule counts the share of slow requests and not the 95th percentile.** Finding 5 showed the old 2-second limit would fire on a healthy shop, and Findings 5 and 7 showed a 95th-percentile limit leaves almost no room (healthy up to 3.8 s, fault 4.4 to 5.0 s). The share of requests slower than 2.5 seconds separates them better: 0.5% to 7.4% when healthy, 7% to 24% during the fault (Finding 8, part D). Ratings uses the same shape for consistency. The "slow" figures differ from story 008's, which were a different measure.

### 1. New file: `infra/azure/alert-rules/robot-shop-alerts.yaml`

The path follows `infra/azure/dashboards/slow-requests.yaml`, the other Azure-only object that is applied with `kubectl apply`. The whole file:

```yaml
# Alert rules for the demo shop on AKS (specs/009-robot-shop-alert-rules).
# Applied by `make setup-aks-alert-rules`, which setup-aks-o11y runs after the
# monitoring chart. Prometheus loads this object because of the
# `release: prometheus-stack` label (research Finding 1). Nothing sends these
# alerts anywhere yet; they show on the Prometheus alerts page.
#
# Change a limit here, run `make setup-aks-alert-rules` again. No chart
# upgrade is needed.
#
# Every alert carries severity, namespace and service (contracts/alert-rules.md).
# The limits below were chosen from measured behaviour; each comment gives the
# numbers and the research finding they come from. Waits (`for`) keep a blip
# from raising an alert (FR-009). Minimum request counts keep a service with a
# handful of requests quiet (EC-005).
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: robot-shop-alerts
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  groups:
    - name: robot-shop
      rules:
        # A shop container was stopped for using too much memory. The metric
        # for the last stop reason is used; container_oom_events_total stays 0
        # during a real kill (Finding 2). The restart part makes it end after
        # 10 minutes without a new kill; the pod-still-exists part is the
        # reason it clears at once when the pod is replaced.
        # Measured: fires 1m53s after the cart fault starts, clears 28s after it
        # is removed (Finding 8).
        - alert: RobotShopContainerOOMKilled
          expr: |
            sum by (namespace, service) (
              label_replace(
                (increase(kube_pod_container_status_restarts_total{namespace="robot-shop"}[10m]) > 0)
                and on (namespace, pod, container)
                (kube_pod_container_status_last_terminated_reason{namespace="robot-shop", reason="OOMKilled"} == 1),
                "service", "$1", "container", "(.*)")
            )
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "{{ $labels.service }} was stopped for using too much memory"

        # A container restarted more than once in 10 minutes. Limit: more than
        # 1. A healthy shop had 0 restarts in 30 minutes (Finding 5) and a normal
        # redeploy does not move the counter (Finding 6). The cart fault gave 6
        # restarts in 8 minutes (Finding 8).
        # The pod-still-exists part is needed: without it the alert stayed on
        # 7m19s after the fix, because a 10-minute window keeps a replaced pod's
        # count (Finding 8, part C).
        - alert: RobotShopContainerRestarting
          expr: |
            sum by (namespace, service) (
              label_replace(
                (increase(kube_pod_container_status_restarts_total{namespace="robot-shop"}[10m]) > 1)
                and on (namespace, pod, container)
                kube_pod_container_status_restarts_total{namespace="robot-shop"},
                "service", "$1", "container", "(.*)")
            )
          for: 1m
          labels:
            severity: high
          annotations:
            summary: "{{ $labels.service }} restarted {{ $value | humanize }} times in 10 minutes"

        # A service has fewer working copies than it should. Covers the
        # deployments and the two stateful sets (mysql, redis).
        # Wait: 2 minutes. A normal redeploy of shipping showed 1 copy not ready
        # for 46 to 76 seconds while the shop still had a working copy
        # (Finding 6), so 2 minutes keeps a redeploy quiet. The cart fault fires
        # it 2m53s after the start (Finding 8), inside the 5 minutes SC-001 allows.
        - alert: RobotShopReplicasUnavailable
          expr: |
            sum by (namespace, service) (
              label_replace(kube_deployment_status_replicas_unavailable{namespace="robot-shop"} > 0,
                "service", "$1", "deployment", "(.*)")
            )
            or
            sum by (namespace, service) (
              label_replace(
                (kube_statefulset_replicas{namespace="robot-shop"} - kube_statefulset_status_replicas_ready{namespace="robot-shop"}) > 0,
                "service", "$1", "statefulset", "(.*)")
            )
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "{{ $labels.service }} has fewer working copies than it should (missing: {{ $value }})"

        # A high share of a service's requests got a server error (5xx), seen
        # from the receiving side (Istio, Finding 3).
        # Limit: more than 5% over 5 minutes. A healthy shop showed 0% (Finding
        # 5), a normal cart redeploy about 0.4% (Finding 6), the slow-database
        # fault 0% (Finding 7). The cart fault raised web to about 24% (Finding
        # 8), nearly five times the limit; a higher limit would only fire later.
        # Minimum: 30 requests in the 5 minutes. A service with a handful of
        # requests is ignored (EC-005): rabbitmq and mysql see about 10 per 5
        # minutes, and cart saw 18 or fewer once the fault had settled.
        # Wait: 2 minutes. Fires for web 3m38s after the cart fault starts (Finding 8).
        - alert: RobotShopHTTPErrors
          expr: |
            label_replace(
              (
                sum by (namespace, destination_workload) (rate(istio_requests_total{reporter="destination", namespace="robot-shop", response_code=~"5.."}[5m]))
                / sum by (namespace, destination_workload) (rate(istio_requests_total{reporter="destination", namespace="robot-shop"}[5m]))
                > 0.05
              )
              and on (namespace, destination_workload)
              (sum by (namespace, destination_workload) (increase(istio_requests_total{reporter="destination", namespace="robot-shop"}[5m])) >= 30),
              "service", "$1", "destination_workload", "(.*)")
          for: 2m
          labels:
            severity: high
          annotations:
            summary: "{{ $labels.service }} answered {{ $value | humanizePercentage }} of its requests with a server error"

        # The shipping cost lookup is slow. A plain 95th-percentile limit does
        # not separate fault from normal here: the healthy 2-minute value
        # reached 3.8 seconds and the fault sat at 4.4 to 5.0 seconds (Findings
        # 5 and 7). The share of requests slower than 2.5 seconds separates
        # them: 0.5% to 7.4% when healthy, 7% to 24% (about 23% once settled)
        # during the slow-database fault (Finding 8, part D).
        # Limit: more than 15% of requests over 2.5 seconds, over 2 minutes.
        # That is about twice the highest healthy value and below the fault.
        # Minimum: 30 requests in the 2 minutes (shipping gets about 200).
        # Wait: 2 minutes. Replayed against the database fault: fires 3 minutes
        # after the start, clears within a minute of the fix (Finding 8). The
        # old 2-second limit from story 008 would fire on a healthy shop
        # (Finding 5).
        - alert: RobotShopShippingSlowRequests
          expr: |
            (
              1 - sum by (namespace) (rate(istio_request_duration_milliseconds_bucket{reporter="destination", namespace="robot-shop", destination_workload="shipping", le="2500"}[2m]))
              / sum by (namespace) (rate(istio_request_duration_milliseconds_count{reporter="destination", namespace="robot-shop", destination_workload="shipping"}[2m]))
              > 0.15
            )
            and on (namespace)
            (sum by (namespace) (increase(istio_request_duration_milliseconds_count{reporter="destination", namespace="robot-shop", destination_workload="shipping"}[2m])) >= 30)
          for: 2m
          labels:
            severity: warning
            service: shipping
          annotations:
            summary: "{{ $value | humanizePercentage }} of shipping cost lookups took longer than 2.5 seconds"

        # The ratings lookup is slow.
        # Limit: more than 10% of requests over 0.5 seconds, over 2 minutes.
        # Healthy: at most 0.8%. Slow-database fault: 21% in the first sample
        # and 100% once settled (Finding 8, part D). 10% sits between the two.
        # Minimum: 30 requests in the 2 minutes (ratings gets about 150).
        # Wait: 2 minutes. Replayed against the database fault: fires 2m31s
        # after the start, clears 1m33s after the fix (Finding 8).
        - alert: RobotShopRatingsSlowRequests
          expr: |
            (
              1 - sum by (namespace) (rate(istio_request_duration_milliseconds_bucket{reporter="destination", namespace="robot-shop", destination_workload="ratings", le="500"}[2m]))
              / sum by (namespace) (rate(istio_request_duration_milliseconds_count{reporter="destination", namespace="robot-shop", destination_workload="ratings"}[2m]))
              > 0.10
            )
            and on (namespace)
            (sum by (namespace) (increase(istio_request_duration_milliseconds_count{reporter="destination", namespace="robot-shop", destination_workload="ratings"}[2m])) >= 30)
          for: 2m
          labels:
            severity: warning
            service: ratings
          annotations:
            summary: "{{ $value | humanizePercentage }} of ratings lookups took longer than 0.5 seconds"
```

### 2. Edit: `makefile` (three small changes)

1. Add the new target to the prerequisites of `setup-aks-o11y` (line 205), right after `setup-aks-prometheus-stack`, because the `PrometheusRule` type comes from that chart. Make runs prerequisites left to right:

   ```
   setup-aks-o11y: setup-db-grafana-psql setup-aks-prometheus-stack setup-aks-alert-rules setup-aks-loki setup-aks-log-shipper setup-aks-o11y-routes setup-dashboards setup-aks-tempo setup-aks-beyla setup-aks-caretta
   ```

2. Add the target itself after `setup-aks-o11y-routes` (line 240). It refuses off AKS the same way `setup-aks` does (`makefile:296`), and `kubectl apply` is safe to run twice:

   ```
   # Alert rules for the demo shop (specs/009-robot-shop-alert-rules). The
   # PrometheusRule type comes from the monitoring chart, so run this after it.
   # Edit the rule file and run this again to change a limit; no chart upgrade.
   setup-aks-alert-rules:
   ifneq ($(STACK_MODE),aks)
   	$(error setup-aks-alert-rules needs STACK_MODE=aks (currently '$(STACK_MODE)'))
   endif
   	kubectl apply -f infra/azure/alert-rules/robot-shop-alerts.yaml
   ```

3. Add one line to the help list after the `setup-aks-o11y-routes` line (line 30):

   ```
   	@echo "	setup-aks-alert-rules             - Apply the robot-shop alert rules (AKS)"
   ```

### 3. Edit: `README.md` and `AGENTS.md` (so the new target is findable)

- `README.md` line 144: add "the robot-shop alert rules" to the list in the `make setup-aks-o11y` comment. In the paragraph at lines 162 to 165, add `setup-aks-alert-rules` after `setup-aks-prometheus-stack` in the chain, and add one sentence: "The alert rules are in `infra/azure/alert-rules/robot-shop-alerts.yaml`; change a limit there and run `make setup-aks-alert-rules` (no chart upgrade)."
- `AGENTS.md` line 35: in the `make setup-aks-o11y` bullet, change "(Prometheus, Grafana," to "(Prometheus, the robot-shop alert rules via `setup-aks-alert-rules` (specs/009), Grafana,". One short clause, so the file stays on one page.

### 4. Decided (developer, 2026-10-28): `docs/architectural-decisions.md`, append AD-015

The repo's rule is that a decision with a cost gets one entry there, newest last. This story makes one: the alert limits live in the rule file and not in `.env` (the exception to principle III in the Complexity Tracking table), and the shipping rule counts the share of slow requests. The entry would say the decision, why (Findings 5, 7 and 8), and what was given up (a single configuration surface, and the simpler 95th-percentile rule). You agreed on 2026-10-28, so it is part of the build.

### 5. Not changed, on purpose

- `.env`: the limits stay in the rule file (Complexity Tracking).
- `monitoring/chart-values/prometheus-values.yaml`: the Bookinfo rule stays (FR-016), and this file is shared with the local and AWS setups (FR-013).
- `infra/azure/chart-values/prometheus-stack.yaml`: no Alertmanager here. That is story #123 and AD-012.
- The fault scripts, the load generator and local/AWS setup behavior (FR-013, FR-017). The shared makefile and documentation receive only the Azure-only additions and explanations listed above.
- Nothing under `agent/`, `.github/` or `.specify/`.

### Departures and follow-ups to record

- **Epic `SPEC.md` line 65** says the metrics come from kube-state-metrics and Beyla, and that `istio_requests_total` "has too few robot-shop series to use". Finding 3 and the replays here show Istio is the better source and Beyla repeats it. I follow the findings. `SPEC.md` is not edited in this story. A one-line follow-up issue should correct it.
- **Payment** is dropped from the slow-request alerts. The spec already states this (Story 2, Assumptions). Story #122 on GitHub still says payment, and the issue text needs a manual update.
- **The old Bookinfo rule** keeps `severity: P1`, which Keep would read as info. It stays as is (FR-016) and is a follow-up for a later story.
- **The quickstart** (`quickstart.md`) now names the real rule file path (replaced after you approved this section).
- **Both faults at once (check 9, EC-006): five alerts, not six.** The plan said all six alerts fire. The live run on 2026-10-28 showed `RobotShopShippingSlowRequests` cannot fire while the cart is down, because no requests reach shipping and the rule needs 30 requests in its window (research Finding 9). The developer accepted five of six on 2026-10-28. Check 9, tasks T027, and the screenshot list are updated to match. Shipping's firing is still proven alone in check 3.

## Verification strategy

This section says how the story is proven: which checks run, in what order, who runs them, what counts as pass, what is attached to the pull request, and what is not proven. The checks themselves, with their commands, are in `quickstart.md` (eleven check groups, including the local traffic-guard tests). Nothing here has been run yet, because the rule file is not applied until the build.

### What proves each requirement

Every success criterion (SC) and every named edge case (EC) has a check. The edge-case list is closed (spec "Edge Cases"), and constitution principle X asks for a proving check for each. Checks 8 to 10 cover no traffic, overlapping faults and redeploys. Check 11 adds local tests of the real request-count guards for zero traffic and very few requests. Check 7 also captures before-and-after proof that metrics, dashboards and traces work (FR-017). These additions are planned verification, not claims that the checks have run.

| Requirement | Proved by (quickstart check) |
|---|---|
| SC-001 cart fault seen | 2 |
| SC-002 database fault seen | 3 |
| SC-003 healthy shop quiet for 30 minutes | 4 |
| SC-004 alerts clear and stay clear | 2, 3, 9 |
| SC-005 each fault raises only its own alerts | 2, 3 |
| SC-006 every alert readable (service, namespace, severity) | 2 (step 4) and 3 (step 3), with rules API output saved while each fault is active |
| SC-007 a change is quick, no reinstall | 5 |
| SC-008 setup is safe to repeat | 1 |
| SC-009 part of the one-shot setup | 1 (wiring check), and the new-cluster proof below |
| SC-010 other setups untouched | 6 |
| SC-011 faults and monitoring still work, lint passes | 2, 3 and 7, including monitoring before/after evidence |
| SC-012 limits explained | 7 |
| EC-001 no shop traffic | 8 (all three request-based alerts) and 11 (zero/absent traffic inputs) |
| EC-002 just after a cluster start | "Before you start" (what "ready" means) and the start of check 4 |
| EC-003 an alert lingers after the fix | the clear times in 2 and 3 |
| EC-004 a pod is replaced during a fault | 2 (step 3) |
| EC-005 very few requests | 11 (each request-based rule below 30 requests, plus a high-traffic positive control); 2 (step 3) observes the live cart case |
| EC-006 both faults at once | 9 |
| EC-007 a normal redeploy | 10 |
| EC-008 running the setup twice | 1 |

### Order, and why

1. **Before the first rule apply**: run `make lint`, the `yamllint` and `promtool` syntax checks (check 7), the local traffic-guard tests (check 11), the file-scope portion of check 6 (committed, staged, unstaged and untracked files), and the `make -n setup-aks` wiring check (check 1, step 4). These are the offline gate in T016 and T035. If any fail, stop before the server dry run or apply. Also record the live monitoring baseline in check 7 step 5 before installation (T003); it is read-only and must pass.
2. **Apply, then prove repeat-safety** (check 1). Everything after needs the rules loaded. Before the first live check, confirm the shop is ready (`kubectl get deploy,sts -n robot-shop`, every READY column complete), the load generator is running, and the rules API lists the six `RobotShop` rules.
3. **The quiet 30 minutes** (check 4), before any fault, so no fault leaves residue in it.
4. **A normal redeploy** (check 10), still on a quiet shop.
5. **The cart fault** (check 2), then **the slow-database fault** (check 3), one at a time.
6. **No traffic** (check 8), then **both faults at once** (check 9). Allow the full 5-minute request window to drain for check 8, record background traffic, and check all three request-based alerts.
7. **Change a limit** (check 5) after the fault checks, as the last check that changes a rule. Restore the file with `git checkout -- infra/azure/alert-rules/robot-shop-alerts.yaml` and apply it again afterwards.
8. **Final regression checks**: repeat the monitoring query, dashboard and trace check after the faults are removed and the original limit is restored; save the after evidence alongside the baseline (check 7 step 5, T030). Re-run lint and the complete file-scope check after final edits.
9. **The new-cluster proof of SC-009** is not run for now (developer decision, 2026-10-28; see "Decided" below).

My estimate of the waiting time is 2.5 to 3 hours, mostly the 30-minute quiet run and the fault checks, which each need about 5 minutes to fire plus 10 to clear plus 10 to stay clear. It comes from the fire and clear times in Finding 8. The second `setup-aks-o11y` run was not timed.

### Who runs what

The builder runs all eleven check groups during `/speckit-implement` and records the output. Check 11 is local and runs before the first rule apply; monitoring checks run both before and after live verification. The independent human reviewer (author and approver must differ) can re-run a shorter set that covers the main claims: checks 1, 2, 6 and 7, which is about an hour. A reviewer may ask for any other check to be repeated.

### What counts as pass, and what to do when a check fails

- A check passes only when its expected result in `quickstart.md` appears in real output. "Should work" is not a pass.
- The fire and clear times in spec SC-001, SC-002 and SC-004 are targets. The run confirms them, or they change with a reason written down (spec, Success Criteria).
- If a check fails, do not weaken it or work around it. Fix the cause in the rule file, then re-run the failed check and any check the fix could affect. A change to a limit or a wait needs three things in the same commit: the new value with its reason in the rule file comment, a new finding in `research.md` with the real numbers, and a one-line departure in `plan.md`.
- Convergence is one round (principle X). A problem that traces to nothing already agreed becomes a new story, not a task here.

### What is attached to the pull request

Following stories 007 and 008, a folder `specs/009-robot-shop-alert-rules/evidence/` holds:
- `quickstart-run.txt`: each check's commands and real output, with times.
- `lint-before.txt` and `lint-output.txt`: actual `make lint` output and exit codes before installation and after verification.
- `scope-before.txt` and `scope-check.txt`: committed, staged, unstaged and untracked file lists plus shared-file diffs, showing only the intended Azure additions and zero diff in the shared Bookinfo settings. Repeat the final file check after the last edits.
- `rules-api.json`: inactive rule definitions with their static labels. `rules-api-cart.json` and `rules-api-database.json`: responses saved during the respective faults, showing the namespace, service and severity on active instances of all six alerts (SC-006).
- `replicas-unavailable-rules.yaml`, `replicas-unavailable-test.yaml` and its real test output: the retained rule snapshot and stateful-set test. T013 extracts its own snapshot after T012 and finishes before T014 edits the source file.
- `traffic-guards-rules.yaml`, `traffic-guards-test.yaml` and its real test output: snapshot and local cases for absent/zero traffic, very few bad requests, and high-traffic positive controls.
- `monitoring-before/` and `monitoring-after/`: shop-traffic query output, dashboard screenshots, request times, trace IDs and screenshots showing newly recorded request steps before installation and after verification (FR-017, SC-011).
- Screenshots of the alerts page: before any fault, during the cart fault (four firing), during the database fault (two firing), and with both faults (five firing; the shipping alert cannot fire while the cart is down, see the departure below).
- `pr-entries.md`: the list above and any departures from this plan.

The pull request carries the `evidence:attached` label once these are in.

### Cleaning up afterwards

Remove both faults (`make aks-cart-oom-revert`, `make aks-db-latency-revert`), put the load generator back to one copy (`kubectl -n loadgen scale deployment/load --replicas=1`), restore the rule file if check 5 changed it, and stop the cluster (`az aks stop`) unless more work follows. If an SC-009 proof cluster is created later, it is removed with `make cleanup`.

### What is not proven live

- **The stateful-set branch of the no-ready-copy rule** (mysql and redis). Stopping the database on the live shop to prove it is not worth the risk. It was checked only with a local `promtool test rules` unit test on made-up numbers, which passed. I will paste that test and its output into the evidence folder as a record. It is not a test the repo runs.
- **The limits come from one run each** (Finding 8). The verification run gives a second sample for each. If it differs a lot, the limits change as described above.
- **Redeploys were tested for cart and shipping only**, not for the databases (Finding 6 and check 10).

### Decided by the developer, 2026-10-28

1. **No new cluster for now.** The only full proof that "one command on a new cluster gives six alerts" (SC-009) is to run `make setup-aks` on a new cluster. That creates a real Azure cluster, which costs money and takes time I have not measured. You decided on 2026-10-28 not to create one for now and to keep working on the existing cluster. So the pull request records the `make -n setup-aks` wiring evidence and explicitly says the new-cluster outcome is not proven live. Running the proof later is a separate go-ahead, and it would be removed afterwards with `make cleanup`.
2. **SC-008 clarified (developer-approved analysis fixes, 2026-10-28).** The spec now states the accepted distinction: the monitoring rerun succeeds, and this story’s alert-rule step creates no new objects and changes no installed rules. The earlier whole-setup "creates or changes 0 things" wording was too broad. `setup-aks-o11y` runs `helm upgrade --install` for each chart, and Helm records a new revision for each upgrade (the monitoring release has 3 revisions today). I have not checked whether an unchanged re-run adds one. SC-008 is read as: the second run exits 0, the alert rule object is unchanged (same `resourceVersion`), and this story's step creates nothing new. The Helm revision numbers before and after are recorded as plain evidence, and a change there is reported, not hidden.

### Analysis fixes approved by the developer, 2026-10-28

The developer approved all fixes in one pass. FR-013, SC-010 and the installation contract now permit the agreed Azure-only edits to shared files while preserving AWS/local behavior. FR-014, SC-008 and EC-008 use the recorded rule-step repeat-safety decision. SC-011 and quickstart check 7 explicitly require before-and-after metrics, dashboard and trace proof. The quickstart and tasks now cover all request-based rules for zero and low traffic, inspect labels on active alert instances, retain a separate test snapshot, include uncommitted files in scope checks, and enforce lint before installation as well as after verification. These are documentation corrections; the rule YAML above is unchanged. Architect approval of the revised spec and plan, including the existing principle III exception, is still required before implementation. SC-009 remains unproven on a new cluster.
