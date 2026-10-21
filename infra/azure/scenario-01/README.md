# Scenario 01 on Azure: the ratings service fails

Three commands for the demo shop running on Azure (AKS): one starts the fault,
one reports whether it is on, one removes it. The scripts in
`scenarios/scenario-01/` are for EKS, not Azure; use this guide on Azure.

## 1. What it does

The shop's **ratings** service answers every request with error 500 until you
remove the fault. Only ratings is touched. The web page's own calls to ratings
fail as a result, so you will also see errors there. Nothing changes the number
of shoppers, and nothing removes the fault on a timer.

## 2. What must already be running

1. `make setup-aks` has finished.
2. Every shop pod is Ready:

   ```bash
   kubectl get pods -n robot-shop
   ```

3. The load generator is running. It sends the shop its steady stream of
   shoppers, and without it the dashboards stay quiet:

   ```bash
   kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f infra/azure/load-gen/load.yaml
   kubectl get pods -n loadgen
   ```

   The pod should say `Running`. To confirm shoppers are really reaching the
   shop, check that the log is moving (a few lines of activity, not an error):

   ```bash
   kubectl logs -n loadgen deploy/load --tail=5
   ```

   You can also open the Grafana **Application Dashboard** and look for a
   non-zero request rate. An empty dashboard means no traffic, not a failed
   fault. Each run of the load generator ends after one
   hour and Kubernetes starts it again by itself, so traffic can pause briefly
   once an hour.

## 3. Start the fault

```bash
make aks-ratings-abort-start
```

It adds the fault, then sends 10 test requests from the web pod to ratings and
expects all 10 to fail:

```text
Adding the fault to the ratings routing rule (every request answered with error 500)...
Checking: 10 test requests from the web pod to ratings...
  500 500 500 500 500 500 500 500 500 500
RESULT: fault active
```

Running it again is safe: it makes no change and ends with
`RESULT: fault already active`.

## 4. Check the state

```bash
make aks-ratings-abort-status
```

This never changes anything. The two normal answers:

| Line | Meaning |
|---|---|
| `RESULT: fault active …` | The fault is set and ratings is failing because of it. |
| `RESULT: fault not active …` | No fault, and ratings answers normally. |

Anything else exits with an error:

| Line | Meaning |
|---|---|
| `RESULT: ratings failing, not because of this fault` | No fault is set, but ratings is failing anyway. The lines above it show what came back. |
| `RESULT: fault set but not taking effect` | The fault is in the routing rule, but the test requests did not fail as expected. |
| `RESULT: ratings rule holds a fault this command did not set` | Someone put a different fault on ratings. The command leaves it alone. |

While the fault is on, status cannot tell whether ratings itself is healthy,
because no request reaches it. Revert's own check shows that.

## 5. What to watch

In Grafana, open the **Application Dashboard**:

- **"Non-2xx Responses by Service"**: the `ratings ->` tile turns red.
- **"5xxs"**: the line goes up.

Both show the change after about 15 seconds. Some things on other dashboards
will mislead you:

- The Istio Service Dashboard's **"Server …"** panels and the ratings logs stay
  blank, because the error is produced before the request reaches ratings.
- The `user ->` tile is always red. It counts normal `404` answers and has
  nothing to do with this fault.
- **"Global Success Rate"** may show `NaN`.

## 6. Remove the fault

```bash
make aks-ratings-abort-revert
```

It removes the fault, restores the ratings routing rule exactly as installed,
and sends 10 test requests expecting 10 normal answers:

```text
RESULT: fault removed
```

The errors on the dashboard clear in about 60 seconds. If ratings still fails
after the fault is gone, revert says
`RESULT: ratings still failing after the fault was removed — not caused by this fault`.

## 7. Good to know

- The fault survives `make setup-robot-shop`. Re-installing the shop does not
  remove it; only revert does.
- Nothing removes the fault on a timer, and anyone with access to the cluster
  can run revert.
- Each command finishes within 30 seconds.
- The commands refuse and change nothing when they are not on Azure
  (`STACK_MODE` is not `aks`), the cluster cannot be reached, the cluster is
  not an Azure (AKS) cluster, the service mesh is not running, the shop is not
  installed, the shop's web pod is not part of the mesh, or the web container
  has no `curl`.
- When you run a command through `make`, any failure makes `make` itself exit
  with code 2 and print `Error <n>`, where `<n>` is the script's own code. The
  script's codes, which you see if you run
  `bash infra/azure/scenario-01/ratings-abort.sh <command>` directly: 3 means a
  refusal, 1 means the check disagreed with what was asked, 2 means a wrong
  argument.
