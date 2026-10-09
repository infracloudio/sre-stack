# Research: Azure Observability Stack

**Branch**: `002-azure-observability-stack` · **Spec**: [spec.md](./spec.md)

Per constitution principle VIII, cheap checks (chart versions, file paths, make
targets, existing labels/taints) are settled here against the real repository
— no cluster needed. Anything that needs a live AKS cluster is listed at the
end, pending the developer running the command and pasting back the actual
output; no output block in this file is invented or "expected".

## Cheap checks (repo-only, no cluster)

1. **Observability pool label/taint** — confirmed: `workload=o11y` label,
   `o11y=true:NoSchedule` taint, `Standard_D4s_v5`, 2–3 nodes, user mode.
   Source: `specs/001-azure-aks-setup/data-model.md:99`
   (`| o11y | Standard_D4s_v5 | 2–3 | workload=o11y | o11y=true:NoSchedule | yes | User |`).
   This is what FR-002's "observability pool" and "workload-separation
   marking" resolve to.

2. **Existing AWS/local monitoring targets** — confirmed via
   `grep -n "^setup-loki\|^setup-optional-otel\|^setup-observability" makefile`:
   - `setup-observability: setup-db-grafana-psql setup-kube-prometheus-stack setup-loki setup-beyla setup-tempo setup-caretta setup-metric-server setup-istio-o11y-addons setup-dashboards` (makefile:133)
   - `setup-optional-otel` (makefile:135) — standalone, not part of `setup-observability`'s chain.
   - `setup-loki` (makefile:99) — its own target, already separate from the composite chain shape story 002 needs to mirror on Azure.

3. **AKS `setup:` chain is cluster-only today** — confirmed:
   ```
   setup:
   ifeq ($(STACK_MODE),aks)
   setup: setup-cluster
   else
     ...
   endif
   ```
   (makefile:52-58, comment: "the aks lifecycle is the empty cluster only... the workloads come in later stories"). This is the precedent the 2026-09-25 spec revision follows for keeping the monitoring stack a separate command.

4. **`setup-gateway` is no longer a no-op, and is not AKS-gated** — confirmed via `sed -n '164-168p' makefile`:
   ```
   setup-gateway:
   	kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
   	kubectl create namespace hotrod --dry-run=client -o yaml | kubectl apply -f -
   	kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n robot-shop
   	kubectl apply -f ./app/hotrod/istio-gateway.yaml -n hotrod
   ```
   It creates namespaces and Gateway/VirtualService objects only — no
   Deployments, no app workloads. Confirms the spec's Assumptions claim that
   depending on this step does not pull in application workloads.

5. **The shared observability routes bind to `robotshop-gateway`, created only by `setup-gateway`** — confirmed via `cat monitoring/istio-observability-addons/kiali-vs.yaml` (and the same `gateways:` block in `grafana-vs.yaml`/`prometheus-vs.yaml`):
   ```yaml
   spec:
     gateways:
     - robot-shop/robotshop-gateway
   ```
   This is the exact dependency the Architect's finding 1 named, and what the spec's "routing step" glossary term and FR-005 now describe.

6. **`setup-istio-o11y-addons` is one shared, cross-platform apply** — confirmed via `sed -n '126-133p' makefile`: `kubectl apply -f monitoring/istio-observability-addons/` — a single folder containing `grafana-vs.yaml`, `prometheus-vs.yaml`, `kiali-vs.yaml`, `kiali.yaml`, `istio-podmonitor.yaml`, `istio-servicemonitor.yaml` — used by both `setup-observability` (EKS) and `setup-local-o11y` (local). Kiali is already deployed by this shared apply on every platform that runs it today.

7. **Kiali's pinned version in the shared manifest** — confirmed via `head -60 monitoring/istio-observability-addons/kiali.yaml`: `helm.sh/chart: kiali-server-1.63.1`, `app.kubernetes.io/version: "v1.63.1"`, image `quay.io/kiali/kiali`. This is a pre-rendered static manifest (checked-in `helm template` output), not a live Helm release — reusing it on AKS would mean reusing v1.63.1 as-is; giving it its own Azure-specific pin would mean rendering a different version. Which one is compatible with Istio 1.30.4 (next finding) is a live-cluster question — see Live checks below.

8. **AKS runs a newer Istio than EKS/local** — confirmed via `specs/003-istio-gateway-kiali-aks/spec.md` R1: "The chart version is 1.30.4 on AKS (EKS/local remain on 1.17.2, which does not support Kubernetes 1.34)." Kiali v1.63.1 (finding 7) was almost certainly rendered against the 1.17.2-era control plane; whether it also works against 1.30.4 is unverified and is a live-cluster question.

9. **AKS-specific gateway/cleanup scripts already scaffolded by story #104 (003)** — confirmed via `sed -n '234-247p' makefile`: `cleanup-istio`/`cleanup-gateway` branch to `infra/scripts/cluster/cleanup-istio.sh` / `cleanup-gateway.sh` under `STACK_MODE=aks`. `setup-gateway` itself (finding 4) has no such branch — it's one shared target for all platforms.

10. **No existing "Azure-specific chart-values" folder convention yet for monitoring** — confirmed via `ls monitoring/chart-values/`: `caretta.yaml loki.yaml metric-server.yaml otel-collector.yaml prometheus-values.yaml tempo.yaml yace.yaml` — all shared, no per-cloud suffix. `infra/azure/` (via `find infra/azure -type f`) has only `gp2-storageclass.yaml`. FR-008's "own folder" for Azure-specific settings has no established directory to reuse yet; Phase 1 design picks one.

11. **An existing no-cluster test harness precedent exists, but tests CLI behavior, not file content** — confirmed via `agent/tests/azure/`: `fake-az.sh`, `fake-kubectl.sh`, `run-offline-tests.sh`, and per-scenario scripts under `agent/tests/azure/scenarios/` (from story 001). This harness asserts on a fake CLI's call log (what was invoked, how many times, in what order) for `setup-cluster-aks.sh`/`cleanup-cluster.sh`/`verify-cluster-aks.sh`. FR-011's deployment check is a different shape — it needs to inspect chart-values/manifest YAML content (node selector, toleration, label) rather than a call log — so it can borrow this harness's scenario/PASS-FAIL structure but needs its own assertion style. This is a Phase 1 design decision, not resolved here.

12. **Loki's Helm chart moved repos; pin corrected to 18.13.7 (latest GA as of the second Architect review)** — confirmed via web search + `artifacthub.io/packages/helm/grafana-community/loki`: as of 2026-03-16, Grafana's OSS Loki chart moved from the old `grafana/helm-charts` repo to `grafana-community/helm-charts` (Promtail and Grafana Agent, used by the old chart, are both past their EOL — 2026-03-02 and 2025-11-01 respectively — matching the Architect's review citation). This finding originally pinned `18.13.5`; the second Architect review (reviewer ABRAJ11) ran its own live Helm index check and found `18.13.7` is now the newest release, superseding `18.13.5` — that check is accepted as the live evidence here rather than re-fetched, per the same reuse pattern this file already applies to other stories' recorded live output. **Pin corrected to `18.13.7`.** This story's `setup-aks-loki` target adds the new repo (`https://grafana-community.github.io/helm-charts` or the `oci://ghcr.io/grafana-community/helm-charts/loki` registry — exact add command confirmed in tasks.md/implementation, not needed here) and pins chart `loki` at `18.13.7`, distinct from the existing `setup-loki` target's chart/repo, which stays untouched (FR-007/FR-017). FR-007 asks for "the current stable release chosen when this story is built," not a specific number frozen in research — so this file states the pin as of the last review pass rather than claiming permanent "latest" status, to avoid the same staleness this correction just fixed. Sources: [Upgrade from the Loki Helm chart to the Community Helm chart](https://grafana.com/docs/loki/latest/setup/upgrade/upgrade-to-community/), [loki · grafana-community/grafana-community](https://artifacthub.io/packages/helm/grafana-community/loki).

13. **Correction found during a later review pass: the new Loki chart does not bundle a log shipper.** The existing AWS/local `monitoring/chart-values/loki.yaml` bundles Promtail as a sub-chart (`promtail.enabled: true`, `monitoring/chart-values/loki.yaml:37-49`) — that's what actually ships logs into Loki today, tolerating only `o11y=true:NoSchedule` so it free-schedules on the untainted `system`/`app` pools plus the tainted `o11y` pool via that toleration, matching the spec's clarification ("the shipper runs wherever it can — cluster system machines, the app pool, and the observability pool"). Reading Grafana's own migration doc (`grafana.com/docs/loki/latest/setup/upgrade/upgrade-to-community/`) confirms the new `grafana-community/loki` chart (finding 12) removed the self-monitoring/shipping path entirely — no Promtail, no bundled replacement, only a one-line pointer to "consider Grafana Alloy," with no chart, version, or config given. Left as originally planned, `setup-aks-loki` would ship a Loki that never receives any logs — this was missed in the first pass of this plan/research and would have satisfied FR-006's "connected and healthy" check while silently failing FR-002's actual log-shipper requirement.
    - **Standalone `grafana/promtail` chart** still exists on ArtifactHub (latest `6.17.1`, app `3.5.1`) and would need the least new work (near-identical values to the existing bundled config), but Grafana has explicitly deprecated and frozen it, prints a deprecation warning on install, and does not recommend it for new deployments — confirmed via web search of the chart's ArtifactHub listing and related GitHub issues.
    - **Decision**: use `grafana/alloy` (the actively-maintained successor Grafana itself points to), not the deprecated standalone Promtail chart, for the new AKS-specific log shipper — an actively-maintained chart is the right choice for new work even though it costs more setup than reusing the frozen one. Latest chart version confirmed via ArtifactHub: `1.13.0` (`artifacthub.io/packages/helm/grafana/alloy`, repo `https://grafana.github.io/helm-charts`, DaemonSet controller by default).
    - **Not yet live-verified**: Alloy's config language (River/Alloy config, not YAML scrape configs like Promtail) is new to this repo. The shape needed — `discovery.kubernetes "pods"` → `discovery.relabel` (add namespace/pod/container/node labels) → `loki.write` (push to the new Loki's endpoint) — matches Grafana's own official pattern (`grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/`), but no config has actually been applied against this cluster yet. This is a genuine open item, not a proven fact — see the new verification task in tasks.md; it must be confirmed live (logs actually arrive in Loki) before this story converges, not assumed from documentation alone. Sources: [Collect Kubernetes logs and forward them to Loki | Grafana Alloy documentation](https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/), [alloy · grafana/grafana](https://artifacthub.io/packages/helm/grafana/alloy), [promtail · grafana/grafana](https://artifacthub.io/packages/helm/grafana/promtail).

14. **Correction found while checking the second Architect review's FR-006 datasource claim: Grafana's Loki datasource is already provisioned by a different, existing mechanism than the one the review named — and it stays intact if the new chart's service name matches.** The review's finding characterized the old `loki-stack` chart's own bundled `templates/datasources.yaml` (activated via that chart's `sidecar.datasources.enabled`) as "the only thing that creates Grafana's Loki datasource today," and warned that the new `grafana-community/loki` chart has no equivalent feature. Checking this repo's actual config directly (not assuming from the chart's general capabilities) shows that path is explicitly turned off here: `monitoring/chart-values/loki.yaml:88-92` sets `grafana.enabled: false` and `grafana.sidecar.datasources.enabled: false` — the bundled Grafana-integration sidecar has never been active in this repo. The datasource that actually exists today comes from a separate mechanism entirely: `monitoring/chart-values/prometheus-values.yaml:183-189`, which configures `kube-prometheus-stack`'s own Grafana subchart with `additionalDataSources: [{name: loki, access: proxy, orgId: 1, type: loki, url: http://loki:3100, version: 1}, ...]` — Grafana's native static-provisioning feature, independent of whichever chart Loki itself is installed from. `setup-kube-prometheus-stack` (and this file) stay unchanged in the AKS chain (plan.md Approach item 1), so **this datasource entry will already be created on AKS with no new task**, regardless of which Loki chart backs it — as long as the URL it hardcodes (`http://loki:3100`) still resolves.
    - This nuances, rather than confirms, the review's specific mechanism claim — but the underlying risk it flagged is still real: whether `http://loki:3100` resolves depends entirely on what Service name/port the new `grafana-community/loki` chart actually renders, which is exactly the review's separate `gateway.enabled: true` finding (new default creates a `loki-gateway` Service, changing the topology from the flat name every existing consumer — this `additionalDataSources` entry, the old bundled Promtail's `clients: url` in `monitoring/chart-values/loki.yaml:43`, and the new Alloy shipper's planned `loki.write` target — all assume).
    - **Decision**: rather than add a new ConfigMap-based datasource (which would risk a second, redundant "loki"-named datasource alongside the one `additionalDataSources` already creates) or leave the gateway topology unresolved, `infra/azure/chart-values/loki.yaml` (T003) explicitly sets `fullnameOverride: loki` and `gateway.enabled: false`. This forces the new chart to render its query/push Service under the exact same flat name and port (`loki:3100`) every existing consumer already hardcodes — the shared `additionalDataSources` entry, and the new Alloy config's `loki.write` target (T004) — with no changes needed to any shared file and no new datasource-provisioning task. This is a values decision within this story's own new file, not a claim about runtime behavior; whether the datasource actually reports healthy once this is live is exactly what plan.md Verification #4 / tasks.md T019 already check — no new verification task is needed either.
    - Not contradicted by anything live-verified so far (L1-L4 never queried Grafana's datasources page) — this remains a design decision grounded in current repo content, not yet a live-proven fact; T019 is where it gets proven.

15. **Checking a third review pass's claim that T003's four-field values file is incomplete — confirmed for three of the fields, one nuanced.** Attempted to fetch `grafana-community/helm-charts`'s `charts/loki/values.yaml` (chart `18.13.7`) directly to check its actual defaults rather than trust the claim at face value; the raw fetch returned content that was internally inconsistent partway through (a well-formed values-file section, then a stretch that looked like template code, not values) — not reliable enough to stand on its own, and this sandbox has no `helm` binary to run `helm template` directly. What follows is confirmed from the parts of that fetch that were clean and consistently formatted, cross-checked against the chart's own inline documentation comments (which read as genuine, not corrupted, at every location cited below); the parts I could not fully trust are marked as such rather than asserted:
    - **Confirmed**: `singleBinary.replicas` defaults to `0`, even though `singleBinary.enabled` defaults to `true` — meaning an unmodified install would render an enabled StatefulSet with zero replicas, i.e. no running Loki at all. `singleBinary.replicas: 1` must be set explicitly. This is the most serious of the three — not a template error, a silent zero-pod install.
    - **Confirmed**: `loki.storage.type` defaults to `s3`, not `filesystem`. This story has no object-storage credentials in scope (Out of Scope explicitly excludes secrets-manager work) and needs none for a small demo install, so `loki.storage.type: filesystem` must be set explicitly.
    - **Confirmed**: `loki.schemaConfig` defaults to `{}` (empty), and the chart's own comment at that key states plainly that "a real Loki install requires a proper schemaConfig defined above this, however for testing or playing around you can enable useTestSchema" — the chart ships a `loki.testSchemaConfig` specifically for this. Rather than hand-write a production `schemaConfig` (index periods, object-store backend, schema version) that this story's small AKS demo has no real need for, the chart's own sanctioned path for exactly this situation is `loki.useTestSchema: true`. This satisfies the review's underlying concern (an empty schema breaks the render) without the added design surface of a hand-rolled schema.
    - **Confirmed**: `lokiCanary.enabled` defaults to `true` (a DaemonSet) — a real extra workload, matching the review's separate finding below.
    - **Not fully trusted from my own fetch, given the inconsistency noted above**: whether `chunksCache`/`resultsCache` truly default to enabled. Accepted here on the review's own authority (presumably from a real `helm template` run) rather than re-asserted as independently confirmed — same reuse-of-a-reviewer's-live-check pattern this file already applies to the Loki version bump (finding 12). T003's own `helm template` verify step is the actual live confirmation either way.
    - **A further nuance the review didn't need to resolve, but worth recording**: the chart's `write`/`read`/`backend` components (its SimpleScalable-mode targets) default to `enabled: true` with non-zero replicas, which sounds like it needs a `replicas: 0` override too — but each carries its own comment stating it "Requires `loki.deploymentMode` to be set to `SimpleScalable`" to actually render. Since this story's values file leaves `deploymentMode` at the chart's own default (`Monolithic`) — stated explicitly in T003 for clarity rather than left implicit — those three components should not render at all, regardless of their own `enabled`/`replicas` defaults. This reasoning is not independently proven live (no `helm template` run here); T003's own verify step is exactly where it gets confirmed or corrected.
    - **Decision**: `infra/azure/chart-values/loki.yaml` (T003) adds `deploymentMode: Monolithic` (explicit, matches the chart default), `singleBinary.replicas: 1`, `loki.storage.type: filesystem`, `loki.useTestSchema: true`, `lokiCanary.enabled: false`, `chunksCache.enabled: false`, `resultsCache.enabled: false` — alongside the existing `nodeSelector`/`tolerations`/`fullnameOverride`/`gateway.enabled: false` fields (findings 1, 14). The canary and both caches are disabled rather than given their own `o11y` placement config: none is required by any FR, and disabling three extra workloads is simpler and lower-risk than adding placement config to each, consistent with this story's existing minimal-footprint choices (skipping Tempo/Beyla/Caretta, skipping `setup-metric-server`, staying on Monolithic rather than SimpleScalable/Distributed mode).

16. **Finding 15 re-checked with a real `helm template` (2026-10-05), replacing its untrusted raw fetch — two of its claims were wrong, and the placement keys were wrong too.** `helm` is available on the developer's machine; the earlier "no helm binary" applied to a different sandbox, and chart values are a cheap check that never qualifies for substitution (principle VIII). Chart pulled with `helm pull loki --repo https://grafana-community.github.io/helm-charts --version 18.13.7`, then rendered offline.
    - **Placement keys**: 18.13.7 has **no top-level `nodeSelector`/`tolerations`** — they exist per component (`singleBinary.*`, `gateway.*`, …) and under `defaults.*`. The top-level shape copied from the old `loki-stack` file (finding 1) would be silently ignored. Placement moves to `singleBinary.nodeSelector` / `singleBinary.tolerations`.
    - **Wrong in finding 15**: `read`/`write`/`backend` *do* matter in Monolithic mode. First render with the planned values:
      `Error: execution error at (loki/templates/validate.yaml:35:4): You have more than zero replicas configured for both the monolithic and simple scalable targets. If this was intentional change the deploymentMode to the transitional 'Monolithic<->SimpleScalable' mode`
      Fix: `read.replicas: 0`, `write.replicas: 0`, `backend.replicas: 0`.
    - **Not anticipated**: disabling the canary breaks the chart's own test hook:
      `Error: execution error at (loki/templates/validate.yaml:6:4): Helm test requires the Loki Canary to be enabled`
      Fix: `test.enabled: false`.
    - **Final render, exit 0**: Services `loki` (port 3100), `loki-headless`, `loki-memberlist`; one StatefulSet `loki`, `replicas: 1`, `nodeSelector workload: o11y`, toleration `key: o11y` / `effect: NoSchedule`, a 10Gi volume; no canary or cache workloads. Confirms finding 14's flat `loki:3100` name.
    - **Found, not fixed**: the volume claim renders with no `storageClassName`, so on AKS it uses the cluster default rather than `gp2` (`infra/azure/gp2-storageclass.yaml` is not marked default). The existing EKS/local values never name a class either, so this is pre-existing behaviour — a follow-up story, not this one.
    - **Alloy (1.13.0, `helm show values`)**: placement lives under `controller.nodeSelector` / `controller.tolerations`, not top-level. T004 corrected to match.
    - **Also needed**: `loki.auth_enabled` defaults to `true` (chart `values.yaml:554`), which makes Loki reject any request without a tenant header. Neither the shared Grafana datasource (`url: http://loki:3100`, no header) nor Alloy sends one, so `loki.auth_enabled: false` is required — the same single-tenant behaviour the old `loki-stack` install had.
    - **Decision**: T003's values file is sixteen settings in total (listed in plan.md Approach item 2), validated by rendering, not by reading the chart's docs.

## Live-cluster checks

### L1 — Current cluster state (run 2026-09-25)

Command:

```bash
kubectl get nodes -L workload --show-labels=false
kubectl get pods -n istio-system -o wide
kubectl get svc -n istio-system istio-ingressgateway
helm list -A
```

Actual output (verbatim):

```
NAME                                 STATUS   ROLES    AGE     VERSION    WORKLOAD
aks-app-36164085-vmss000000          Ready    <none>   2d18h   v1.34.11   app
aks-app-36164085-vmss000001          Ready    <none>   2d18h   v1.34.11   app
aks-app-36164085-vmss000002          Ready    <none>   2d18h   v1.34.11   app
aks-loadgen-12473643-vmss000000      Ready    <none>   2d18h   v1.34.11   loadgen
aks-nodepool1-10557749-vmss000000    Ready    <none>   2d18h   v1.34.11
aks-o11y-87088337-vmss000000         Ready    <none>   2d18h   v1.34.11   o11y
aks-o11y-87088337-vmss000001         Ready    <none>   2d18h   v1.34.11   o11y
aks-persistent-32573892-vmss000000   Ready    <none>   2d18h   v1.34.11   persistent
aks-persistent-32573892-vmss000001   Ready    <none>   2d18h   v1.34.11   persistent

NAME                                    READY   STATUS    RESTARTS   AGE     IP             NODE
istio-ingressgateway-8677d95c5b-5fbrv   1/1     Running   0          2d18h   10.244.0.139   aks-nodepool1-10557749-vmss000000
istiod-d5f79b88d-7bhpb                  1/1     Running   0          2d18h   10.244.0.220   aks-nodepool1-10557749-vmss000000

NAME                   TYPE           CLUSTER-IP    EXTERNAL-IP       PORT(S)
istio-ingressgateway   LoadBalancer   10.0.49.224   135.224.177.246   15021:31943/TCP,80:32394/TCP,443:30578/TCP

NAME                     NAMESPACE    REVISION  CHART                          APP VERSION
caretta                  monitoring   1         caretta-0.0.16                 v0.0.16
istio-base               istio-system 1         base-1.30.4                    1.30.4
istio-ingressgateway     istio-system 1         gateway-1.30.4                 1.30.4
istiod                   istio-system 1         istiod-1.30.4                  1.30.4
loki                     monitoring   1         loki-stack-2.10.3              v2.9.3
opentelemetry-collector  monitoring   5         opentelemetry-collector-0.173.1 0.160.0
prometheus-stack         monitoring   1         kube-prometheus-stack-52.0.0   v0.68.0
roboshop                 robot-shop   4         robot-shop-1.1.0
tempo                    monitoring   1         tempo-1.24.4                   2.9.0
```
(`aks-managed-*` kube-system addon releases omitted — irrelevant here.)

**What this tells us** (facts, not yet interpreted into decisions):

- The cluster, the four labelled node pools (o11y currently at 2 of its 2–3
  range), Istio (istio-base/istiod/gateway all 1.30.4, matching finding 8),
  and the ingress gateway with an external IP are all already up.
- Contrary to the makefile's "aks lifecycle is the empty cluster only"
  comment (finding 3), this cluster already has `loki`, `prometheus-stack`,
  `tempo`, `caretta`, and `opentelemetry-collector` installed as Helm
  releases in `monitoring`, plus `roboshop` in `robot-shop` — someone ran
  the individual (shared, not-yet-AKS-specific) sub-targets directly against
  this cluster outside the composite chain. This is exploratory/manual state
  from before this story, not evidence of an AKS-specific chain that already
  exists.
- `loki`'s installed chart is `loki-stack-2.10.3` / app `v2.9.3` — this is
  the existing AWS/local pin (`monitoring/chart-values/loki.yaml`'s chart),
  **not** the "own AKS-specific settings file, pinned to latest GA" FR-007
  requires. Confirms FR-007 is not yet satisfied by anything currently on
  the cluster — expected, since that's this story's job, not something
  already done.
- `roboshop` (robot-shop) is already deployed, which means Robot Shop's app
  workload is running on this cluster right now — a fact for the plan/PR to
  flag, since this story's Out-of-Scope line assumes no app workloads are
  deployed by this story; one already is, from earlier manual testing or
  story 004 work. Whether `setup-gateway` has also been run (creating
  `robotshop-gateway`) is checked next (L2).
- `helm list -A` says nothing about Kiali, but Kiali is deployed via plain
  `kubectl apply`, not Helm — its absence from this list doesn't tell us
  whether it's running. Checked next (L2).

### L2 — Kiali/gateway/metrics-server state (run 2026-09-25)

Command and actual output (verbatim):

```
$ kubectl get deploy,svc -n monitoring -l app=kiali
No resources found in monitoring namespace.

$ kubectl get gateway,virtualservice -A
NAMESPACE    NAME                                            AGE
hotrod       gateway.networking.istio.io/hotrod-gateway      2d
robot-shop   gateway.networking.istio.io/robotshop-gateway   2d

NAMESPACE    NAME                                           GATEWAYS                HOSTS                   AGE
hotrod       virtualservice.networking.istio.io/hotrod      ["hotrod-gateway"]      ["hotrod.demo.local"]   2d
robot-shop   virtualservice.networking.istio.io/cart                                ["cart"]                45h
robot-shop   virtualservice.networking.istio.io/catalogue                           ["catalogue"]           45h
robot-shop   virtualservice.networking.istio.io/mongodb                             ["mongodb"]             45h
robot-shop   virtualservice.networking.istio.io/payment                             ["payment"]             45h
robot-shop   virtualservice.networking.istio.io/ratings                             ["ratings"]             45h
robot-shop   virtualservice.networking.istio.io/redis                               ["redis"]               45h
robot-shop   virtualservice.networking.istio.io/robotshop   ["robotshop-gateway"]   ["*"]                   2d
robot-shop   virtualservice.networking.istio.io/shipping                            ["shipping"]            45h
robot-shop   virtualservice.networking.istio.io/user                                ["user"]                45h

$ kubectl get pods -n kube-system | grep -i metrics-server
metrics-server-64d77894df-9nrzp   2/2   Running   0   2d18h
metrics-server-64d77894df-j4hz6   2/2   Running   0   2d18h

$ kubectl get clusterrole system:metrics-server -o yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations: {kubectl.kubernetes.io/last-applied-configuration: ...}
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: system:metrics-server
```

**What this tells us**:

- Kiali, `kiali-vs`, `grafana-vs`, and `prometheus-vs` are all absent — the
  shared `setup-istio-o11y-addons` apply (finding 6) genuinely has not run
  on this cluster. No double-install has happened yet; the risk the
  Architect named (finding 3) is about what happens if this story naively
  reuses that shared apply, not something already gone wrong here.
- `robotshop-gateway` and `hotrod-gateway` (and their per-app `VirtualService`s)
  already exist — `setup-gateway` (finding 4) has already been run on this
  cluster, and `robotshop-gateway` is up. This means the routing step
  precondition FR-005 depends on is *already met on this cluster right
  now* — so applying the monitoring `VirtualService`s here today would bind
  to a real Gateway immediately. On a genuinely fresh cluster (nobody has
  run `setup-gateway` yet), the spec's edge case (FR-005/US1 scenario 5)
  still applies.
- `roboshop` (finding L1) is a real, currently-running app workload on this
  cluster from earlier manual/story-004 work — noted for the PR, not a
  defect of this story.
- AKS's built-in `metrics-server` add-on is running in `kube-system`
  (2/2 Ready), owned by AKS's own `addonmanager` (`mode: Reconcile`) via
  `ClusterRole system:metrics-server`. Its own reconciliation would fight
  a second installer of the same cluster-scoped name.
- **`setup-metric-server`'s actual collision was already run live against
  this exact cluster during story #108's (004) research**, and is recorded
  verbatim in `specs/004-deploy-demo-apps-aks/research.md` §6, so it is not
  re-run here — re-running it would just reproduce the same recorded
  failure against the same unchanged addon:
  ```
  Error: unable to continue with install: ClusterRole "system:metrics-server" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata...
  ```
  Confirmed real by that story, and explicitly flagged there as "out of
  scope for this story (belongs to #101's AKS observability work" — i.e.
  handed to this story to resolve. **Decision needed in plan.md**: skip
  `setup-metric-server` on AKS entirely (AKS's own addon already serves the
  same API), rather than try to fix the collision — reusing what the
  platform already provides is simpler and lower-risk than fighting an
  addon-manager-reconciled resource.

### L3 — Kiali v1.63.1 against Istio 1.30.4 (run 2026-09-25)

Command and actual output (verbatim, abridged — full log had routine
Kiali-cache-refresh and Kubernetes `Endpoints`-deprecation warnings only,
no errors):

```
$ kubectl apply -f monitoring/istio-observability-addons/kiali.yaml
serviceaccount/kiali unchanged
configmap/kiali unchanged
clusterrole.rbac.authorization.k8s.io/kiali-viewer unchanged
clusterrole.rbac.authorization.k8s.io/kiali unchanged
clusterrolebinding.rbac.authorization.k8s.io/kiali unchanged
role.rbac.authorization.k8s.io/kiali-controlplane unchanged
rolebinding.rbac.authorization.k8s.io/kiali-controlplane unchanged
service/kiali unchanged
deployment.apps/kiali unchanged

$ kubectl apply -f monitoring/istio-observability-addons/kiali-vs.yaml
virtualservice.networking.istio.io/kiali-vs unchanged

$ kubectl get pods -n monitoring -l app=kiali
NAME                   READY   STATUS    RESTARTS   AGE
kiali-658fc489-tt6rn   1/1     Running   0          150m

$ kubectl logs -n monitoring -l app=kiali --tail=40
2026-09-25T07:46:58Z INF Server endpoint will start at [:20001/kiali]
2026-09-25T07:46:58Z INF Starting Metrics Server on [:9090]
2026-09-25T08:35:58Z INF Kiali Cache: Updating cache with new token
2026-09-25T08:35:58Z INF [Kiali Cache] Waiting for cluster-scoped cache to sync
2026-09-25T08:35:58Z INF [Kiali Cache] started
(repeats every ~45 min; only other lines are non-fatal "v1 Endpoints is
deprecated in v1.33+" warnings — no errors, no crash loop)

$ curl -sI http://135.224.177.246/kiali/
HTTP/1.1 200 OK
content-type: text/html
vary: Accept-Encoding
server: istio-envoy
```

**Everything reported "unchanged"** — these exact manifests, unmodified,
were already applied to this cluster before this check (age 150m; not by
this story's work, and not present when L2 checked minutes earlier with
`-l app=kiali` on `deploy,svc` — the L2 query likely used the wrong label
key, since finding below shows the Deployment does carry `app: kiali`).

**What this tells us, decisively**:

- Kiali v1.63.1 (finding 7) **runs healthy against Istio 1.30.4** (finding 8)
  on real AKS, unmodified — 1/1 Running, no restarts, clean cache-sync logs,
  no compatibility error of any kind. The version-mismatch risk the
  Architect's finding 3 raised does not materialize in practice.
- It is reachable end-to-end through the exact dependency chain the spec
  describes: the existing `robotshop-gateway` (created by the routing step,
  finding 4/L2) plus the shared, unmodified `kiali-vs.yaml` → `curl` through
  the shared ingress IP returns `200 OK` from `istio-envoy`.
- **Decision for plan.md**: the service mesh dashboard reuses the existing
  shared manifests (`kiali.yaml` + `kiali-vs.yaml`) as-is on AKS — no
  separate Azure-specific version pin needed. This resolves the Assumptions
  entry that left this open; FR-018 ("compatible version... no duplicate
  install") is satisfied by reuse, not a new pin.
- Checked separately (cheap, repo-only) — `monitoring/istio-observability-addons/kiali.yaml:568-573`
  already sets:
  ```yaml
  tolerations:
    - key: "o11y"
      value: "true"
      effect: "NoSchedule"
  nodeSelector:
    workload: "o11y"
  ```
  on the Kiali Deployment itself — the shared manifest already satisfies
  FR-002's observability-pool placement without any AKS-specific edit.
  Confirming the pod actually landed on an `o11y` node (not just that the
  manifest asks for it) is the last live check below.

### L4 — Kiali's actual node placement (run 2026-09-25)

Command and actual output (verbatim):

```
$ kubectl get pod -n monitoring -l app=kiali -o wide
NAME                   READY   STATUS    RESTARTS   AGE    IP             NODE
kiali-658fc489-tt6rn   1/1     Running   0          178m   10.244.6.162   aks-o11y-87088337-vmss000001
```

**Confirmed**: the pod is running on `aks-o11y-87088337-vmss000001` — one of
the two `o11y`-labelled, `o11y=true:NoSchedule`-tainted nodes (finding 1 /
L1). FR-002's placement requirement is met by the shared manifest as-is,
verified live, not just asserted from the YAML.

## Phase 0 summary — decisions this story's plan.md will carry forward

1. **Monitoring stack and service mesh dashboard each get their own command**, run after `setup-cluster`/`setup-istio`/`setup-gateway`, per the spec's 2026-09-25 clarification — no change to the composite `setup:` chain's AKS branch (still cluster-only).
2. **`setup-metric-server` is skipped on the AKS path.** AKS already runs its own `metrics-server` addon (`kube-system`, addon-managed); installing a second one collides on `ClusterRole system:metrics-server` (proven in `specs/004-deploy-demo-apps-aks/research.md` §6, same cluster, not re-run here). The AKS observability chain omits this step rather than trying to fix the collision.
3. **The service mesh dashboard reuses the existing shared manifests (`monitoring/istio-observability-addons/kiali.yaml` + `kiali-vs.yaml`) unmodified** — no Azure-specific version pin. Proven live: Kiali v1.63.1 runs healthy against Istio 1.30.4, is reachable through the existing `robotshop-gateway` (200 OK), and its Deployment already carries the correct `o11y` `nodeSelector`/toleration, confirmed by where the pod actually landed (L3/L4).
4. **The routing step (`setup-gateway`) is a real, separate prerequisite**, not automatic — on this cluster it had already been run (L2), but the spec's edge case (fresh cluster, routing not yet run) is real and must be handled by the monitoring command's own screens too, per FR-005/US1 scenario 5, not just Kiali's.
5. **Loki, the metrics store, Tempo, and Caretta are already installed on this cluster using the shared (non-Azure-specific) chart pins** (L1) — from earlier manual work, not from any AKS-specific target that exists yet. This story still needs to build the real AKS-specific Loki target per FR-007 (latest GA, own settings file); the currently-installed `loki-stack-2.10.3`/`v2.9.3` release is not that target and will need to be reconciled (reinstalled under the new target, or left as-is and pointed at by it — a plan-time decision) rather than assumed correct.
6. **Robot Shop is already deployed on this cluster** (`roboshop` release, L1) — a fact for the PR, not a defect; this story's "no application workloads" boundary is about what *this story* deploys, and it deploys none.
7. **The log shipper needs a new, separate component: `grafana/alloy` (chart `1.13.0`)**, added as its own target chained into `setup-aks-o11y`, tolerating only `o11y=true:NoSchedule` (mirrors the existing Promtail config's tolerations exactly, so it free-schedules on `system`/`app` and reaches `o11y` via the toleration — matches FR-002 and the spec's log-shipper clarification). Not Promtail's standalone chart (deprecated, frozen, not recommended for new work — finding 13). **Not yet live-verified** — this is a design decision grounded in documentation, not a proven-live fact like findings 1-11; a live task to confirm logs actually arrive in the new Loki is required before this story converges.
8. **User Story 3 (optional telemetry collector, FR-010) needs no new engineering.** The existing `setup-optional-otel` target has no `STACK_MODE` branching and its chart-values already use the generic `workload: o11y` placement (`monitoring/chart-values/otel-collector.yaml:231-237`) — and it was already run successfully against this exact AKS cluster during story 004's research ("Ran it explicitly; installed cleanly," `specs/004-deploy-demo-apps-aks/research.md` §5). This was missed in the first pass of this plan — it needs a verification task and a documentation line, not a new target.
9. **Grafana's Loki datasource (FR-006) needs no new provisioning task, only a naming decision in the new Loki values file.** The shared `monitoring/chart-values/prometheus-values.yaml`'s existing `additionalDataSources` entry (finding 14) already creates it, unchanged, on every platform including AKS — provided the new `grafana-community/loki` chart's rendered Service is named to match the URL that entry already hardcodes (`http://loki:3100`). `infra/azure/chart-values/loki.yaml` sets `fullnameOverride: loki` and `gateway.enabled: false` to guarantee that match, sidestepping the chart's `gateway.enabled: true` default (which would otherwise introduce a differently-named `loki-gateway` Service) with no change to any shared file.
10. **The new Loki chart needs five more values than the two placement fields to actually run** (finding 15): `singleBinary.replicas: 1` (the chart's own default is `0` — an enabled StatefulSet with no pods), `loki.storage.type: filesystem` (default is `s3`, out of scope for this story), `loki.useTestSchema: true` (default `schemaConfig` is empty, and the chart's own comment recommends this exact toggle over hand-writing a production schema for "testing or playing around"), plus `lokiCanary.enabled: false`, `chunksCache.enabled: false`, and `resultsCache.enabled: false` to turn off three chart-bundled extra workloads that default to on and would otherwise need their own `o11y` placement config to satisfy FR-002.
