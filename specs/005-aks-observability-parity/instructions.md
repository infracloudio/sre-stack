# Reviewer instructions — deploy and test story 005 on AKS

These steps build your own AKS cluster from scratch, deploy both demo apps
and the full observability stack (now including Tempo, Beyla and Caretta),
and walk through what to check. The command-by-command acceptance checks
live in [quickstart.md](./quickstart.md); the results recorded on the
developer's cluster (2026-10-14) are under T011 and T016 in
[tasks.md](./tasks.md).

This builds on story 002's guide
([../002-azure-observability-stack/instructions.md](../002-azure-observability-stack/instructions.md)).
Where the two differ, this file wins: story 005 adds traces, the service
map and automatic app measurements, and makes every AKS workload tolerate
spot nodes.

Your cluster is separate from the developer's. Resource names come from
your signed-in Azure identity, so nothing you create collides with
`sre-stack-452138`.

---

## 0. Before you start

**Azure access.** Activate your PIM role on the subscription. You need
rights to create resource groups and AKS clusters.

**Tools.** You need `az`, `kubectl`, `helm`, `kustomize`, `jq`, `git` and
`make`. From the repo root:

```bash
make install-check   # shows what is missing; changes nothing
make install         # installs missing tools and enables the pre-commit hooks
```

**Branch.**

```bash
git fetch origin
git checkout 005-aks-observability-parity
```

## 1. Sign in and configure

```bash
az login
az account set --subscription <subscription-id>
```

In `.env` (already tracked; only these three lines matter for AKS):

| Setting | Value |
|---|---|
| `STACK_MODE` | `aks` (already the default) |
| `AZURE_SUBSCRIPTION_ID` | your subscription ID, or leave empty to use the one `az` is signed in to |
| `AZURE_LOCATION` | leave empty for `southindia` |

## 2. One shot

```bash
make setup-aks
```

Runs, in order: cluster, Istio, the observability stack, Kiali, Robot
Shop, HotROD, the routing step, then prints the endpoints. It does not
start the load generator; it prints those commands at the end (step 4).
Every step is safe to re-run: if one fails, fix the cause and run
`make setup-aks` again. To run the steps one at a time, follow story 002's
guide, steps 2–5; only the observability step changed (step 3 below).

**Spot nodes.** When the subscription has spot quota, every node pool
except the system pool is created on spot machines, and Azure marks those
nodes so that only pods that explicitly allow it can run there. With
`STACK_MODE=aks`, the make targets pick AKS-only copies of the files that
carry that permission (plan.md, "Spot-mode tolerations"):

| Workload | AKS file |
|---|---|
| Grafana's Postgres + its database job | `infra/azure/grafana-postgres/` |
| Robot Shop (all 13 workloads) | `infra/azure/chart-values/robot-shop.yaml` |
| HotROD | `infra/azure/hotrod/` |
| Load generator | `infra/azure/load-gen/load.yaml` |
| Prometheus stack, Loki, OTel collector, Kiali | their existing `infra/azure/` files |

EKS and local use the shared files, unchanged.

## 3. Observability stack (this story)

```bash
make setup-aks-o11y
```

On top of story 002's Postgres, Prometheus+Grafana, Loki, Alloy, routes
and dashboards, this now installs three more, at pinned chart versions:

| Capability | Release | Chart | Runs on |
|---|---|---|---|
| Traces | `tempo` | `grafana-community/tempo` 3.1.0 | `o11y` pool |
| Automatic app measurements and traces | `beyla` | `grafana/beyla` 1.16.11 | every node |
| Service map | `caretta` | `groundcover/caretta` 0.0.16 | every node |

The routes step skips cleanly, with a message, when the service mesh is
not installed. If `kubectl` itself fails (expired sign-in, wrong context),
it now stops with an error instead of skipping.

## 4. Traffic (needed for every check in step 6)

Use the AKS copy of the load generator; the shared one cannot run on spot
nodes:

```bash
kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f infra/azure/load-gen/load.yaml
date -u   # note the start time; the checks look at the 5 minutes after it
```

It runs 10 clients against Robot Shop on the loadgen pool. Wait about 5
minutes before checking.

## 5. Open the dashboards

```bash
make get-service-endpoints
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

Grafana's user is `admin`. Robot Shop is at `http://<ingress-IP>/`.

---

## 6. What to check

### Automated

```bash
bash agent/scripts/verify-aks-observability.sh   # read-only
```

Expect `PASS` for every check, including four per-machine helpers
(`alloy`, `beyla`, `caretta`, node-exporter) "running on every node pool
(app, loadgen, o11y, persistent, system)", ending
`observability verification: 0 failure(s)`.

```bash
make lint
```

Expect exit 0, with `verify-observability offline tests: 11 checks, 0
failed` and `o11y-routes offline tests: 20 checks, 0 failed`. Loom's
"spec pack is N days old" warnings are expected and not about this story.

### By hand

Commands for each row are in quickstart.md (step numbers in the last
column).

| Check | Expect | quickstart |
|---|---|---|
| Releases | One each of `tempo-3.1.0`, `beyla-1.16.11`, `caretta-0.0.16` | §2 |
| Placement | `beyla` and `caretta` DaemonSets READY = node count, one pod per node on every pool incl. the system pool; Tempo, Prometheus, Grafana, Loki, OTel collector on `aks-o11y-*` nodes only | §2 |
| No stuck pods | `kubectl get pods -A --field-selector=status.phase=Pending` → "No resources found" | — |
| Service Map | Grafana → Application Dashboard → `Service Map` shows edges between Robot Shop services | §3a |
| Traces | Grafana → Explore → Tempo → `{resource.service.name="catalogue" && name="GET /products"}` returns traces; one opens to spans across `web` → `catalogue` | §3b |
| App measurements | Grafana → Explore → Prometheus → `sum(increase(http_server_request_duration_seconds_count{service_namespace="robot-shop"}[5m]))` > 0 | §3c |
| Existing panels | Request volume and success rate populated, as before this story | §4 |
| Re-runs | `make setup-aks-o11y` (or `make setup-aks`) again: exit 0, still one release of each, same chart versions | §5 |

On the developer's cluster: 118 service-map links, 20 matching traces,
about 6,390 requests counted by Beyla, 9.4 req/s mesh traffic, and four
back-to-back runs (`setup-aks-o11y` ×2, `setup-aks` ×2) all exit 0.

### Accepted, not defects

- **Error-log panels show lines that are not errors.** Each panel matches
  the word "error" anywhere in any container's log, so it picks up Istio
  sidecar start-up lines (`misc:error`), PHP `php.INFO` deprecation
  notices, and Instana "cannot connect to the agent" messages (Robot Shop
  looks for an Instana agent we do not run). The panels are unchanged by
  this story; tightening them touches the shared dashboard and is a
  follow-up story.
- **Error-log panels for cart, catalogue, payment and user are otherwise
  empty.** Those services log no errors under normal load. Run a
  `scenarios/scenario-0*` fault to see real errors.
- **An extra `caretta-grafana-dashboards` ConfigMap in `monitoring`.** The
  Caretta chart always creates it; it has no `grafana_dashboard` label, so
  Grafana never loads it.
- **Kustomize warns that `bases` is deprecated** during `setup-hotrod`.
  The warning comes from the shared `app/hotrod/kustomization.yaml`, which
  this story does not change.
- **Two Grafana pods.** Grafana's existing HA setting; both run on `o11y`.

---

## 7. Troubleshooting

- **A pod is `Pending` with "untolerated taint(s)"
  `kubernetes.azure.com/scalesetpriority`.** Something was applied from a
  shared (EKS/local) file instead of its AKS copy. Check `STACK_MODE=aks`
  in `.env` and re-run the make target; for the load generator, apply
  `infra/azure/load-gen/load.yaml`.
- **`make setup-aks-o11y` stops at the routes step with "Could not check
  for crd …".** `kubectl` could not reach the cluster. Check
  `kubectl config current-context` and `az login`, then re-run.
- **`make setup-aks-o11y` hangs downloading the Caretta or Alloy chart.**
  Both charts download from GitHub's release server, which has flaked
  before. Press Ctrl-C and re-run the target; everything is safe to re-run.
- **Tempo takes a while.** Its install waits up to 10 minutes
  (`--timeout 10m`) for the first start.
- For everything else, see story 002's troubleshooting section.

## 8. Clean up

```bash
make cleanup
```

This deletes the whole resource group, including the cluster and everything
running in it. It asks no further questions, so check that `.env` and your
`az` sign-in point at your own subscription before running it.
