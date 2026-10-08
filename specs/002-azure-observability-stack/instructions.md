# Reviewer instructions — deploy and test story 002 on AKS

These steps build your own AKS cluster from scratch, deploy both demo apps
and the observability stack, and walk through what to check. Expected
output for each check is in [evidence.md](./evidence.md) (§ numbers below).

Your cluster is separate from the developer's. Resource names come from
your signed-in Azure identity, so nothing you create collides with
`sre-stack-d6d56b`.

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
git checkout 002-azure-observability-stack
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
| `AZURE_LOCATION` | leave empty for `eastus2` |

## 2. Create the cluster

```bash
make setup-cluster
```

This creates a resource group named `<your-identity>-aks-<code>` and a
cluster named `sre-stack-<code>`, with five node pools: system, app,
persistent, o11y and loadgen. It uses spot machines when the subscription
has spot quota, otherwise regular ones. If quota is short, it stops with a
message saying which quota, and creates nothing. When it finishes, your
`kubectl` context points at the new cluster.

Check it:

```bash
bash infra/scripts/cluster/verify-cluster-aks.sh
kubectl get nodes -L workload       # nodes in app, loadgen, o11y, persistent, and the system pool
```

## 3. Service mesh

```bash
make setup-istio                    # Istio 1.30.4 + the shared ingress gateway
```

## 4. Observability stack (this story)

```bash
make setup-aks-o11y                 # Postgres for Grafana, Prometheus+Grafana, Loki, Alloy, routes, dashboards
make setup-kiali-aks                # Kiali, separately; refuses if the mesh is not running
```

Run this before the demo apps: Robot Shop's chart renders ServiceMonitor
custom resources, and their CRDs are only on the cluster once
`setup-kube-prometheus-stack` (inside `setup-aks-o11y`) has run.

## 5. Demo applications

```bash
make setup-robot-shop               # Robot Shop, with in-cluster MySQL/MongoDB/RabbitMQ/Redis
make setup-hotrod                   # HotROD; also installs the optional OTel collector first
make setup-gateway                  # the routing step: Gateway/VirtualService for both apps
```

`make setup-gateway` must run before the dashboards can be reached: the
Grafana, Prometheus and Kiali routes bind to the Robot Shop gateway.

## 6. Traffic (optional, but the dashboards are empty without it)

There is no make target for the load generator yet (`setup-loadgen` is
commented out in the makefile), so apply it directly:

```bash
kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f scenarios/load-gen/load.yaml
```

It runs 10 clients against Robot Shop for an hour, on the loadgen pool.
Give it a few minutes before checking the dashboards.

## 7. Open the dashboards

```bash
make get-service-endpoints
```

This prints the Grafana, Prometheus and Kiali addresses. Grafana's user is
`admin`; the password is in the cluster:

```bash
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

Robot Shop is at `http://<ingress-IP>/`. HotROD needs a host header:
`curl -H "Host: hotrod.demo.local" http://<ingress-IP>/`.

---

## 8. What to check

### Automated

```bash
bash agent/scripts/verify-aks-observability.sh   # read-only
```

It should print `PASS` for every pod and end with
`observability verification: 0 failure(s)` (evidence.md §2).

```bash
make lint
```

It should print five `PASS` placement lines (evidence.md §7), then the
verifier's offline tests ending `9 checks, 0 failed`, and exit 0.
Loom's "spec pack is N days old" warnings are expected and not about this
story.

### By hand

| Check | How | Expect | evidence.md |
|---|---|---|---|
| Placement (FR-002) | `kubectl get pods -n monitoring -o wide` | Everything on `aks-o11y-*` nodes, except `alloy-*` and `*-node-exporter-*`, which run one pod per node on every pool | §2 |
| Endpoints (FR-004/005) | Open the three printed URLs | Grafana login page, Prometheus UI, Kiali UI | §3 |
| Datasources (FR-006) | Grafana → Connections → Data sources → Prometheus, Loki → "Save & test" | Both succeed | §5 |
| Logs (FR-002) | Grafana → Explore → Loki → `{namespace="robot-shop"}` | Robot Shop log lines with `app`, `pod`, `container`, `node` labels | §4 |
| Dashboards | Grafana → Dashboards → Application Dashboard | Request and error panels populated once the load generator has run | §9 |
| Kiali graph (FR-019) | Kiali → Traffic Graph → namespace `robot-shop` | Live graph of the Robot Shop services | §6 |
| Re-runs (FR-003) | Run `make setup-aks-o11y` and `make setup-kiali-aks` again | Exit 0; Helm says "upgraded" and kubectl says "unchanged"; no new pods | §11 |
| Missing routing (US1 scenario 5) | On a cluster where `make setup-gateway` has not run, run `make get-service-endpoints` | A plain "not reachable yet — the routing step hasn't run" message, no URLs | — |

### Accepted, not defects

- **Service Map panel is empty.** It reads Caretta metrics, and Caretta is
  out of scope on AKS.
- **Tempo datasource fails "Save & test".** The shared values provision it;
  Tempo is out of scope on AKS (AD-006).
- **Loki's datasource has no `/health` route** on this Grafana version, so
  the verify script checks it with a query instead.
- **Two Grafana pods.** Grafana's existing HA setting; both run on `o11y`.
- **Error-log panels for cart, catalogue, payment and user are empty.**
  Those services log no errors under normal load.

---

## 9. Troubleshooting

- **`make setup-aks-o11y` hangs at "Installing the Grafana Alloy log
  shipper…".** Helm is waiting on a chart download from GitHub's release
  server that never connects (seen twice during the evidence run). Press
  Ctrl-C and run `make setup-log-shipper-aks`, then
  `make setup-aks-o11y-routes setup-dashboards`. Everything is safe to
  re-run.
- **`make setup-robot-shop` fails with `no matches for kind "ServiceMonitor"
  in version "monitoring.coreos.com/v1"`.** The Prometheus Operator CRDs are
  not on the cluster yet — run `make setup-aks-o11y` first, then re-run
  `make setup-robot-shop`. The failed attempt leaves nothing behind, so no
  manual uninstall is needed.
- **`make get-service-endpoints` says the addresses are not reachable
  yet.** Run `make setup-gateway`.
- **`make setup-kiali-aks` says the service mesh is not running.** Run
  `make setup-istio` first.
- **`make setup-cluster` stops on quota.** The message names the quota and
  the numbers. Raise it under Azure Portal → Quotas → Compute, or set a
  different `AZURE_LOCATION`.

## 10. Clean up

```bash
make cleanup
```

This deletes the whole resource group, including the cluster and everything
running in it. It asks no further questions, so check that `.env` and your
`az` sign-in point at your own subscription before running it.
