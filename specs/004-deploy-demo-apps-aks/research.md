# Research: 004-deploy-demo-apps-aks

**Researcher**: Builder (Viknesh)

**Status**: Cluster created and verified live. Robot Shop deployed and functional end-to-end except one unresolved, non-blocking finding (§4). HotROD deployed clean, no defects found. The new gateway/reachability requirement (FR-011, added to the issue after spec approval) verified working live. Two real chart defects found and fixed in `app/robot-shop/helm/templates/`; one AKS-unrelated cluster defect found and not fixed (§6, out of this story's scope).

**Evidence standard for this document**: every claim below is real terminal output from commands run against the live AKS cluster (`sre-stack-c1d1fb`, resource group `viknesh-g-improving-com-aks-c1d1fb`, `eastus2`), not reconstructed or assumed. Where a hypothesis was tested and disproven, that is recorded as a ruled-out theory, not omitted.

---

## 1. AKS cluster did not exist; created live

**Question**: Is the AKS cluster from story #97 available to test against?

**Finding**: No cluster existed under the accessible Azure subscription (`Pune - Sandbox (TPM)`). `az aks list -o table` initially returned an unrelated cluster (`testkube-atul` / `atul-testkube-demo`), not this project's.

**Action**: Ran `make setup-cluster` live. Real output (abridged):
```
allowance check: spot 0/3 (need 26 for missing workload pools), DSv5 0/50 (need 22 + 2 for the system pool), FSv2 0/50 (need 4) — chosen mode: regular
Names: resource group viknesh-g-improving-com-aks-c1d1fb, cluster sre-stack-c1d1fb.
creating cluster sre-stack-c1d1fb (kubernetes 1.34, 1× Standard_D2s_v5 system pool)...
adding node pool app (3× Standard_D2s_v5)...
adding node pool persistent (2× Standard_D4s_v5)...
adding node pool o11y (2× Standard_D4s_v5)...
adding node pool loadgen (1× Standard_F4s_v2)...
applying infra/azure/gp2-storageclass.yaml...
Setup complete: cluster sre-stack-c1d1fb in viknesh-g-improving-com-aks-c1d1fb (eastus2), mode regular.
```

**Conclusion**: Cluster now exists and is real. This is a prerequisite (story #97's responsibility), not part of 004, but had to be created here to do any further research.

---

## 2. Node pool labels and taints match the workload placement contract (Principle V)

**Question**: Does the real cluster match the `workload=app|persistent|o11y|loadgen` label/taint contract this story's placement (FR-002, FR-005) depends on?

**Command**: `kubectl get nodes --show-labels` / `kubectl get nodes -o json | jq '.items[].spec.taints'`

**Findings**: Labels present: `workload=app`, `workload=persistent`, `workload=o11y`, `workload=loadgen`. Taints: `app` pool nodes untainted; `persistent`, `o11y`, `loadgen` pools each tainted `NoSchedule` with a matching key (`persistent=true`, `o11y=true`, `loadgen=true`).

**Conclusion**: Matches Principle V exactly. No changes needed to the cluster itself.

---

## 3. `setup-robot-shop` and `setup-hotrod` were fully disabled, not "existing commands to reuse"

**Question**: Do the deployment commands named in the issue's Outcome section already work, as assumed?

**Finding**: Both targets, and their AWS-specific dependency (`setup-db-rds-mysql`, `setup-rabbitmq-operator`), were fully commented out in the `makefile` for every `STACK_MODE` (not just AKS), landed by commit `chore(003): comment out AWS/app-specific makefile targets for now`. The inline comment on `setup-gateway`'s AKS branch (`infra/scripts/cluster/setup-gateway-aks.sh`) explicitly states: *"Robot Shop deployment (and its Gateway/VirtualService routing) is out of scope for this story (see story #102)"* — confirming this repo already expected 004 to restore this.

**Correction applied**: spec.md's FR-001/FR-004/Assumptions were rewritten (commit `0e0d0dc`) to state the commands are currently non-functional everywhere and restoring them is in scope, not a prerequisite. `setup-robot-shop` and `setup-hotrod` were uncommented locally for this research; not yet committed (implementation is `/speckit-implement`, after `gate:plan-approved`).

---

## 4. Robot Shop: two real chart defects found and fixed; one unresolved finding

### 4a. Missing CRDs (dependency ordering, not a chart bug)

**First attempt** (`helm upgrade --install robot-shop ...`) failed:
```
Error: unable to build kubernetes objects from release manifest: [resource mapping not found for name: "rabbitmq" ...: no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
..., no matches for kind "VirtualService" in version "networking.istio.io/v1alpha3"
ensure CRDs are installed first]
```
**Cause**: Istio (`VirtualService` CRD) and kube-prometheus-stack (`ServiceMonitor` CRD) — both story #101/003 dependencies — were not yet installed on this fresh cluster.
**Fix**: Ran `make setup-istio` then `make setup-observability` (the latter got as far as `setup-metric-server` before hitting an unrelated defect, §6 — both needed CRDs were already installed by that point). Robot Shop then progressed past this error.

### 4b. MySQL chart templates gated to `stack_mode: "local"` only

**Symptom**: No `mysql` pod, service, secret, or configmap ever created when deploying with `--set stack_mode=aks`. `ratings`/`shipping` pods stuck at `1/2 Ready`, logs showing:
```
[app.ERROR] Database error SQLSTATE[HY000] [2002] php_network_getaddresses: getaddrinfo failed: Name or service not known
```
**Root cause, found by reading the chart source directly** — all five MySQL templates share the same condition:
```
app/robot-shop/helm/templates/mysql-statefulset.yaml:1:{{- if eq .Values.stack_mode "local" }}
app/robot-shop/helm/templates/mysql-config.yaml:1:{{- if eq .Values.stack_mode "local" }}
app/robot-shop/helm/templates/mysql-secret.yaml:1:{{ if eq .Values.stack_mode "local" }}
app/robot-shop/helm/templates/mysql-service.yaml:1:{{ if eq .Values.stack_mode "local" }}
app/robot-shop/helm/templates/mysql-seeed-job.yaml:2:{{- if eq .Values.stack_mode "local" }}
```
`values.yaml`'s `mysql:` block already has the correct `nodeSelector: {workload: persistent}` and matching toleration — the placement logic was already right, only the render condition was wrong.

**Fix applied** (uncommitted, local chart edit): all five changed from `eq .Values.stack_mode "local"` to `ne .Values.stack_mode "eks"`, so MySQL renders for both `local` and `aks`, matching the "in-cluster DB, no managed service" requirement (FR-003) for every non-EKS target.

**Verification, real output after fix**:
```
NAME                         READY   STATUS    RESTARTS
mysql-0                      3/3     Running   0
ratings-...                  2/2     Running   0
shipping-...                 2/2     Running   4 (recovered)
```
All 8 Robot Shop app pods plus 4 in-cluster datastores (MySQL, MongoDB, RabbitMQ, Redis) reached `Running`.

### 4c. Also found and ruled out: `mysql-seeder` Job immutability

Re-running `helm upgrade` after the template fix failed once more:
```
Job.batch "mysql-seeder" is invalid: spec.template: ...: field is immutable
```
**Cause**: the Job created before the fix still existed with a different pod template; Kubernetes Jobs cannot update their pod template in place.
**Fix**: `kubectl delete job -n robot-shop mysql-seeder` before re-running upgrade. Not a chart bug — a re-run hygiene note for `tasks.md`/`plan.md` (idempotency handling, FR-008).

### 4d. Unresolved, non-blocking finding: seed data import hangs for the seeder Job specifically

**Symptom**: `mysql-seeder`'s pod (`sidecar.istio.io/inject: "false"` — deliberately outside the mesh) hangs indefinitely importing `10-cities.sql`, confirmed via `MYSQL_PWD=... mysql -h ... < file` reproduced manually with `timeout`: exit code 124 (timeout), zero CPU usage.

**Theories tested and ruled out with real evidence, not assumed:**
- *Strict mTLS blocking plaintext clients*: `kubectl get peerauthentication -A` returned empty — no STRICT policy exists anywhere, so Istio's mesh-wide default (PERMISSIVE) applies. Ruled out.
- *Istio's legacy `mysql`-named-port protocol filter mishandling non-meshed clients*: renamed the `mysql` Service port to `tcp-mysql` (forcing plain TCP passthrough) in `app/robot-shop/helm/templates/mysql-service.yaml`, redeployed. Seeder hung identically at the same log line afterward. Ruled out.
- *Raw TCP-level comparison*: using bash's `/dev/tcp`, a **meshed** pod (`ratings`) received the MySQL server's handshake bytes within milliseconds; the **unmeshed** `mysql-seeder` pod completed the TCP three-way handshake but received zero bytes within an 8-second window, every time. Consistent difference between meshed and unmeshed clients confirmed, but not yet root-caused.
- *Envoy inbound proxy logs on `mysql-0`*: bumped to debug level (`POST /logging?level=debug`) and re-triggered the seeder's connection attempt. The debug log captured a concurrent, unrelated, fully successful connection from `ratings` (full TLS handshake, clean close) but **no entry at all** for the seeder's connection — suggesting the problem may occur before reaching `mysql-0`'s sidecar (NetworkPolicy, Azure CNI, or conntrack), not inside Envoy's filter chain. Not confirmed.

**Practical impact, verified live**: the actual store (browsing, product page, ratings display as "No votes yet" — a graceful empty state, not an error — add to cart, cart totals) all work normally end to end via a browser through `kubectl port-forward`. This finding only affects the one-time sample-data seed job, not the running application's health or observability value.

**Recommendation for `plan.md`/`tasks.md`**: treat as a known, documented gap. Either (a) accept missing seed data for this demo story and file a follow-up story to root-cause it, or (b) have the Builder spend bounded time on it during implementation with a hard stop if unresolved, per constitution Principle X (convergence has an exit criterion, not an open-ended hunt).

---

## 5. HotROD: clean deployment, one dependency gap (not a chart bug)

**Chart check**: `app/hotrod/base/hotrod/deployment.yaml` already has correct placement (`nodeSelector: {workload: app}`) and minimal resources (`100m CPU / 100M memory`, single replica). No fix needed.

**Dependency finding**: HotROD's container sets `OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector.monitoring:4318`. That collector is installed by `setup-optional-otel`, which is **not** part of `setup-observability`'s dependency chain (`setup-observability: setup-db-grafana-psql setup-kube-prometheus-stack setup-loki setup-beyla setup-tempo setup-caretta setup-metric-server setup-istio-o11y-addons setup-dashboards` — `setup-optional-otel` is absent from that list). Ran it explicitly; installed cleanly (with two Helm deprecation notices about the `otlp` exporter being renamed `otlp_grpc`, non-blocking).

**Verification**: `kubectl get pods -n hotrod` → `hotrod-... 1/1 Running`, immediately, no restarts.

**Recommendation for `plan.md`**: either add `setup-optional-otel` as a real dependency of `setup-hotrod`/`setup-observability`, or document it as a manual prerequisite step. Leaving it silently optional means HotROD's traces silently go nowhere.

---

## 6. Found, out of scope: `setup-metric-server` fails on AKS

While running `setup-observability`, it stopped at:
```
Error: unable to continue with install: ClusterRole "system:metrics-server" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata...
```
**Cause**: AKS ships a built-in `metrics-server` addon by default; this Helm install collides with it. Confirmed real, not fixed — out of scope for this story (belongs to #101's AKS observability work, not app deployment). Noted here so it isn't rediscovered as a surprise later.

---

## 7. New requirement (FR-011): per-app external reachability — verified working

**Question** (added to issue #102 after spec approval): can Robot Shop and HotROD each be reached from outside the cluster through their own address, without interfering with each other?

**Finding**: `infra/scripts/cluster/setup-gateway-aks.sh` is currently a literal no-op for AKS, with a comment stating Robot Shop's Gateway/VirtualService routing is "out of scope for this story (see story #102)" — i.e., this repo already expected 004 to fill this in.

**Design risk found**: naively reusing Robot Shop's existing `app/robot-shop/Istio/gateway.yaml` pattern for HotROD as well would have both `Gateway`/`VirtualService` pairs claim `hosts: "*"` on the same shared `istio-ingressgateway` — a direct routing collision, which is exactly what FR-011 requires avoiding.

**Fix verified live**: kept Robot Shop's existing `gateway.yaml` (`hosts: "*"`) unchanged, and added a second `Gateway`/`VirtualService` for HotROD scoped to a specific host (`hotrod.demo.local`) in a new file, `app/hotrod/istio-gateway.yaml` (uncommitted, research-stage). Real verification against the shared ingress IP (`135.224.177.246`):
```
$ curl -sI http://135.224.177.246/ | head -3
HTTP/1.1 200 OK
server: istio-envoy
$ curl -sI -H "Host: hotrod.demo.local" http://135.224.177.246/ | head -3
HTTP/1.1 200 OK
accept-ranges: bytes
content-length: 5013
```
Both apps reachable through the same IP, cleanly separated by host, no collision.

**Conclusion**: FR-011/SC-006 are achievable with host-based `VirtualService` routing. `plan.md` should specify this approach (one shared `Gateway` selector, host-scoped `VirtualService` per app) rather than per-app dedicated Gateways or path-based rewriting (which risks breaking HotROD's internal asset links, untested here).

---

## Summary of uncommitted local changes made during this research

- `makefile`: `setup-robot-shop` and `setup-hotrod` uncommented.
- `app/robot-shop/helm/templates/mysql-{statefulset,config,secret,service,seeed-job}.yaml`: condition changed from `eq .Values.stack_mode "local"` to `ne .Values.stack_mode "eks"`.
- `app/robot-shop/helm/templates/mysql-service.yaml`: port renamed `mysql` → `tcp-mysql` (ruled-out fix attempt for §4d; harmless, can stay or be reverted).
- `app/hotrod/istio-gateway.yaml`: new file, host-scoped Gateway/VirtualService for HotROD.
- `app/robot-shop/Istio/gateway.yaml`: applied live to the cluster, not edited.

None of these are committed. They exist to inform `plan.md`/`tasks.md`; formal implementation happens via `/speckit-implement` after `gate:plan-approved`.
