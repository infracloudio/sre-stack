# Data Model: HTTP Abort Fault for the Demo Shop on Azure

This story stores no data of its own. The "model" is the few things in the
cluster that the start, status and revert commands read or change, the states
they can report, and the checks they make before touching anything. Findings
referenced below are in [research.md](research.md).

## 1. The ratings routing rule — the only thing changed

The routing rule (Istio VirtualService) named `ratings` in namespace
`APP_NS` (`robot-shop` in `.env`). The shop's install creates it and Helm owns
it; this story never creates or deletes it, only adds or removes one part.

| Field | Value when fault is off (as installed) | Value when fault is on |
|---|---|---|
| `spec.hosts` | `[ratings]` | unchanged |
| `spec.http[0].route` | send to host `ratings` | unchanged |
| `spec.http[0].fault` | absent | `abort`: `httpStatus: 500`, `percentage.value: 100` |
| labels / annotations | `app.kubernetes.io/managed-by: Helm`, Helm release notes | unchanged |

Rules:
- **The fault is "set"** exactly when `spec.http[0].fault.abort` is present
  with status `500` and percentage `100`. Any other `fault` content is treated
  as "set by someone else" and left alone — the commands report it and stop
  (see state 5).
- **Revert restores the original exactly**: only the `fault` part is removed;
  `spec` then matches the installed rule character for character (Finding 1).
- A shop reinstall leaves the `fault` part in place while the chart's ratings
  rule file is unchanged (Finding 2).

## 2. The test-request check — what the commands observe

One `kubectl exec` into the `web` pod (container `web`) sends 10 requests to
`http://ratings/_health`, each limited to 3 seconds (Finding 3). Each answer is
recorded as a status code plus, for failures, the answer body.

| Answer kind | What it looks like | Meaning |
|---|---|---|
| Healthy | `200`, body `{"pdo_connectivity":true}` | ratings answered |
| Injected | `500`, body `fault filter abort` | this fault stopped it (Finding 4) |
| Other failure | anything else, e.g. `503 no healthy upstream`, timeout | ratings or the mesh failing for another reason |

The 10 answers are summarised as: all healthy, all injected, or mixed / other.

## 3. Fault states — what status reports

Combining the rule (section 1) with the check (section 2):

| # | Rule has this fault? | 10 answers | State reported | Exit |
|---|---|---|---|---|
| 1 | yes | all injected | **fault active** | 0 |
| 2 | no | all healthy | **fault not active** | 0 |
| 3 | no | any other | **ratings failing, not because of this fault** — plus what was seen | non-zero |
| 4 | yes | any other | **fault set but not taking effect** — plus what was seen | non-zero |
| 5 | different `fault` content | not checked | **ratings rule holds a fault this command did not set** — left unchanged | non-zero |

State 1 can hide a real ratings outage (Finding 4, case C); revert exposes it
through its own check.

## 4. State changes — start and revert

```text
            start                         revert
 not active ───────► active      active ───────► not active
 active     ───────► active      not active ───► not active   (no change)
   (no change)
```

| Command | From | Action on the rule | Then requires | On success | On failure |
|---|---|---|---|---|---|
| start | not active (state 2) | add the `fault` part | 10 of 10 injected | "fault active" | stop, print the answers seen; rule left with the fault so revert can remove it |
| start | active (state 1) | none | 10 of 10 injected | "fault already active" | as above |
| revert | active (state 1 or 4) | remove the `fault` part | 10 of 10 healthy | "fault removed" | stop, print the answers seen (e.g. ratings still down) |
| revert | not active (state 2 or 3) | none | 10 of 10 healthy | "fault was not active" | stop, print the answers seen |
| start / revert | state 5 | none | — | — | stop, rule unchanged |

Waiting: after a change, the check is retried until it passes or about 20 s
have gone by, so the command stays under SC-005's 30 s (the change took effect
within 5 s in Findings 1–3).

## 5. Pre-checks — when the commands refuse (FR-006, EC-005)

Run before reading or changing the rule, in this order; the first failure
stops the command with a message naming what is missing and changes nothing.

| # | Check | How it is seen | Example message |
|---|---|---|---|
| 1 | Settings say Azure | `.env` `STACK_MODE` is `aks` | "This command is for Azure (STACK_MODE=aks); .env says 'eks'." |
| 2 | Cluster reachable | `kubectl` can read the cluster | "Could not reach the cluster in the current kubectl context." |
| 3 | Cluster is an AKS cluster | nodes carry the label `kubernetes.azure.com/cluster` | "The current cluster is not an Azure (AKS) cluster." |
| 4 | Mesh running | deployment `istiod` in `istio-system` has a ready copy | "The service mesh (istiod) is not running; run 'make setup-istio'." |
| 5 | Shop installed | namespace `APP_NS` and rule `ratings` exist | "The demo shop is not installed; run 'make setup-robot-shop'." |
| 6 | Shop joined to the mesh | the `web` pod is running with an `istio-proxy` container | "The shop's web pod is not in the mesh, so the check would be meaningless." |
| 7 | Check tool present | `curl` runs inside the `web` container | "The web container has no curl; cannot check the result." |

Seen on the live cluster during planning: node label
`kubernetes.azure.com/cluster=MC_rijo-john-improving-com-aks-452138_sre-stack-452138_southind`,
`istiod 1/1`, namespace label `istio-injection=enabled`, `web` pod `2/2`.

## 6. Settings read

| Setting | Source | Value here | Used for |
|---|---|---|---|
| `STACK_MODE` | `.env` line 5 | `aks` | pre-check 1 |
| `APP_NS` | `.env` line 38 | `robot-shop` | where the rule and `web` pod live |
| `ISTIO_NAMESPACE` | `.env` line 32 | `istio-system` | pre-check 4 |

No new settings are added.
