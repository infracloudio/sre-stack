# Research: Slow Database Fault for the Demo Shop on Azure

Live run against AKS cluster `sre-stack-452138` (southindia), kube context `sre-stack-452138`, namespace `robot-shop`, 2026-10-22. Every output block below is pasted from the terminal. Findings are added one at a time, each approved by the developer before the next (constitution principles VIII and IX).

## Finding 1 — Which services use the MySQL database (Technical Context question 7)

**Question.** Does anything other than ratings and shipping use MySQL? (FR-005, spec Assumptions.)

**Run 1 — Services, then each Deployment's first-container env vars** (`kubectl get svc -n robot-shop`, then `kubectl get deploy <name> -n robot-shop -o jsonpath=...` per Deployment). The `mysql` Service line:

```
mysql              ClusterIP   10.0.107.72    <none>        3306/TCP,9104/TCP                       8d
```

Env vars:

```
== cart
== catalogue
== dispatch
AMQP_HOST=rabbitmq-cluster
== payment
AMQP_HOST=rabbitmq-cluster
== ratings
PDO_URL=mysql:host=mysql.robot-shop.svc.cluster.local;dbname=ratings;charset=utf8mb4
== shipping
JAVA_OPTS=-Xms1000M -Xmx2000M
DB_HOST=mysql.robot-shop.svc.cluster.local
== user
== web
```

**Run 2 — live connections inside `mysql-0`, grouped by user** (`information_schema.processlist`, run with `kubectl exec -n robot-shop mysql-0 -c mysql`):

```
mysql: [Warning] Using a password on the command line interface can be insecure.
user	client_ip	db	n
root	localhost	NULL	1
shipping	127.0.0.6	cities	10
```

**What it shows.** Only `ratings` (database `ratings`) and `shipping` (database `cities`) name the MySQL host. `cart`, `catalogue` and `user` carry no MySQL setting. The only application connections at the time of the query were from the MySQL user `shipping`.

**Limits and surprises.**
- Ratings was not in the connection list. It opens a connection per request, so it was not connected at that moment; it is confirmed by its env var only.
- Every client IP is `127.0.0.6`: the mesh sidecar rewrites the source address, so IP cannot say which pod connected. `shipping` was identified by MySQL user name only.
- `grep -i mysql .env` finds only `RDS_MYSQL_*` settings (the EKS database), none for the in-cluster one. The in-cluster password was read from `${MYSQL_ROOT_PASSWORD}` inside the pod and not printed.
- No `VirtualService` or `DestinationRule` exists for `mysql` in `robot-shop`; the nine `VirtualService` objects are all for HTTP services (cart, catalogue, mongodb, payment, ratings, redis, robotshop, shipping, user). Whether Istio HTTP fault injection can apply to MySQL's plain TCP traffic is untested here (carried to a later finding).

**Result.** Spec assumption holds: ratings and shipping are the database's users. Test requests go through exactly those two paths.

## Finding 2 — Normal speed of the two database-dependent requests today (Technical Context question 3)

**Question.** How fast do ratings and shipping answer now, with no fault? "Slow" in the spec means at least 2 s slower than this (spec §3).

**Run.** From inside the `web` container (the route the story 006 script uses), 10 requests each with `curl -s -o /dev/null -m 15 -w "%{http_code} %{time_total}\n"`:

```
ratings /api/fetch/HAL-1
200 0.023771
200 0.027645
200 0.016003
200 0.026982
200 0.019510
200 0.027155
200 0.021665
200 0.027639
200 0.021212
200 0.021702
shipping /match/de/ber
200 0.817546
200 0.698320
200 0.780673
200 0.794073
200 0.692790
200 0.790054
200 0.794858
200 1.199596
200 0.899789
200 1.084199
shipping /calc/52.5,13.4
400 0.009720
400 0.005245
400 0.005481
400 0.109779
400 0.012264
```

**What it shows.**
- Ratings: all `200`, 0.016 to 0.028 s (spec says about 0.02 s).
- Shipping `/match/de/ber`: all `200`, 0.69 to 1.20 s, typically about 0.8 s. Slightly wider than the spec's 0.4 to 0.9 s; 2 of 10 samples were above 1.0 s. "Slow" for shipping therefore means roughly 3 s or more.

**Failure recorded.** My first guess at the shipping route, `/calc/52.5,13.4`, returned `400` every time in about 0.01 s: a bad request from a guessed path, not a database call. Not used. `/match/de/ber` reads the `cities` table and is the shipping test request.

**Limits.** 10 samples each, one moment, one pod. The script must compare each request to a baseline taken just before the start, as the spec defines.

**Result.** Test requests: ratings `GET /api/fetch/HAL-1`, shipping `GET /match/de/ber`.

**Correction, 2026-10-22 (found during Finding 9).** `HAL-1` is not a product in this shop (real SKUs from `http://catalogue:8080/products` include `Watson`, `Ewooid`, `HPTD`, `UHJ`). `GET /api/fetch/HAL-1` returned `{"avg_rating":0,"rating_count":0}` and left no statement in the database's statement summary, so the ratings numbers in this finding (0.016 to 0.028 s) are not database times. Also, the project's load generator (Deployment `load`, namespace `loadgen`, 1 replica) was running during this finding and Findings 4 and 5; it was not checked at the time. The shipping numbers stand: a control run with the load generator at 0 replicas gave 0.60 to 0.89 s (Finding 8).

## Finding 3 — What the database and its mesh setup allow (Technical Context question 1, first half)

**Question.** Which slowdown mechanisms are possible here? Read-only checks; nothing on the cluster was changed.

**Run 1 — MySQL version and settings** (`mysql` container in `mysql-0`):

```
VERSION()
5.7.35
Variable_name	Value
init_connect	
Variable_name	Value
max_connections	151
```

**Run 2 — pod annotations, container security settings, Service ports:**

```
{"istio.io/rev":"default", ... "sidecar.istio.io/status":"{\"initContainers\":[\"istio-init\",\"istio-proxy\"],\"containers\":null, ...,\"revision\":\"default\"}"}
(StatefulSet: securityContext, command, args all empty)
[{"name":"tcp-mysql","port":3306,"protocol":"TCP","targetPort":3306},{"name":"http-metrics","port":9104,"protocol":"TCP","targetPort":9104}]
```

**What it shows.**
- MySQL is 5.7.35. `SET PERSIST` does not exist in 5.7, so a `SET GLOBAL` change is lost when the pod restarts (FR-003, SC-013). The developer was offered relaxing FR-003/SC-013 and chose to keep them (2026-10-22).
- `init_connect` is empty. Setting it to run `DO SLEEP(n)` would delay each new connection, not each query. Ratings opens a connection per request, so it would slow; shipping keeps about 10 connections open (Finding 1), so it would barely notice.
- The Service port is named `tcp-mysql`, protocol TCP: Istio treats it as plain TCP. Story 006's `fault.abort` on an HTTP `VirtualService` does not carry over; a `fault.delay` has the same HTTP-only limit.
- The Istio sidecar is an init container (`initContainers: istio-init, istio-proxy`). The StatefulSet has no `command`, `args` or `securityContext`.

**Failure recorded.** My `jsonpath` for the `istio-proxy` image returned an empty line because it looked under `containers`; the proxy is under `initContainers`. Not re-run.

**Result.** Three routes stay open, none proven: (1) a TCP-level delay at the sidecar, which Istio does not offer in `VirtualService`; (2) a small delay proxy in front of MySQL with the Service pointed at it, which adds a workload; (3) a per-connection delay inside MySQL, which fails for shipping and for restart.

## Finding 4 — Lowering MySQL's CPU limit (Technical Context question 1, second half)

**Question.** The developer asked for the slowdown to come from inside the database (not the network, not an error), and ruled out the delay proxy. Can a lower CPU limit on the `mysql` container slow ratings and shipping without errors, and without a restart?

**Read-only facts first.** The `mysql` container already has a limit; the chart builds it from `.Values.mysql.resources` (`app/robot-shop/helm/templates/mysql-statefulset.yaml:39`):

```
mysql {"limits":{"cpu":"200m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"700Mi"}}
mysql-exporter {}
----
20000 100000
----
mysql-0   mysql            37m          524Mi
----
COUNT(*)
948833
innodb_thread_concurrency   0
innodb_buffer_pool_size     134217728
```

(`20000 100000` is `/sys/fs/cgroup/cpu.max` in the container: 20 ms of CPU per 100 ms.) Lowering `max_connections` was ruled out in reasoning, not run: MySQL answers extra connections with an error, which breaks SC-002.

**Failed attempts (the cluster was unchanged by both).**

Attempt 1, `kubectl patch pod mysql-0 --subresource resize --type merge` (limit only):

```
The Pod "mysql-0" is invalid: 
* spec.containers[0].image: Required value
* spec.containers: Forbidden: containers may not be added or removed on resize
```

Attempt 2, `--type strategic`, limit 50m, request left at 100m:

```
The Pod "mysql-0" is invalid: spec.containers[0].resources.requests: Invalid value: "100m": must be less than or equal to cpu limit of 50m
```

The "50m" probes of these two attempts ran against the unchanged 200m and are not results. In both, `cpu.max` still read `20000 100000` and restarts were `0`.

**Baseline** (limit 200m, taken just before attempt 1):

```
ratings 200 0.020386
ratings 200 0.026880
ratings 200 0.016525
ratings 200 0.088565
ratings 200 0.020306
shipping 200 0.675951
shipping 200 0.790248
shipping 200 0.887770
shipping 200 0.902345
shipping 200 0.890894
```

**Run A — request and limit lowered together, in place (`--type strategic`).** First step, 50m:

```
pod/mysql-0 patched
5000 100000
restarts=0 ready=true
ratings 200 0.718597
ratings 200 0.791912
ratings 200 1.191870
ratings 200 1.294974
ratings 200 0.990428
shipping 200 17.994171
shipping 000 30.001223
shipping 000 30.001563
shipping 000 30.001183
shipping 000 30.001421
command terminated with exit code 28
```

Then 20m:

```
pod/mysql-0 patched
2000 100000
restarts=0 ready=true
ratings 200 1.380755
ratings 200 1.295903
ratings 200 0.793578
ratings 200 1.391043
ratings 200 2.494993
shipping 000 30.000244
shipping 000 30.000798
shipping 000 30.000102
shipping 000 30.000795
shipping 000 30.000439
command terminated with exit code 28
```

Restored immediately to request 100m / limit 200m. Right after the restore, MySQL was still working through the scans that timed-out clients had abandoned:

```
pod/mysql-0 patched
20000 100000
restarts=0 ready=true {"limits":{"cpu":"200m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"700Mi"}}
running
10
== probe after restore
ratings 200 0.566737
ratings 200 0.387755
ratings 200 0.082696
ratings 200 0.389185
ratings 200 0.295468
shipping 200 6.495880
shipping 200 3.273568
shipping 200 4.298220
shipping 200 1.179787
shipping 200 1.191308
```

After the backlog drained (polled `information_schema.processlist`: `busy queries: 0`), the pod was back to baseline:

```
ratings 200 0.016705
ratings 200 0.045571
ratings 200 0.013394
ratings 200 0.018236
ratings 200 0.018288
shipping 200 0.791355
shipping 200 1.182461
shipping 200 0.894630
shipping 200 0.789459
shipping 200 0.895793
```

**Run B — stepped 100m, 85m, 70m** (6 requests each, client timeout 12 s, automatic restore on exit, stop on first shipping timeout):

```
== request+limit 100m
pod/mysql-0 patched
10000 100000
ratings 200 0.064502
ratings 200 0.026004
ratings 200 0.028373
ratings 200 0.014883
ratings 200 0.020541
ratings 200 0.079358
shipping 200 1.979103
shipping 200 3.485542
shipping 200 10.795666
shipping 200 10.088511
shipping 200 4.993849
shipping 200 7.796117
== request+limit 85m
pod/mysql-0 patched
9000 100000
ratings 200 0.124623
ratings 200 0.085018
ratings 200 0.093506
ratings 200 0.093764
ratings 200 0.028573
ratings 200 0.049008
shipping 200 2.299660
shipping 200 2.296658
shipping 200 4.881133
shipping 200 7.694795
shipping 200 2.392968
shipping 200 3.388520
== request+limit 70m
pod/mysql-0 patched
7000 100000
ratings 200 0.362925
ratings 200 0.286290
ratings 200 0.691821
ratings 200 0.892436
ratings 200 0.495929
ratings 200 0.791238
shipping 200 6.973545
shipping 000 12.000301
shipping 000 12.001648
shipping 000 12.001053
shipping 000 12.001383
shipping 000 12.001038
command terminated with exit code 28
shipping timed out at 70m, stopping
== restored
20000 100000
restarts=0 {"limits":{"cpu":"200m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"700Mi"}}
```

**What it shows.**
- In-place CPU resize works with no restart (`restarts=0`, `ready=true` throughout), as long as request and limit are lowered together and restored together (original: request 100m, limit 200m). The StatefulSet spec was not touched, so a pod restart would bring 200m back; surviving a restart (FR-003) needs the StatefulSet spec edited as well.
- Ratings and shipping do not react alike. Shipping scans `cities` (948,833 rows) and needs far more CPU than ratings. At 85m all 6 shipping requests were 2.3 to 7.7 s (inside the spec's 2 to 10 s window) and ratings stayed under 0.13 s. At 100m two of 6 shipping requests passed 10 s. At 70m shipping failed 5 of 6 while ratings was 0.29 to 0.89 s (4 of 6 above 0.5 s). No single limit puts both paths in their windows.
- Surprise: 85m printed `9000 100000` (90 ms), not 8500. Why the limit is rounded was not investigated.
- Slow requests abandoned by timed-out clients keep running in MySQL after the client gives up. After restore, shipping took 1.2 to 6.5 s until the 10 queued scans finished (under two minutes). This matters for SC-004's 10-second revert target.

**Limits.** 6 samples per step; one moment; one pod.

**Decision (developer, 2026-10-22): option 1.** Shipping is the visible slow path, at about 85m. Ratings is not slowed. Spec edits this implies (FR-001, SC-001/002/003/004 test requests, §3 "normal"/"slow" definition, user stories 1 and 2, EC-007) are proposed separately and go through the spec gate again.

**Correction, 2026-10-22.** The ratings requests in this finding used the non-existent SKU `HAL-1` (see the correction under Finding 2), so they never reached the database. What the ratings numbers here show is not database behaviour. The load generator was also running. Option 1 (shipping only) was chosen on this premise; it was later replaced by Finding 9.

## Finding 5 — Bigger sample at 85m and 90m

**Question.** Finding 4 had 6 requests per step. Is there a stable CPU limit where shipping stays in the spec's 2 to 10 s window?

**Run.** In place, request and limit set together; 10 ratings and 20 shipping requests per step, one after another from the `web` container, client timeout 15 s (`000` means the client gave up at 15 s, not that the shop returned an error). The limit was restored and the query backlog drained (polled `information_schema.processlist`) after each step.

```
== request+limit 85m
pod/mysql-0 patched
9000 100000
ratings 200 0.049677
ratings 200 0.092997
ratings 200 0.194406
ratings 200 0.031044
ratings 200 0.151412
ratings 200 0.093529
ratings 200 0.012386
ratings 200 0.075973
ratings 200 0.091736
ratings 200 0.086655
shipping 200 3.602086
shipping 200 4.187996
shipping 200 4.791397
shipping 200 9.895982
shipping 200 13.988935
shipping 200 2.595864
shipping 200 4.491414
shipping 200 13.892977
shipping 000 15.001925
shipping 000 15.001093
shipping 000 15.001308
shipping 000 15.000999
shipping 200 8.461033
shipping 200 3.182463
shipping 200 3.490462
shipping 200 7.393326
shipping 200 12.190198
shipping 200 11.597420
shipping 200 13.593579
shipping 200 10.991650
summary: ratings>0.5s=0/10 shipping n=20 errors=4 under2s=0 over10s=6
-- restored, draining
== request+limit 90m
pod/mysql-0 patched
9000 100000
ratings 200 0.022197
ratings 200 0.035607
ratings 200 0.088117
ratings 200 0.094503
ratings 200 0.292308
ratings 200 0.097982
ratings 200 0.073517
ratings 200 0.094569
ratings 200 0.093403
ratings 200 0.091579
shipping 200 2.904602
shipping 200 7.578023
shipping 200 7.093686
shipping 200 2.597993
shipping 200 3.591730
shipping 200 3.495246
shipping 200 9.694841
shipping 200 5.991544
shipping 200 7.395460
shipping 200 3.095240
shipping 200 4.392161
shipping 200 8.892108
shipping 200 10.388385
shipping 200 12.592208
shipping 200 3.627012
shipping 200 2.647392
shipping 200 6.496348
shipping 200 9.292744
shipping 200 6.699597
shipping 200 3.995005
summary: ratings>0.5s=0/10 shipping n=20 errors=0 under2s=0 over10s=2
-- restored, draining
20000 100000
restarts=0 {"limits":{"cpu":"200m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"700Mi"}}
```

**Timeout check, read-only.** `/etc/nginx/conf.d/default.conf` in `web` proxies `/api/shipping/` to `http://shipping:8080/` and `/api/ratings/` to `http://ratings:80/`; the grep for `timeout` printed no timeout line. `VirtualService` `shipping` and `ratings` printed no `timeout` and no `retries`.

**What it shows.**
- 85m and 90m both print `9000 100000`: the container ran at 90 ms of CPU per 100 ms in both. The requested value is rounded to a 10 ms step. (Why was not investigated.)
- At the same effective limit the two runs differed a lot: the first had 4 client timeouts and 6 requests above 10 s out of 20; the second had none timed out and 2 above 10 s. Shipping times at 90 ms spread from 2.6 to 12.6 s. Finding 4's "6 of 6 inside 2 to 10 s" at 85m did not repeat.
- Every shipping request that completed at 90 ms took longer than 2 s (20 of 20, minimum 2.6 s). Ratings stayed under 0.3 s (0 of 10 above 0.5 s).
- No nginx or mesh timeout was found on the shipping path, so a slow answer is probably still a successful answer in the shop. The shipping application's own timeout was not checked.

**Limits.** Two runs of 20; one moment; the first run's four timeouts may reflect how long the pod had been under load. Not repeated.

**Decision (developer, 2026-10-22).** Keep the CPU lever at the effective 90 ms. "Slow" means the shipping lookup takes longer than 2 seconds; there is no need for the 10 s upper bound or a 10-of-10 pass rate. The spec edits are proposed separately and go through the spec gate.

**Correction, 2026-10-22.** The ratings requests used the non-existent SKU `HAL-1`, and the load generator was running (see the corrections under Findings 2 and 4). The shipping numbers were repeated with the load generator off in Finding 8 and the collapse under overlapping traffic is the same. The decision above was superseded by Finding 9.

## Finding 6 — A shop re-deploy leaves the in-place limit alone (Technical Context question 4, EC-002)

> **Superseded, 2026-10-22.** This finding is about the in-place CPU limit, which was dropped (Findings 8 and 9). What a shop re-deploy does to the Rewriter rules is **not tested yet**: the deploy re-creates the seeder job and reloads the data, but whether the `query_rewrite` schema and the rules survive is open. The seeder facts below still hold.

**Question.** Does re-running the shop's deploy put MySQL's CPU limit back and so clear the fault?

**Read-only facts first.** The AKS branch of `setup-robot-shop` runs `kubectl delete job mysql-seeder -n $(APP_NS) --ignore-not-found`, then `helm upgrade --install $(APP_RELEASE_NAME) -n $(APP_NS) --create-namespace ./app/robot-shop/helm/ --values ./infra/azure/chart-values/robot-shop.yaml --set stack_mode=$(STACK_MODE) --set mysql_root_password=… --wait --timeout $(LOCAL_APP_SETUP_TIMEOUT)` (`LOCAL_APP_SETUP_TIMEOUT=10m0s`, `.env:19`). The seeder is a plain `Job` in the chart (`app/robot-shop/helm/templates/mysql-seeed-job.yaml`), not a Helm hook. Its import script drops and recreates each table it loads. The makefile delete-line was added by story 004 (`git log -S"delete job mysql-seeder"`: `3a477c1`). Helm's copy of the `mysql` StatefulSet shows the same values as the pod template (200m / 100m):

```
resources:
    limits:
      cpu: 200m
      memory: 1024Mi
    requests:
      cpu: 100m
      memory: 700Mi
----
{"rollingUpdate":{"partition":0},"type":"RollingUpdate"} gen=3 obs=3
mysql-798d94d666
mysql-798d94d666 mysql-798d94d666
```

**Run.** Limit set in place to 90m, then the same `helm upgrade` as the target, without the Job delete (so the seeder was not re-run):

```
== before: set 90m
pod/mysql-0 patched
9000 100000
NAME           STATUS     COMPLETIONS   DURATION   AGE
mysql-seeder   Complete   1/1           2m7s       131m
== helm upgrade (same args as make setup-robot-shop, no job delete)
Release "roboshop" has been upgraded. Happy Helming!
NAME: roboshop
LAST DEPLOYED: Thu Oct 22 19:10:55 2026
NAMESPACE: robot-shop
STATUS: deployed
REVISION: 14
TEST SUITE: None
== after upgrade
NAME    	NAMESPACE 	REVISION	UPDATED                                	STATUS  	CHART           	APP VERSION
roboshop	robot-shop	14      	2026-10-22 19:10:55.170542727 +0530 IST	deployed	robot-shop-1.1.0	           
9000 100000
restarts=0 age=2026-10-22T11:53:34Z {"limits":{"cpu":"90m","memory":"1Gi"},"requests":{"cpu":"90m","memory":"700Mi"}}
mysql-0                      3/3     Running   0          107m
```

(All other pods kept their ages; the release is now at revision 14 because of this test.) The limit was restored to 200m/100m afterwards (`20000 100000`, `restarts=0`).

**Quirk recorded.** Right after the restore, shipping took 2.76, 4.09 and 2.29 s; a minute later, with 0 busy queries, 0.69 to 1.42 s (the last 12 of 15 requests were under 1.0 s).

**What it shows.**
- A `helm upgrade` with an unchanged chart leaves the pod's in-place CPU limit alone and restarts nothing. So a shop re-deploy does not clear the fault.
- The full `make setup-robot-shop` was not run, because its seeder step drops and reloads tables including `cities` (948,833 rows), which would take much longer with MySQL at 90 ms and leave data incomplete meanwhile. So "the fault survives" is shown for the Helm upgrade only, not for the whole make target.
- The seeder re-runs on every deploy because a Job's spec cannot be updated by `helm upgrade`, so the makefile deletes it first. Stopping the re-run means changing the shared chart or target, which is out of scope here (FR-013); to be filed as its own story.

**Result.** EC-002 answer: the fault stays on through a re-deploy, but the deploy reloads the data. Presenters revert first. The guide says so.

## Finding 7 — How status tells this fault from other slowness (Technical Context question 5)

> **Superseded, 2026-10-22.** The four states below were built on the pod annotation and the live CPU limit, both dropped (Findings 8 and 9). With the Rewriter the on/off state is the `enabled` column and `Rewriter_number_loaded_rules` (Findings 9, 10 and 12). Status still has to be redesigned around those; what status can read from the shop and the dashboards below still holds.

**Question.** What can status read to tell "our fault" from "the database is slow for another reason" (FR-009, EC-007)?

**Read-only facts first.** The story 007 script marks its fault with an annotation on the cart Deployment: set at `infra/azure/scenario-02/cart-oom-kill.sh:227`, removed at `:280`, read at `:68–78`, and a classifier at `:109–120` combines "marker present" with "live value differs from the release" into four states. What the `mysql-0` pod exposes with the fault off:

```
annotations: {"istio.io/rev":"default", ... "sidecar.istio.io/status":"{...}"}   (no sre-stack/... marker)
spec resources: {"limits":{"cpu":"200m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"700Mi"}}
conditions: PodReadyToStartContainers, Initialized, Ready, ContainersReady, PodScheduled  (all "True", observedGeneration 14)
status.resize: (empty)
allocatedResources: {"cpu":"100m","memory":"700Mi"}
```

**Run.** Marker annotation added to the pod, in-place resize to 90m, then everything restored:

```
== annotate
pod/mysql-0 annotated
active restarts=0
== resize to 90m
pod/mysql-0 patched
spec:   90m
status: 90m
cgroup: 9000 100000
marker: active
== restored
spec:   200m
marker: []
restarts=0
```

**What it shows.**
- A pod annotation can be added and removed with `kubectl annotate` without a restart.
- During an in-place resize, `spec.containers[mysql].resources.limits.cpu`, the container status and `cpu.max` agree. Status can compare the pod's `spec` limit with the StatefulSet template (`kubectl get sts mysql`), which matched Helm in Finding 6.
- A marker on the pod disappears when the pod is recreated, together with the in-place limit, which fits the relaxed FR-003. A marker on the StatefulSet would outlive the pod and make status wrong after a restart.

**Result.** Four states from marker x live limit:

| Marker | Live limit vs template | Status says |
|---|---|---|
| yes | lowered | fault active |
| no | same | fault not active |
| yes | same | not active; leftover marker (revert clears it) |
| no | lowered | CPU limit changed by something else, not this fault |

For EC-007, with no marker and a normal limit, status also sends a few shipping test requests and reports "not active, but shipping is slow for another reason" when they take longer than 2 s.

## Finding 8 — Lowering the CPU limit under overlapping traffic (supersedes the CPU-limit conclusions of Findings 4 and 5)

**Question.** Finding 5 sampled one request at a time. Does the CPU limit still give "slow but answering" when requests overlap, as they do with the shop's load generator? Is 100m or 120m any better than 90m?

**Method.** In-place resize of `mysql-0` (request and limit set together, restored afterwards, `restarts=0` each time). Pattern: for 4 minutes, one shipping `/match/de/ber` and one ratings `/api/fetch/HAL-1` request every 2 s (the shipping request in the background, so they overlap), client timeout 40 s. Prometheus queried at the end of the window (`http://20.235.19.12/prometheus`). Script: `fault-run.sh` in the session scratchpad.

**Run 1 — 90m, load generator running** (the first overlapping run, run before the check below):

```
fault on at 14:10:23 UTC
== during fault (end of 4 min window)
threads_running success [('mysql-0', 11.0)]
threads_running_max4m success [('mysql-0', 11.0)]
qps success [('mysql-0', 6.333)]
slow_queries_4m success [('mysql-0', 0.0)]
shipping_p90_ms success [('', 57000.0)]
ratings_p90_ms success [('', 566.667)]
throttled_by_container success [('mysql-0', 0.0), ('mysql-0', 9.985)]
cpu_usage success [('mysql-0', 0.004), ('mysql-0', 0.085), ('mysql-0', 0.004), ('mysql-0', 0.093)]
== restored: 200m marker=[]
traffic: shipping n=100 timeouts=89 over2s=11 ratings n=100 over0.5s=26
```

Backlog after restore: `busy=10`, `busy=10`, `busy=0` (about 5 minutes after the fault ended), then shipping 0.79 to 0.81 s.

**Run 2 — 100m then 120m** (automatic step-up on any timeout; load generator still running):

```
=== level 100m: fault on at 14:18:58 UTC
pod/mysql-0 patched
cpu.max: 10000 100000
--- Prometheus at end of window (14:23:43 UTC)
threads_running success [('mysql-0', 11.0)]
threads_running_max4m success [('mysql-0', 11.0)]
qps success [('mysql-0', 5.333)]
shipping_p90_ms success [('', 56760.0)]
ratings_p90_ms success [('', 800.0)]
throttled_by_container success [('mysql-0', 0.0), ('mysql-0', 10.025)]
--- traffic
shipping n=101 timeouts=87 over2s=14 over10s=14 max_ok=37.9872 | ratings n=101 over0.5s=25
restored: 200m marker=[] restarts=0
14:23:48 busy=10
14:24:10 busy=10
14:24:30 busy=0
failures at 100m, trying 120m
=== level 120m: fault on at 14:24:30 UTC
pod/mysql-0 patched
cpu.max: 12000 100000
--- Prometheus at end of window (14:29:15 UTC)
threads_running success [('mysql-0', 11.0)]
threads_running_max4m success [('mysql-0', 11.0)]
qps success [('mysql-0', 5.5)]
shipping_p90_ms success [('', 56162.791)]
ratings_p90_ms success [('', 835.0)]
throttled_by_container success [('mysql-0', 0.0), ('mysql-0', 9.997)]
--- traffic
shipping n=102 timeouts=68 over2s=33 over10s=30 max_ok=39.882 | ratings n=102 over0.5s=18
restored: 200m marker=[] restarts=0
14:29:20 busy=10
14:29:40 busy=0
=== done
```

**Mistake found, recorded.** Before this finding I told the developer the load generator was not running without checking. It was: `kubectl get deploy,pods,jobs -A | grep -i load` showed `loadgen deployment.apps/load 1/1 1 1 7d23h` and `pod/load-cb796c98b-h4jvz 1/1 Running 2 (39m ago) 166m`. It is `robotshop/rs-load:2.1.0` with 10 users (`infra/azure/load-gen/load.yaml:27`). It was scaled to 0 (`kubectl scale deploy/load -n loadgen --replicas=0`) at the developer's request, and runs 1 and 2 above and Findings 2 to 5 had its traffic in them.

**Run 3 — control and 90m with the load generator off** (200m control first, then the fault; 90m prints `9000 100000`):

```
=== control at 200m, no fault, no load generator (sequential)
shipping 200 0.785235
shipping 200 0.695353
shipping 200 0.602895
shipping 200 0.885430
shipping 200 0.781753
shipping 200 0.805333
ratings 200 0.023026
ratings 200 0.019729
ratings 200 0.019578
=== control at 200m, overlapping pattern, 2 minutes
control shipping n=57 timeouts=0 over2s=0 max_ok=1.19208 | ratings n=57 over0.5s=0
14:36:06 busy=0
=== level 90m: fault on at 14:36:06 UTC
pod/mysql-0 patched
cpu.max: 9000 100000
--- Prometheus at end of window (14:40:50 UTC)
threads_running success [('mysql-0', 11.0)]
threads_running_max4m success [('mysql-0', 11.0)]
qps success [('mysql-0', 3.7)]
shipping_p90_ms success [('', 57000.0)]
ratings_p90_ms success [('', 495.833)]
throttled_by_container success [('mysql-0', 0.0), ('mysql-0', 10.006)]
--- traffic
shipping n=100 timeouts=74 over2s=26 over10s=19 max_ok=39.7881 | ratings n=100 over0.5s=30
restored: 200m marker=[] restarts=0
14:41:00 busy=11
14:41:21 busy=4
14:41:42 busy=0
=== done
```

**Read-only observations in this finding.** `long_query_time` is `10.000000` and `slow_query_log` is `OFF`, so `mysql_global_status_slow_queries` stayed at 0 under the fault. Installed Database dashboard panels that moved: "MySQL Client Thread Activity" (threads running 1 to 11), "Current QPS" (17.5 to 3.7 to 6.6 depending on run). No panel plots CPU throttling (`grep` of `monitoring/dashboards/mysql.yaml`: its resource panel is memory only).

**What it shows.**
- The load generator was not the cause. The same overlapping pattern at 200m is clean (0 of 57 timed out, slowest 1.19 s); at 90m with the load generator off, 74 of 100 timed out (it was 89 of 100 with it on).
- A lower CPU limit gives a cliff, not a slope: 120m still had 68 of 102 shipping requests time out, 100m had 87 of 101, 90m had 74 to 89 of 100. A usable band, if any, lies between 120m and 200m. It was not searched.
- After the fault ends the queue takes up to about 5 minutes to clear (`busy=10` at 14:15:27 and 14:15:48, `busy=0` at 14:16:09).
- The "ratings" numbers in these runs are not database times (see the correction under Finding 2).

**Result.** The CPU-limit lever was dropped.

## Finding 9 — A fixed sleep added by MySQL's Rewriter plugin

**Question.** Is there a way to slow the shop's database from inside MySQL that adds a fixed delay per statement, so that it does not collapse under overlapping traffic? (The developer ruled out a network delay.)

**Sources.** Context7 resolved MySQL (`/mysql/mysql-server`, version `mysql-5.7.44`) but its answer to the Rewriter question returned only unrelated text, so the manual pages came via web: `https://dev.mysql.com/doc/refman/5.7/en/rewriter-query-rewrite-plugin-usage.html` and `.../rewriter-query-rewrite-plugin-reference.html`. The usage page says: "Prepared statements are rewritten at parse time (that is, when they are prepared), not when they are executed later", and that `flush_rewrite_rules()` must be called to load the rules table into the plugin cache. A fetched page also mentioned a `SKIP_QUERY_REWRITE` privilege and a variable `rewriter_enabled_for_threads_without_privilege_checks`; the live 5.7.35 server lists only `rewriter_enabled` and `rewriter_verbose`, so that wording comes from a newer version and is not used. A web search on MySQL-native latency injection found only network proxies (Toxiproxy, Chaos Mesh), application driver wrappers, and `innodb_thread_concurrency` with `innodb_thread_sleep_delay` (delays only when queries overlap), none of which fit.

**Read-only facts first.** The plugin file is in the image and not installed:

```
plugin_dir      /usr/lib/mysql/plugin/
performance_schema  ON
(no row for any plugin named like "rewrit" in information_schema.plugins)
rewriter.so
install_rewriter.sql
uninstall_rewriter.sql
mysql  Ver 14.14 Distrib 5.7.35
```

Data baseline taken before any change (`cities.cities` checksum is `SUM(CRC32(CONCAT(uuid,city,country_code,name)))`):

```
cities	948833	2037759317216027
codes	25
cities	cities	906712
cities	codes	9
mysql	plugin	0
ratings	ratings	9
```

The statements the shop sends (from `performance_schema.events_statements_history`; shipping's are plain `statement/sql/select`):

```
select city0_.uuid as uuid1_0_, city0_.city as city2_0_, city0_.country_code as country_3_0_, city0_.latitude as latitude4_0_, city0_.longitude as longitud5_0_, city0_.name as name6_0_, city0_.region as region7_0_ from cities city0_ where city0_.country_code='de'
select city0_.uuid as uuid1_0_, ... from cities city0_ where city0_.country_code='de' and (city0_.city like 'ber%')
```

Ratings' statement was read from the app source (`/var/www/html/src/Service/RatingsService.php:13` and `src/Database.php:43`): a real prepared statement, `PDO::ATTR_EMULATE_PREPARES => false`:

```
select avg_rating, rating_count from ratings where sku = ?
```

**Run — install, add shipping rules, test.** Output hashes of the two shipping routes taken first (`fac23cd2b8ffdf432b27b74fb359e324` for `/match/de/ber`, `4d81af2eac60dd9c1459c4a3b37a35b4` for `/cities/de`). Install (`mysql < /usr/share/mysql/install_rewriter.sql`):

```
PLUGIN_NAME	PLUGIN_STATUS	PLUGIN_TYPE
Rewriter	ACTIVE	AUDIT
rewriter_enabled	ON
rewriter_verbose	1
Rewriter_number_loaded_rules	0
Rewriter_number_reloads	1
Rewriter_number_rewritten_queries	0
Rewriter_reload_error	OFF
Tables_in_query_rewrite
rewrite_rules
rules
0
restarts=0
```

Two rules (`pattern_database` `cities`; replacement adds a one-row derived table `(select sleep(3)) as db_delay` in front of `cities city0_`; values replaced by `?`), then `CALL query_rewrite.flush_rewrite_rules()`:

```
id	enabled	loaded	message
1	YES	1	NULL
2	YES	1	NULL
Rewriter_number_loaded_rules	2
Rewriter_number_reloads	2
Rewriter_number_rewritten_queries	0
Rewriter_reload_error	OFF
```

Sequential timings, then output hashes again:

```
shipping-match 200 3.661644
shipping-match 200 3.990717
shipping-match 200 3.892905
shipping-match 200 3.800551
shipping-match 200 3.781938
shipping-match 200 3.704555
shipping-cities 200 4.441008
shipping-cities 200 4.342248
shipping-cities 200 4.391903
ratings 200 0.016580   (SKU HAL-1: not a database request, see Finding 2 correction)
ratings 200 0.014687
ratings 200 0.015453
hash after:
fac23cd2b8ffdf432b27b74fb359e324  -
4d81af2eac60dd9c1459c4a3b37a35b4  -
Rewriter_number_rewritten_queries	11
```

**Run — 4-minute overlapping pattern, shipping rules, load generator off:**

```
before: 14:50:49 UTC
avg_statement_s_before success [('', 3.791)]
== end of window 14:54:52 UTC
threads_running success [('mysql-0', 3.0)]
threads_running_max4m success [('mysql-0', 3.0)]
qps success [('mysql-0', 6.567)]
avg_statement_s success [('', 3.703)]
shipping_p90_ms success [('', 4750.0)]
ratings_p90_ms success [('', 24.092)]
mysql_cpu success [('mysql-0', 0.078)]
traffic: shipping n=115 timeouts=0 over2s=115 min=3.544277 max=4.310916 avg=3.78726 | ratings n=115 over0.5s=0
```

(`avg_statement_s_before` was already 3.791 because its one-minute window included the sequential test above; it is not a baseline.) The "ratings" rows of this run again used `HAL-1`.

**Ratings.** A real SKU (`Watson`, from `/products`) returns `{"avg_rating":3.09,"rating_count":250}` in 0.016 to 0.073 s. A rule on the prepared statement (`pattern_database` `ratings`, replacement `select avg_rating, rating_count from (select sleep(3)) as db_delay, ratings where sku = ?`):

```
id	enabled	message
1	YES	NULL
2	YES	NULL
3	YES	NULL
Rewriter_number_loaded_rules	3
Rewriter_reload_error	OFF
== ratings after rule, sequential
{"avg_rating":3.09,"rating_count":250} 200 6.030102
{"avg_rating":3.09,"rating_count":250} 200 6.033038
{"avg_rating":3.09,"rating_count":250} 200 6.028357
{"avg_rating":3.09,"rating_count":250} 200 6.024026
{"avg_rating":3.09,"rating_count":250} 200 6.017847
```

The body is identical to before. A 3 s sleep gives 6 s: the ratings request appears to run the query twice (why was not investigated). Overlapping pattern, 2 minutes (the loop waits for the ratings call, so 15 iterations), with all three rules:

```
overlapping 2 min, both rules: shipping n=15 timeouts=0 over2s=15 min=3.605076 max=3.926567 | ratings n=15 timeouts=0 over2s=15 min=6.019716 max=6.172596
Rewriter_number_rewritten_queries	181
```

**Run — revert and uninstall.** Rules disabled (`UPDATE query_rewrite.rewrite_rules SET enabled='NO'`, flush: `Rewriter_number_loaded_rules 0`), then:

```
shipping 200 0.726125
shipping 200 0.786148
shipping 200 0.782267
ratings 200 0.017337   (Watson)
ratings 200 0.014137
ratings 200 0.033472
```

After `uninstall_rewriter.sql`:

```
== uninstall
exit=1                       (exit of the grep that filters the client warning; the script printed nothing)
1                            (rewriter_plugins in information_schema.plugins: see below)
0                            (rows in mysql.plugin)
0                            (query_rewrite schemas)
rewriter_enabled	ON
rewriter_verbose	1
cities	948833	2037759317216027
codes	25
ratings	9	2276
restarts=0 limit=200m
fac23cd2b8ffdf432b27b74fb359e324  -
4d81af2eac60dd9c1459c4a3b37a35b4  -
{"avg_rating":3.09,"rating_count":250} 200 0.036970
```

```
PLUGIN_NAME	PLUGIN_STATUS	PLUGIN_TYPE
Rewriter	DELETED	AUDIT
Rewriter_number_loaded_rules	0
Rewriter_number_reloads	4
Rewriter_number_rewritten_queries	181
plugin_rows
0
```

**What it shows.**
- A fixed sleep inside MySQL works and does not collapse under overlapping traffic: 115 of 115 shipping requests answered (3.54 to 4.31 s) with MySQL using 78m of CPU and 3 threads running, against 74 to 89 of 100 timeouts for the CPU limit.
- Results are identical (hashes of both shipping routes; ratings body unchanged), and shop data is identical after uninstall (`cities` 948,833 rows with the same checksum, `codes` 25, `ratings` 9 rows, `mysql.plugin` back to 0 rows).
- Ratings is slowed too, at twice the sleep (6.0 s for 3 s). Shipping `/match` gets about 2.9 to 3.2 s more than its normal 0.8 s; `/cities` about 3 s more than 1.4 s.
- The rules match the exact statement text. The `mysql` image is `robotshop/rs-mysql-db:latest` (seen in Finding 3), so a changed upstream image could stop the rules matching.
- After `uninstall_rewriter.sql` the plugin stays loaded in memory as `DELETED` until MySQL restarts, and reinstalling fails (see Finding 10).
- The Database dashboard's existing statement metrics work as a panel source: the average statement time was 3.7 s during the fault.

**Result.** The fault is the Rewriter rules. Plan facts drawn from this finding: `pattern_database` is `cities` for shipping and `ratings` for ratings; ratings needs about half the sleep of shipping for a similar delay; `Rewriter_number_loaded_rules` and the `enabled` column are the on/off state.

## Finding 10 — The Rewriter plugin cannot be uninstalled and reinstalled without restarting MySQL

**Question.** Can revert uninstall the plugin and start install it again?

**What I ran.** The plugin's own scripts, `/usr/share/mysql/install_rewriter.sql` and `uninstall_rewriter.sql`, each run twice on the live `mysql-0` on 2026-10-22, in the session of Finding 9. The output below is the terminal output of that run:

```
== state now
plugin=DELETED
mysql.plugin rows=0
schema=0
== install while plugin is DELETED
ERROR 1125 (HY000) at line 37: Function 'rewriter' already exists
(0) done install_rewriter.sql
plugin=DELETED
mysql.plugin rows=0
schema=1
== install again (already installed)
ERROR 1125 (HY000) at line 37: Function 'rewriter' already exists
(0) done install_rewriter.sql
plugin=DELETED
mysql.plugin rows=0
schema=1
== uninstall
ERROR 1305 (42000) at line 24: FUNCTION (UDF) load_rewrite_rules does not exist
(0) done uninstall_rewriter.sql
plugin=DELETED
mysql.plugin rows=0
schema=0
== uninstall again (already uninstalled)
ERROR 1305 (42000) at line 24: FUNCTION (UDF) load_rewrite_rules does not exist
(0) done uninstall_rewriter.sql
plugin=DELETED
mysql.plugin rows=0
schema=0
restarts=0
```

**What it shows.**
- The first uninstall removes the plugin's table row (`mysql.plugin rows=0`), but the plugin stays loaded in memory as `DELETED` until MySQL restarts.
- A later install fails with `ERROR 1125 ... Function 'rewriter' already exists` and half-creates the `query_rewrite` schema (`schema=1`).
- A second uninstall fails with `ERROR 1305 ... load_rewrite_rules does not exist`.
- The pod had 0 restarts throughout. A restart cleared the state: on 2026-10-22, after the cluster was started again, the plugin was absent and a fresh install worked.

**Result.** Revert only disables the rules and leaves the plugin installed (developer decision, 2026-10-22). Disabling was tested the same day: `UPDATE query_rewrite.rewrite_rules SET enabled='NO'` plus `CALL query_rewrite.flush_rewrite_rules()` took `Rewriter_number_loaded_rules` to 0 and request times were normal at once. Start installs the plugin only if it is missing, then enables the rules. Whether the rules survive a MySQL restart was not tested; the spec does not require it.

## Finding 11 — Tempo shows the slow database call for shipping (Technical Context question 6, FR-010)

**Question.** Can the presenter see the slow database step of a slow request, and from where?

**What I ran** (2026-10-22, 18:14 UTC, Rewriter rules on with 2.5 s for the shipping statements and 0.5 s for ratings; requests sent from `deploy/web`; Tempo at `tempo.monitoring.svc:3200`):

```
match 200 2.737232
ratings 200 1.024695
```

Search for shipping traces longer than 2 s (`{ resource.service.name = "shipping" && duration > 2s }`):

```
231e2a4ac6028de2a36ac75491fa83fc GET /match/de/ber 2684
54f95ec9ef73a91b6827a2a6cb8cda3a GET /match/de/ber 2708
868cee38581c07f99c42cc0592b1cc01 GET /match/de/ber 2714
```

The spans of the first trace, fetched with `/api/traces/<id>`:

```
['shipping'] GET /match/de/ber 2685.0 ms
['shipping'] GET /match/de/ber 2684.4 ms
['shipping'] SELECT cities 2505.9 ms
['shipping'] SELECT cities 2505.8 ms
['shipping'] GET /match/de/ber 2683.9 ms
['shipping'] SELECT cities 2506.0 ms
```

Three TraceQL searches:

```
== { span.db.system != nil }
0 traces []
== { name = "SELECT cities" }
3 traces [('SELECT cities', 2504), ('GET /match/de/ber', 2635), ('SELECT cities', 2505)]
== { resource.service.name = "ratings" && duration > 0.9s }
Traceback (most recent call last):
  ...
KeyError: 'rootTraceName'
```

The last search did return a trace (`rootServiceName` `<root span not yet received>`, `durationMs` 17907); my script failed because the reply has no `rootTraceName`. I did not open its spans.

**In Grafana** (logged in by the developer; the Grafana datasource list shows `Tempo`, type `tempo`, uid `EbPG8fYoz`, `http://tempo.monitoring:3200`): Explore → Tempo → TraceQL with the shipping query above and a 30 minute range showed a table with Trace ID, Start time, Name and Duration. The rows were `/match/de/ber` at 2.63 to 2.77 s and `/cities/de` at 3.24 to 3.26 s, and one row named `<root span not yet received>` at 2.72 s. Clicking a trace ID opened the trace view with 6 spans, the lower `SELECT` spans at about 2.51 s of 2.63 s.

**Failure.** My own call to Grafana's `/api/ds/query` returned `{"message":"An error occurred within the plugin","messageId":"plugin.downstreamError","statusCode":500}` for 15 minute and 1 hour ranges. The same query worked in the Explore screen, so the request body I hand-built was the likely problem; the cause was not investigated.

**What it shows.**
- For shipping, the `SELECT` span is about 2.5 s of a 2.68 s request. That is the "database is the slow part" view.
- Search by span name works; search by `span.db.system` finds nothing.
- Late spans can leave a `<root span not yet received>` row. It still opens.
- Whether ratings has an SQL span is not confirmed.
- The Database dashboard has no link to these traces today; the presenter has to know to use Explore.

**Update, same day (Finding 12).** Ratings does have SQL spans (`SELECT ratings`, about 0.5 s, with the 0.5 s sleep). The ratings sentence above is settled by Finding 12.

**Result.** The Database dashboard gets one new panel (developer decision, 2026-10-22): a Tempo table of slow shipping requests whose trace IDs open the span view. Ratings is included too, since Finding 12 confirmed its SQL spans. The panel's exact query and layout are a plan decision, still to write. The spec needs a requirement for this panel, still to amend.

## Finding 12 — Tuned sleeps, overlapping traffic, revert, data check and ratings spans (Technical Context questions 1 and 2)

**Question.** Which sleep lengths put shipping above 2 s and ratings above 0.5 s without errors, does revert work by disabling rules, is the data unchanged, and does ratings show SQL spans?

**What I ran** (2026-10-22, cluster started again that evening, load generator at 0 replicas; `mysql-0` restarted by the cluster start so the plugin was absent at the start; requests from `deploy/web`).

Plugin installed with `install_rewriter.sql`, then three rules loaded: shipping at 2 s, ratings at 0.5 s:

```
id	enabled	loaded	message
1	YES	1	NULL
2	YES	1	NULL
3	YES	1	NULL
Variable_name	Value
Rewriter_number_loaded_rules	3
Rewriter_number_reloads	3
Rewriter_number_rewritten_queries	0
Rewriter_reload_error	OFF
```

At 2 s for shipping (`/match` normal time at this point was 0.16 to 0.29 s):

```
match 200 2.603002
match 200 2.282588
match 200 2.234097
match 200 2.178348
cities 200 4.165742
cities 200 3.631653
cities 200 3.701440
ratings 200 1.030231
ratings 200 1.025674
ratings 200 1.027020
ratings 200 1.018612
```

Several `/match` times are close to the 2 s line, so shipping went to 2.5 s. The `UPDATE` that did it ran in the same command as a `SELECT` using `REGEXP_SUBSTR`, which MySQL 5.7 does not have, so that command printed `ERROR 1046 (3D000) at line 1: No database selected`. The rule rows were checked separately and the update had applied:

```
id	pattern_database	enabled	message	s
1	cities	YES	NULL	2.5
2	cities	YES	NULL	2.5
3	ratings	YES	NULL	0.5
Variable_name	Value
Rewriter_number_loaded_rules	3
Rewriter_number_reloads	4
Rewriter_number_rewritten_queries	29
Rewriter_reload_error	OFF
```

At 2.5 s and 0.5 s:

```
match 200 2.645871
match 200 2.699331
match 200 2.686853
match 200 2.697160
match 200 2.703083
cities 200 3.262939
cities 200 3.254839
cities 200 3.243335
ratings 200 1.029279
ratings 200 1.019225
ratings 200 1.027526
```

Overlapping traffic for 2 minutes (one shipping `/match/de/ber` and one ratings `/api/fetch/Watson` request every 2 s, 40 s timeout), summarised with awk:

```
shipping n=40 bad=0 over2s=40 min=2.641237 max=2.822228 | ratings n=40 bad=0 over0.5s=40 max=1.138295
```

Revert: all rules set to `enabled='NO'`, then `flush_rewrite_rules()`:

```
id	enabled	message
1	NO	NULL
2	NO	NULL
3	NO	NULL
Variable_name	Value
Rewriter_number_loaded_rules	0
match 200 0.156958
match 200 0.201239
match 200 0.288935
cities 200 1.269682
ratings 200 0.023464
ratings 200 0.016858
ratings 200 0.055813
```

Data check with the rules on, then off (the rules were disabled between the two runs), and the shipping output hashes after revert, next to the hashes saved before any change:

```
== fault ON
Variable_name	Value
Rewriter_number_loaded_rules	3
COUNT(*)	SUM(CRC32(CONCAT(uuid,city,country_code,name)))
948833	2037759317216027
COUNT(*)
25
COUNT(*)
0
Variable_name	Value
Rewriter_number_loaded_rules	0
== fault OFF
COUNT(*)	SUM(CRC32(CONCAT(uuid,city,country_code,name)))
948833	2037759317216027
COUNT(*)
25
COUNT(*)
0
fac23cd2b8ffdf432b27b74fb359e324  -
4d81af2eac60dd9c1459c4a3b37a35b4  -
fac23cd2b8ffdf432b27b74fb359e324  -
4d81af2eac60dd9c1459c4a3b37a35b4  -
```

The first two hash lines are the shipping routes after revert; the last two are the saved "before" values. They match.

Ratings spans for one slow `GET /api/fetch/Watson` (trace `98e58d945daf26f395afc39d6157d2e9`, rules on; columns: service, container, span name, kind, milliseconds, database, port), sorted by start time:

```
web istio-proxy GET /api/fetch/Watson SERVER 1019.5 None 15001
web istio-proxy GET /api/fetch/Watson CLIENT 1018.1 None 80
ratings istio-proxy GET /api/fetch/Watson SERVER 1017.7 None 15006
ratings istio-proxy GET /api/fetch/Watson CLIENT 1017.1 None 80
ratings ratings GET /api/fetch/Watson SERVER 1017.0 None 80
ratings istio-proxy SELECT ratings SERVER 0.2 mysql 15001
ratings ratings SELECT ratings CLIENT 501.8 mysql 3306
ratings istio-proxy SELECT ratings CLIENT 501.4 mysql 3306
```

A second trace of the same call (`85b03ef929053000073bc4af2115b22f`) had the same spans plus `SELECT dual` (0.3 and 0.7 ms) and a trace length of 5,935 ms; I did not look into either.

**Failure: the `ratings` table is empty.** The response body for `Watson` was `{"avg_rating":0,"rating_count":0}` (it was `3.09` and `250` in Finding 9) and the count above is 0, not 9 rows (`SUM(rating_count)` 2276). The count was 0 with the rules on and off, and the rules only rewrite `SELECT`s, so the fault did not cause it. `cities` (948,833 rows) survived the cluster stop and start. The cause was not found; the ratings logs show only health checks. Open item (developer decision: note it and move on).

**What it shows.**
- 2.5 s for both shipping statements gives `/match` 2.64 to 2.82 s and `/cities` about 3.25 s; 0.5 s for ratings gives 1.02 to 1.14 s. All 40 shipping and 40 ratings requests in the overlap run succeeded, all over the thresholds (2 s and 0.5 s).
- At 2 s the shipping `/match` time was 2.18 to 2.60 s, too close to the 2 s line.
- The ratings request takes about twice its sleep (the query seems to run twice), but its trace listed one 0.5 s `SELECT ratings` client span. Why is not known.
- Disabling the rules and flushing returns request times to normal at once (`/match` 0.16 to 0.29 s, ratings 0.017 to 0.056 s).
- Shipping data and outputs are unchanged by the fault (row count, checksum, both route hashes).
- Ratings does have SQL spans in Tempo, so the traces panel can include ratings.

**Result.** Sleeps: 2.5 s for both shipping statements and 0.5 s for ratings. Revert is disable plus flush. Open: why `ratings` has no rows, and the second 0.5 s on the ratings request. The "nothing changed" check for ratings is not possible until the table has rows again.

## Finding 13 — A shop re-deploy leaves the fault on (Technical Context question 4, EC-002, FR-013)

**Question.** Does re-running the shop's deploy clear the Rewriter rules?

**What I ran** (2026-10-22, 18:35 to 18:38 UTC): with the three rules enabled, `make setup-robot-shop` (STACK_MODE `aks`), then waited for the seeder job. Before, right after the deploy, and after the seeder finished, I recorded the rules, the plugin state and a shipping request:

```
== BEFORE
id	enabled	pattern_database
1	YES	cities
2	YES	cities
3	YES	ratings
Variable_name	Value
Rewriter_number_loaded_rules	3
PLUGIN_NAME	PLUGIN_STATUS
Rewriter	ACTIVE
2f259ce6-e3b6-4a9c-84ca-0b3500aa3182 restarts=0
match 200 2.647434
```

The deploy printed (password lines filtered out of the paste):

```
kubectl delete job mysql-seeder -n robot-shop --ignore-not-found
job.batch "mysql-seeder" deleted
Release "roboshop" has been upgraded. Happy Helming!
STATUS: deployed
REVISION: 15
```

It finished in 10 s (18:35:46 to 18:35:56); `helm --wait` does not wait for the seeder.

```
== AFTER deploy (seeder running)
id	enabled	pattern_database
1	YES	cities
2	YES	cities
3	YES	ratings
Variable_name	Value
Rewriter_number_loaded_rules	3
PLUGIN_NAME	PLUGIN_STATUS
Rewriter	ACTIVE
2f259ce6-e3b6-4a9c-84ca-0b3500aa3182 restarts=0
job.batch/mysql-seeder   Running   0/1   7s
== AFTER seeder complete (condition met, 18:37:59 UTC)
id	enabled	pattern_database
1	YES	cities
2	YES	cities
3	YES	ratings
Variable_name	Value
Rewriter_number_loaded_rules	3
COUNT(*)
948833
COUNT(*)
0
match 200 2.750635
match 200 2.786110
ratings 200 1.026246
{"avg_rating":0,"rating_count":0}
```

**What it shows.**
- Rules, plugin and pod (same uid, 0 restarts) all survive a re-deploy, and the fault stays on.
- The seeder took about 2 minutes and was not slowed by the fault: its statements are not matched by the rules. The old EC-002 text ("takes much longer while the database is slowed") does not apply to this design.
- The `ratings` table was already empty before the deploy and the seeder leaves it empty. The developer's explanation is that rows come from the load generator, which was off; this was not tested here (see Finding 14 for what a database restart does to the table).

**Result.** EC-002 answer: the fault stays on through a re-deploy and the data reloads normally. The guide can still suggest reverting first as the cleaner order, but it is not needed for speed or for data.

## Finding 14 — A MySQL restart wipes the fault and reloads the shop data (EC-003, EC-004)

**Question.** What happens to the fault, and to the shop, when `mysql-0` restarts?

**What I ran** (2026-10-22): rules enabled (`Rewriter_number_loaded_rules` 3), then `kubectl delete pod mysql-0 -n robot-shop` at 18:41:31 UTC (the StatefulSet recreated it), then checks:

```
before uid=2f259ce6-e3b6-4a9c-84ca-0b3500aa3182
pod "mysql-0" deleted
pod/mysql-0 condition met
after uid=c3e6b366-bffb-4cb7-b764-be2e7b8b15cf
ERROR 1146 (42S02) at line 1: Table 'query_rewrite.rewrite_rules' doesn't exist
match 000 30.001218
match 000 30.000937
ratings 500 0.036750
```

The pod reported ready 15 s after the delete, but the MySQL log showed it still initialising from scratch:

```
2026-10-22 18:42:01+00:00 [Note] [Entrypoint]: Creating database cities
2026-10-22 18:42:01+00:00 [Note] [Entrypoint]: Creating user shipping
2026-10-22 18:42:01+00:00 [Note] [Entrypoint]: Giving user shipping access to schema cities
2026-10-22 18:42:01+00:00 [Note] [Entrypoint]: /usr/local/bin/docker-entrypoint.sh: running /docker-entrypoint-initdb.d/10-dump.sql.gz
2026-10-22 18:43:41+00:00 [Note] [Entrypoint]: /usr/local/bin/docker-entrypoint.sh: running /docker-entrypoint-initdb.d/20-ratings.sql
2026-10-22 18:43:42+00:00 [Note] [Entrypoint]: /usr/local/bin/docker-entrypoint.sh: running /docker-entrypoint-initdb.d/99-finished.sh
```

After it finished (18:43:51 UTC):

```
ready=true restarts=0
Database
information_schema
cities
mysql
performance_schema
ratings
sys
COUNT(*)
948833
COUNT(*)
0
COUNT(*)
0
match 200 3.103562
ratings 200 0.016282
```

The three counts are `cities` rows, `ratings` rows and `mysql.plugin` rows. An earlier check, while it was still initialising, had printed `ERROR 1053 (08S01) at line 1: Server shutdown in progress` (the temporary init server stopping), `COUNT(*)` 0 for `information_schema.plugins` Rewriter and 0 for `mysql.plugin`.

**What it shows.**
- A restart removes the plugin, the `query_rewrite` schema and the rules: the fault is gone. This confirms EC-003 as written.
- The shop is down for about 2 minutes: shipping timed out at 30 s and ratings returned 500 while MySQL initialised. A presenter should not restart MySQL in the middle of a demo.
- The `cities` data comes back (948,833 rows); the `ratings` table is empty again. Its rows come from shop traffic (developer's explanation, consistent with this).
- Start after a restart installs the plugin from scratch, so "install only if missing" (Finding 10) holds.
- The first `/match` after initialisation took 3.10 s with the fault off (cold cache), so "normal speed" depends on how recently the database restarted.
- Not investigated: why the data is re-created although `/var/lib/mysql` is a mounted volume claim (`data-mysql-0`).

**Result.** No restart survival, as the spec says. Status after a restart reads "not active". The guide warns against restarting MySQL during a demo.
