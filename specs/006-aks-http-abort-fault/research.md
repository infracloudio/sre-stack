# Research: HTTP Abort Fault for the Demo Shop on Azure

Phase 0 findings for [plan.md](plan.md), taken from a live run (constitution
principle VIII). Every output block below is pasted from the terminal.

**Cluster**: AKS `sre-stack-452138` (current kubectl context), freshly set up
with `make setup-aks` on 2026-10-14. Istio `1.30.4`, shop namespace
`robot-shop`. Test requests are sent from inside the shop's `web` pod (it has
`/usr/bin/curl` and an Istio sidecar), so they pass through the mesh the same
way the shop's own requests do.

---

## Finding 1 — Put the fault in the existing ratings rule; a second rule is ignored

**Question** (Technical Context open item 1): to make ratings fail, do we edit
the routing rule (VirtualService — Istio's per-service traffic rule) that the
shop's install already created, or add a second rule for the same service?

**Decision**: Start adds a fault (answer 100% of requests with error 500) to
the existing `ratings` rule; revert removes it again.

**Rationale**: When two rules name the same service, Istio used only the
original one. The second rule had no effect and gave no warning. Editing the
original worked on 10 of 10 requests and reverting restored it exactly.

**Alternatives considered**: A separate `ratings-fault` rule, which would leave
the shop's own rule untouched and make revert a simple delete. Rejected: 10 of
10 requests still succeeded while it was in place.

### What was run

The shop's rule as installed — owned by Helm (the tool that installs the shop):

```text
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  annotations:
    meta.helm.sh/release-name: roboshop
    meta.helm.sh/release-namespace: robot-shop
  labels:
    app.kubernetes.io/managed-by: Helm
  name: ratings
  namespace: robot-shop
spec:
  hosts:
  - ratings
  http:
  - route:
    - destination:
        host: ratings
--- web pod tools
/usr/bin/curl
--- baseline
/_health 200
/api/fetch/Watson 200
```

**Test B — second rule `ratings-fault` for host `ratings`** (100% abort, 500),
10 requests to `/_health`, then deleted:

```text
virtualservice.networking.istio.io/ratings-fault created
200 200 200 200 200 200 200 200 200 200 
--- istiod analysis
NAME            GATEWAYS   HOSTS         AGE
ratings                    ["ratings"]   15m
ratings-fault              ["ratings"]   9s
virtualservice.networking.istio.io "ratings-fault" deleted
--- after delete
200 200 200
```

**Test A — fault added to the existing `ratings` rule** with a JSON patch
(`add /spec/http/0/fault`), 10 requests, one full response, then removed
(`remove /spec/http/0/fault`):

```text
virtualservice.networking.istio.io/ratings patched
kubectl patch virtualservice ratings -n robot-shop --type=json   0.06s user 0.01s system 40% cpu 0.174 total
500 500 500 500 500 500 500 500 500 500 
--- one response body+headers
HTTP/1.1 500 Internal Server Error
content-length: 18
content-type: text/plain
date: Wed, 14 Oct 2026 11:23:27 GMT
server: envoy

fault filter abort
--- labels/annotations after patch
{"app.kubernetes.io/managed-by":"Helm"}
{"hosts":["ratings"],"http":[{"fault":{"abort":{"httpStatus":500,"percentage":{"value":100}}},"route":[{"destination":{"host":"ratings"}}]}]}
--- restore
virtualservice.networking.istio.io/ratings patched
kubectl patch virtualservice ratings -n robot-shop --type=json   0.06s user 0.02s system 54% cpu 0.147 total
200 200 200 200 200 200 200 200 200 200 
{"hosts":["ratings"],"http":[{"route":[{"destination":{"host":"ratings"}}]}]}
```

### Notes and surprises

- **Silent failure of the second rule.** Nothing — not `kubectl apply`, not
  `kubectl get` — said the second rule was being ignored. A command built that
  way would have reported success while changing nothing; the FR-012 check
  (send test requests after the change) is what would catch it.
- **Timing.** Each patch took about 0.2 s; requests were failing at the first
  check 5 s later. Well inside SC-005 (30 s per command).
- **Revert is exact.** After removal the rule's `spec` matches the installed
  one character for character.
- **Helm still owns the rule while the fault is on** (`managed-by: Helm` label
  unchanged). Whether a shop reinstall wipes the fault is Finding 2 (EC-002).
- **Injected errors are recognisable**: body `fault filter abort`, header
  `server: envoy`. Input to Finding 4 (telling this fault apart from ratings
  failing for another reason); not yet confirmed against a real failure.

Cluster left as installed: `ratings-fault` deleted, `ratings` rule back to the
original, ratings answering 200.

---

## Finding 2 — Re-running the shop install keeps the fault (EC-002)

**Question** (Technical Context open item 2, spec EC-002): if someone re-runs
the shop's normal install (`make setup-robot-shop`, which runs `helm upgrade`)
while the fault is on, is the fault silently removed?

**Decision**: No — the fault survives. The guide says so, and says that revert
is the way to remove it; start can be run again if it was ever lost (FR-004).

**Rationale**: On upgrade, Helm compares its previous copy of each object with
its new copy and only changes what differs between those two. The shop's chart
did not change, so Helm had nothing to change in the ratings rule and left the
live fault in place. 10 of 10 requests still failed after the reinstall.

**Limit of this finding**: it holds while the chart's ratings rule file
(`app/robot-shop/helm/templates/ratings-vs.yaml`) is unchanged. If a later
change edits that file, the next reinstall rewrites the rule and the fault is
dropped. Not tested: a reinstall across a chart change.

**Alternatives considered**: none — this is an observation the spec asked for,
not a design choice.

### What was run

Fault added (same patch as Finding 1), then `make setup-robot-shop`, then the
rule and 10 requests checked:

```text
virtualservice.networking.istio.io/ratings patched
--- before reinstall
500 500 500 500 500 
REVISION	UPDATED                 	STATUS  	CHART           	APP VERSION	DESCRIPTION     
1       	Wed Oct 14 16:38:01 2026	deployed	robot-shop-1.1.0	           	Install complete
--- reinstall
kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
namespace/robot-shop configured
kubectl label namespace robot-shop istio-injection=enabled
namespace/robot-shop not labeled
kubectl delete job mysql-seeder -n robot-shop --ignore-not-found
job.batch "mysql-seeder" deleted
helm upgrade --install roboshop -n robot-shop --create-namespace ./app/robot-shop/helm/ --values ./infra/azure/chart-values/robot-shop.yaml --set stack_mode=aks --set mysql_root_password=<REDACTED> --wait --timeout 10m0s
Release "roboshop" has been upgraded. Happy Helming!
NAME: roboshop
LAST DEPLOYED: Wed Oct 14 17:03:37 2026
NAMESPACE: robot-shop
STATUS: deployed
REVISION: 2
TEST SUITE: None
make setup-robot-shop 2>&1  3.79s user 0.39s system 69% cpu 6.013 total
tail -15  0.00s user 0.00s system 0% cpu 6.013 total
--- after reinstall
REVISION	UPDATED                 	STATUS    	CHART           	APP VERSION	DESCRIPTION     
1       	Wed Oct 14 16:38:01 2026	superseded	robot-shop-1.1.0	           	Install complete
2       	Wed Oct 14 17:03:37 2026	deployed  	robot-shop-1.1.0	           	Upgrade complete
{"hosts":["ratings"],"http":[{"fault":{"abort":{"httpStatus":500,"percentage":{"value":100}}},"route":[{"destination":{"host":"ratings"}}]}]}
500 500 500 500 500 500 500 500 500 500 
```

(One value redacted above: `make` echoes the demo MySQL password from `.env`
`RDS_MYSQL_DB_MASTER_PASSWORD`; replaced with `<REDACTED>` so the secrets
hook passes. Everything else is as printed.)

Fault then removed, Helm version recorded:

```text
v3.18.6+gb76a950
virtualservice.networking.istio.io/ratings patched
200 200 200 200 200 
{"hosts":["ratings"],"http":[{"route":[{"destination":{"host":"ratings"}}]}]}
```

### Notes and surprises

- `kubectl label namespace robot-shop istio-injection=enabled` prints
  `namespace/robot-shop not labeled` on a re-run and exits 0 — harmless.
- Side observation, outside this story: before this test the database-loading
  job pod (`mysql-seeder-ft72f`) was still `1/1 Running` with 3 restarts,
  about 4 minutes after install, rather than finished. The reinstall deleted it
  and started `mysql-seeder-xww8d`. Not investigated here.

---

## Finding 3 — Commands check their result from the `web` pod, in one go

**Question** (Technical Context open item 3, FR-012, FR-013): after changing
the rule, from where do the commands send their test requests, to which
ratings address, and how many must fail or succeed?

**Decision**:
- Start, revert and status each run one `kubectl exec` into the shop's `web`
  pod (container `web`), which sends 10 requests to `http://ratings/_health`,
  each limited to 3 seconds.
- Start passes only on 10 of 10 `500`; revert passes only on 10 of 10 `200`;
  anything else stops the command with what it saw (FR-012).
- If the `web` pod is missing or has no mesh sidecar, the commands refuse
  (FR-006), because the check would mean nothing.

**Rationale**:
- The fault is applied by the *calling* pod's sidecar (the mesh helper
  container next to each shop service), not by ratings. A pod outside the mesh
  went straight past the fault (10 of 10 `200` while it was on), so the check
  must come from a meshed shop pod. `web` is meshed and already has `curl`.
- 100% abort failed every request in every run, so expecting all 10 to agree
  is safe.
- One `exec` with 10 requests inside took 0.6 s against 3.5 s for 10 separate
  `exec` calls, leaving room inside SC-005's 30 s.
- The direct address is used because SC-002 counts requests sent to ratings.
  Requests through web's own proxy (the path shoppers use) failed the same way,
  which is the knock-on failure FR-005 expects.

**Alternatives considered**:
- A separate test pod — rejected: one without a sidecar bypasses the fault
  (shown below), and creating one adds time and clean-up.
- One `kubectl exec` per request — rejected: about 6× slower.
- Web's proxy path `localhost:8080/api/ratings/_health` — behaved identically;
  not chosen, since SC-002 counts requests to ratings itself.

### What was run

web's proxy listens on 8080 and forwards `/api/ratings/` to ratings:

```text
/etc/nginx/conf.d/default.conf:80:    location /api/ratings/ {
/etc/nginx/conf.d/default.conf:81:        proxy_pass http://ratings:80/;
/etc/nginx/conf.d/default.conf-82-    }
```

```text
6:    listen       8080;
37:    # proxy the PHP scripts to Apache listening on 127.0.0.1:80
43:    # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
```

A throwaway pod without a sidecar (`curlimages/curl:8.10.1`, label
`sidecar.istio.io/inject=false`), then 10 requests from each caller with the
fault off, on, and off again, plus timings:

```text
pod/curl-nomesh condition met
containers: curl-nomesh
--- fault OFF
  direct web->ratings      : 200 200 200 200 200 200 200 200 200 200 
  via web proxy            : 200 200 200 200 200 200 200 200 200 200 
  no-sidecar pod->ratings  : 200 200 200 200 200 200 200 200 200 200 
virtualservice.networking.istio.io/ratings patched
--- fault ON
  direct web->ratings      : 500 500 500 500 500 500 500 500 500 500 
  via web proxy            : 500 500 500 500 500 500 500 500 500 500 
  no-sidecar pod->ratings  : 200 200 200 200 200 200 200 200 200 200 
--- timing: 10 separate execs
500 500 500 500 500 500 500 500 500 500 
( for i in $(seq 1 10); do; kubectl exec -n robot-shop deploy/web -c web --  )  1.01s user 0.26s system 36% cpu 3.524 total
--- timing: one exec, 10 requests
500 500 500 500 500 500 500 500 500 500 
kubectl exec -n robot-shop deploy/web -c web -- sh -c   0.09s user 0.03s system 19% cpu 0.629 total
virtualservice.networking.istio.io/ratings patched
--- fault OFF again
  direct web->ratings      : 200 200 200 200 200 200 200 200 200 200 
  via web proxy            : 200 200 200 200 200 200 200 200 200 200 
  no-sidecar pod->ratings  : 200 200 200 200 200 200 200 200 200 200 
pod "curl-nomesh" deleted
```

### Notes and surprises

- The non-mesh result is the trap here: a check from the wrong place would
  report "fault not working" while it works perfectly for the shop.
- The check depends on `curl` being in the upstream `web` image; it is today
  (`/usr/bin/curl`, Finding 1). If a future image drops it, the commands must
  stop with a message rather than misreport.

---

## Finding 4 — Telling this fault apart from ratings really failing (FR-013)

**Question** (Technical Context open item 4): the status command must report
"fault active" only when this fault causes the errors, and say something else
when ratings is failing for another reason. What tells the two apart?

**Decision**: Status looks at two things — whether the ratings rule holds the
fault, and the 10 test answers (Finding 3):

| Rule has the fault? | 10 answers | Status reports |
|---|---|---|
| yes | all `500` with body `fault filter abort` | fault active |
| no | all `200` | fault not active |
| no | any failure | ratings is failing, not because of this fault — plus what it saw |
| yes | anything else | fault is set but not taking effect — plus what it saw |

**Rationale**: The injected error always carried the body `fault filter abort`.
A real outage (ratings scaled to 0 copies) answered `503` with body
`no healthy upstream`. The header `server: envoy` appeared in every case,
healthy ones included, so it cannot be used. Checking the rule as well as the
answers separates "fault set but not working" from "someone else broke it".

**Limits of this finding**:
- **The fault hides a real outage.** With the fault on and ratings down, the
  answers were the same as with ratings healthy (case C). Status cannot see
  through it; revert can, because its own check (FR-012) then expects `200`,
  gets `503`, and stops with what it saw. The guide mentions this.
- **Not tested**: ratings itself answering `500` (for example, its database
  broken). Expected to carry a different body and the
  `x-envoy-upstream-service-time` header (only present when the request
  reached ratings), but not produced here — breaking the database was judged
  too disruptive for planning.
- The mesh has no access logs switched on (below), so the logs' own "fault
  injected" marker is not available; the answer body is the evidence used.

**Alternatives considered**: the `server: envoy` header — rejected, present in
every case; mesh access-log markers — not available on this setup, and turning
them on would change the shared Istio install (out of scope).

### What was run

```text
replicas=1
no accessLog setting in mesh config
```

Three requests plus headers in each state; ratings scaled to 0 copies for the
outage and back to 1 at the end:

```text
=== A: fault ON, ratings UP
fault filter abort [500]
fault filter abort [500]
fault filter abort [500]
server: envoy
=== C: fault ON, ratings DOWN
deployment.apps/ratings scaled
pod/ratings-5c57957c7f-wbcbd condition met
fault filter abort [500]
fault filter abort [500]
fault filter abort [500]
server: envoy
=== B: fault OFF, ratings DOWN
no healthy upstream [503]
no healthy upstream [503]
no healthy upstream [503]
server: envoy
=== restore
deployment.apps/ratings scaled
Waiting for deployment "ratings" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "ratings" rollout to finish: 0 of 1 updated replicas are available...
deployment "ratings" successfully rolled out
{"pdo_connectivity":true} [200]
{"pdo_connectivity":true} [200]
{"pdo_connectivity":true} [200]
server: envoy
x-envoy-upstream-service-time: 10
{"hosts":["ratings"],"http":[{"route":[{"destination":{"host":"ratings"}}]}]}
```

---

## Finding 5 — Which dashboard panels show the errors, and how fast (FR-007, SC-001, SC-003)

**Question** (Technical Context open item 5): on the dashboards the Azure
monitoring setup already installs, where do the ratings errors appear, and do
they appear and clear within the spec's times?

**Decision**: FR-007 is met by existing panels; no dashboard changes. The
guide points presenters at **Application Dashboard → "Non-2xx Responses by
Service"** (the `ratings ->` tile) and **"5xxs"**, and warns that:
- the Istio Service Dashboard's **"Server …"** panels and the ratings logs
  panels stay blank while the fault is on;
- the `user ->` tile is red all the time from normal `404` answers, unrelated
  to this fault.

**Rationale**: The fault stops requests at the calling pod's sidecar, so only
measurements taken on the caller's side (`reporter="source"`) count them.
Measurements taken on ratings' side (`reporter="destination"`) and ratings'
own logs never see the request. Timings with the load generator running:

| Moment | Seen in Prometheus | Spec target |
|---|---|---|
| Start → first ratings `500` counted | t+15 s | SC-001: within 60 s — met |
| Revert → error rate starts falling | t+31 s | SC-003: falling within 60 s — met |
| Revert → error rate back to zero | t+62 s | SC-003: zero within 2 min — met |

The mesh metrics are collected every 15 s (`envoy-stats-monitor`), which
matches the 15 s first-seen time; the Application Dashboard refreshes every
5 s, the Istio Service Dashboard every 1 min.

**Alternatives considered**: adding a panel or alert — out of scope (FR-007,
spec Out of Scope); switching the "Server" panels to the caller's side —
changes a shared dashboard, out of scope.

### What was run

Load generator started from `infra/azure/load-gen/load.yaml`
(`robotshop/rs-load:2.1.0`, `NUM_CLIENTS=10`, `RUN_TIME=1h`); dashboards that
use the mesh request counter:

```text
namespace/loadgen created
deployment.apps/load created
--- dashboards using istio_requests_total
monitoring/dashboards/application.yaml
monitoring/dashboards/istio-service.yaml
```

Relevant panel queries (extracted from the dashboard files):

```text
dashboard: Application Dashboard
 - 5xxs | sum(irate(istio_requests_total{reporter="source", response_code=~"5.*"}[1m]))
 - Non-2xx Responses by Service | increase(istio_requests_total{reporter="source" ,response_code!="200"}[1m])
dashboard: Istio Service Dashboard
 - Client Success Rate (non-5xx responses) | sum(irate(istio_requests_total{reporter=~"$qrep",destination_service=~"$service",response_code!~"5.*"}[5m])) / sum(irate(istio_requests_total{reporter=~"$qrep",destination_service=~"$service"}[5m]))
 - Server Request Volume | round(sum(irate(istio_requests_total{reporter="destination",destination_service=~"$service"}[5m])), 0.001)
 - Server Success Rate (non-5xx responses) | sum(irate(istio_requests_total{reporter="destination",destination_service=~"$service",response_code!~"5.*"}[5m])) / sum(irate(istio_requests_total{reporter="destination",destination_service=~"$service"}[5m]))
```

```text
scrape interval:
['scrape_interval: 30s', 'scrape_interval: 15s', 'scrape_interval: 30s']
application refresh: 5s
istio-service refresh: 1m
```

```text
15s
```
(`kubectl get podmonitor envoy-stats-monitor -n istio-system` — interval.)

Fault on at 17:16:19 (same patch as Finding 1). Prometheus at t+107 s, and
first non-zero `5xx` since then, by reporter:

```text
T0=1791978379 now=1791978486 (t+107s)
--- now, source reporter, ratings, by code+flags
  code=200 flags=- = 0.00/s
  code=500 flags=FI = 0.44/s
  code=503 flags=UH = 0.00/s
--- now, destination reporter, ratings
  code=200 flags=- = 0.00/s
--- first non-zero 5xx since T0-60 (source)
  code=500 flags=FI first>0 at 1791978394 (value 0.27)
  code=503 flags=UH first>0 at None (value 0.00)
--- first non-zero 5xx since T0-60 (destination)
  none
```

(`503 UH` is left over from Finding 4's outage test.) Grafana, seen with
Playwright at 17:18 with the fault on: "5xxs" `0.157 ops/s`; "Non-2xx
Responses by Service" tiles `ratings -> 29.3` (red), `user -> 26.7` (red);
"Global Success Rate" `NaN`; ratings error-log panel showing only routine
`php.INFO` lines.

The `user` tile, checked:

```text
--- user service non-200 (source)
  code=404 flags=- = 20.00/s
--- user 404 before fault (range from 17:05)
  code=404 flags=- first>0 at 1791978435 (value 0.10)
```

Fault off at 17:19:24, polled every ~10 s (`rate` = "5xxs"-style,
`increase` = "Non-2xx" panel):

```text
virtualservice.networking.istio.io/ratings patched
fault OFF at 17:19:24 R0=1791978564
t+10s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.82/s
  code=500 flags=- = 49.33/s
t+21s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.82/s
  code=500 flags=- = 49.33/s
t+31s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.62/s
  code=500 flags=- = 37.33/s
t+41s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.20/s
  code=500 flags=- = 12.00/s
t+52s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.20/s
  code=500 flags=- = 12.00/s
t+62s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+73s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+83s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+94s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+104s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+115s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+125s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
t+136s ratings 500 FI rate[1m] / increase[1m] (Non-2xx panel):
  code=500 flags=- = 0.00/s
  code=500 flags=- = 0.00/s
--- ratings 200 rate now
  code=200 flags=- = 0.76/s
--- user 404 still?
  code=404 flags=- = 14.67/s
```

Load generator then removed:

```text
deployment.apps "load" deleted
```

### Notes and surprises

- **Blank "Server" panels are the trap**: a presenter on the Istio Service
  Dashboard's server-side panels, or on the ratings logs, sees nothing and
  thinks the fault failed.
- **`user ->` tile always red**: `404` from user continued after revert
  (14.67 in the last minute), so it is normal shop traffic, not this fault.
  Does not affect SC-009 (ratings only), but the guide must say to ignore it.
- Prometheus tags each injected error `response_flags="FI"` (fault injected) —
  a second fingerprint alongside the `fault filter abort` body (Finding 4).
- "Global Success Rate" showed `NaN` — a pre-existing panel problem, not
  investigated here.
- **Failed first attempt**: the first polling loop crashed on every line with
  `SyntaxError: unexpected character after line continuation character`
  (backslash escapes inside a Python f-string, not allowed before Python
  3.12). No data was lost; first-seen times were read back from Prometheus'
  history with a range query instead of the live poll.
- The Istio Service Dashboard was checked through its panel queries and
  Prometheus, not by screenshot with the fault on.

---

## Finding 6 — New files go in `infra/azure/scenario-01/`

**Question** (Technical Context open item 6): `scenarios/scenario-01/` may not
change (FR-009), so where do the new script and any supporting files live?

**Decision** (developer's choice, 2026-10-14): `infra/azure/scenario-01/`.
One script there takes `start`, `status` or `revert`; the fault change is a
one-line patch (Findings 1, 3), so no separate routing file is needed. The
make targets that call it are added to `makefile` as Azure-only lines; their
names are settled in Phase 1.

**Rationale**: It follows the existing pattern for Azure copies of shared
folders — `infra/azure/load-gen/` is the Azure copy of `scenarios/load-gen/` —
and leaves everything under `scenarios/` untouched (FR-009, SC-008).
Presenters find it through the two guides, which FR-008 and FR-011 require to
name the commands.

**Alternatives considered**:
- `scenarios/scenario-01-aks/` — easier to browse, but a new naming pattern,
  and `scenarios/README.md` (shared with EKS) would need a line.
- `infra/scripts/cluster/` — holds cluster set-up and tear-down scripts, not
  faults.

### What was run

```text
infra/azure/chart-values/  infra/azure/grafana-postgres/  infra/azure/hotrod/
infra/azure/kiali/  infra/azure/load-gen/
scenarios/load-gen/  scenarios/scenario-01/  scenarios/scenario-02/
scenarios/scenario-03/  scenarios/scenario-04/
```

```text
"infra/azure/scenario-01": No such file or directory (os error 2)
```

None of the files this story will touch (`makefile`, `infra/azure/`,
`agent/tests/azure/`, `docs/aks-explained.md`, `scenarios/README.md`) match a
line in `agent/hooks/protected-paths.txt`.

---

## Quickstart note — health addresses, and `shipping` not ready

While choosing the read-only addresses for quickstart step 6 (SC-002), each
other web service was asked for its health page from the `web` pod, with no
fault active:

```text
http://cart:8080/health 200
http://catalogue:8080/health 200
http://user:8080/health 200
http://payment:8080/health 200
http://shipping:8080/health 503
http://ratings/_health 200
http://localhost:8080/ 200
```

```text
cart               8080                    http
catalogue          8080                    http
dispatch           55555                   headless
mongodb            27017                   mongo
mysql              3306,9104               tcp-mysql,http-metrics
payment            8080                    http
rabbitmq-cluster   5672,15672,15692,4369   tcp-amqp,http-management,http-metrics,tcp-epmd
ratings            80                      http
redis              6379                    redis
shipping           8080                    http
user               8080                    http
web                8080                    http
http://shipping:8080/health -> no healthy upstream [503]
http://shipping:8080/count -> no healthy upstream [503]
http://shipping/health ->  [000]
{"failureThreshold":30,"httpGet":{"path":"/health","port":8080,"scheme":"HTTP"},"initialDelaySeconds":5,"periodSeconds":5,"successThreshold":1,"timeoutSeconds":1}
```

`shipping` was not Ready and had no endpoints; its log shows database errors,
and the database-loading job was stuck on the cities file:

```text
NAME                        READY   STATUS    RESTARTS   AGE   IP             NODE                          NOMINATED NODE   READINESS GATES
shipping-688d885c8c-hv7zd   1/2     Running   0          55m   10.244.2.234   aks-app-19185549-vmss000001   <none>           <none>
NAME       ENDPOINTS   AGE
shipping               55m
  Warning  Unhealthy  52m (x25 over 54m)    kubelet            Readiness probe failed: HTTP probe failed with statuscode: 500
  Warning  Unhealthy  4m36s (x98 over 52m)  kubelet            Readiness probe failed: Get "http://10.244.2.234:15020/app-health/shipping/readyz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

```text
pod/mysql-seeder-xww8d   1/1     Running   0          29m
Checking availability of mysql.robot-shop.svc.cluster.local:3306
Host mysql.robot-shop.svc.cluster.local:3306 is now available!
--------------------------------------------------------
docker-compose-wait - Everything's fine, the application can now start!
--------------------------------------------------------
Seeding is still a WIP
Importing all seed data into DB: 
Adding file: 10-cities.sql
--- shipping first error lines
2026-10-14 11:10:10.311 ERROR 1 --- [           main] com.zaxxer.hikari.pool.HikariPool        : HikariPool-1 - Exception during pool initialization.
java.sql.SQLNonTransientConnectionException: Could not create connection to database server. Attempted reconnect 3 times. Giving up.
```

**What this means for the story**: nothing in Findings 1–5 changes — ratings
answered normally throughout and does not call shipping. But SC-002 (other
services keep answering) and SC-009 (clean setup) can only be judged when
every shop pod is Ready, so the quickstart makes that a prerequisite.

**Not settled**: the first loading job was still running, with 3 restarts,
before Finding 2's reinstall deleted it and started a new one; whether that
reinstall interrupted a load that would have finished cannot be told from what
is left. `shipping` was `2/2` at 16:42 and not Ready by 17:33. The loading job
itself is outside this story.

### Follow-up — cause and in-cluster fix (2026-10-14, 17:36–17:45)

The developer asked for the cause and, if minor, a fix in the cluster only (no
repository change). Two problems, both outside this story:

**1. The database-loading job stalled mid-file.** The seeder's `mysql` client
was alive but idle, its TCP connection still `ESTABLISHED` on its side, while
MySQL had no session for it (MySQL had not restarted). The seed file creates
`cities` first and `codes` after it, so `codes` was empty — which `shipping`
needs.

```text
Id	User	Host	db	Command	Time	State	Info
459	shipping	127.0.0.6:39151	cities	Sleep	530		NULL
...
1091	root	localhost	NULL	Query	0	starting	SHOW FULL PROCESSLIST
table_schema	table_name	table_rows
cities	cities	940974
cities	codes	0
ratings	ratings	9
```

```text
1: bash /opt/seeds/seeder.sh 
10: mysql -h mysql.robot-shop.svc.cluster.local -u root 
{"limits":{"cpu":"200m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"500Mi"}}
NAME                 CPU(cores)   MEMORY(bytes)   
mysql-seeder-xww8d   0m           1Mi
```

```text
mysql restarts=0 last= at 
Uptime	3380
Aborted_clients	0
Aborted_connects	0
```

```text
22:CREATE DATABASE IF NOT EXISTS cities;
28:DROP TABLE IF EXISTS `cities`;
122:DROP TABLE IF EXISTS `codes`;
140:INSERT INTO `codes` VALUES (26,'au','Australia'),...
lines: 153
--- seeder tcp (state 01=ESTABLISHED)
486B000A:0CEA 01
```

The `ratings` database (created by the *second* seed file) already existed, so
the first loading job had most likely completed; Finding 2's reinstall then
started a new job that dropped and began reloading `cities`/`codes` and
stalled. Likely, not proven.

**Fix**: re-ran the same seed file inside `mysql-0` over its local socket.
A first attempt piped the file through `kubectl exec … cat` and failed:

```text
ERROR 1064 (42000) at line 113: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near ''ha' at line 1
cities	924711
codes	25
```

because that pipe corrupts a 64 MB stream — checksums differed:

```text
278e03c7cd5d9249998dac728878c4c4  /opt/seeds/10-cities.sql
3b182a855aeb6469b0b2b86ebfcbba95  .../seed-dl/10-cities.sql
```

`kubectl cp` copied it intact (`278e03c7…` locally and inside `mysql-0`), and
the import from the local file ran clean in 1 min 45 s:

```text
278e03c7cd5d9249998dac728878c4c4  /tmp/10-cities.sql
17:40:55
mysql exit=1
17:42:40
cities	948833
codes	25
```

(`exit=1` is `grep` finding no error lines to print, not MySQL.) The stuck job
was then deleted, as `make setup-robot-shop` does on every run.

**2. `shipping` was starved of CPU.** Its container sat at its 200m limit; the
Java service never answered within its readiness probe's 1 s.

```text
{"limits":{"cpu":"200m","memory":"2Gi"},"requests":{"cpu":"100m","memory":"1Gi"}}
shipping-688d885c8c-hv7zd   shipping      200m         1018Mi
```

Node had room (requests 1040m of 1900m). Raised in the cluster only to
request 500m / limit 1000m CPU:

```text
deployment.apps/shipping resource requirements updated
deployment "shipping" successfully rolled out
kubectl rollout status deploy shipping -n robot-shop --timeout=480s  0.08s user 0.02s system 0% cpu 43.806 total
shipping-5b487b7f6b-w8jpd   shipping      986m         385Mi
/health 200 0.018336s
/codes 200 0.378538s
```

All shop pods Ready afterwards, and every web service 10 of 10 `200`:

```text
http://ratings/_health        200 200 200 200 200 200 200 200 200 200 
http://cart:8080/health       200 200 200 200 200 200 200 200 200 200 
http://catalogue:8080/health  200 200 200 200 200 200 200 200 200 200 
http://user:8080/health       200 200 200 200 200 200 200 200 200 200 
http://payment:8080/health    200 200 200 200 200 200 200 200 200 200 
http://shipping:8080/health   200 200 200 200 200 200 200 200 200 200 
```

**Limits**: both fixes live only in this cluster. A fresh `make setup-aks`
installs shipping with 200m again (`app/robot-shop/helm/values.yaml:199-207`)
and runs the same loading job. Candidates for a follow-up story, not this one.

## Pre-check note — the `web` sidecar is an init container (data-model §5 #6)

**Question** (raised by `/speckit-analyze`, 2026-10-14): pre-check 6 asks
whether the `web` pod is in the mesh by looking for an `istio-proxy`
container. Where does that container appear in the pod spec on this cluster?

### What was run

2026-10-14 18:18:09 IST, cluster `sre-stack-452138`:

```text
$ kubectl get pod -n robot-shop -l service=web -o jsonpath='{range .items[*]}{.metadata.name} phase={.status.phase} containers={.spec.containers[*].name} init={.spec.initContainers[*].name} proxyRestart={.spec.initContainers[?(@.name=="istio-proxy")].restartPolicy} ready={.status.initContainerStatuses[?(@.name=="istio-proxy")].ready}{"\n"}{end}'
web-755f4b88b8-h75tr phase=Running containers=web init=istio-init istio-proxy proxyRestart=Always ready=true
```

**Decision**: pre-check 6 looks for a container named `istio-proxy` in
`.spec.initContainers` or `.spec.containers`. Istio injects the sidecar here
as a *native sidecar*: an init container with `restartPolicy: Always`, which
keeps running beside the app. `.spec.containers` holds only `web`, so a check
of that list alone would refuse every command (exit 3).

**Rationale**: checking both lists works with either injection mode, so the
check does not depend on how a given Istio install is configured. `kubectl get
pods` still shows `2/2` because the native sidecar is counted as ready.
