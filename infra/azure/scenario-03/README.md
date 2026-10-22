# Scenario 03 on Azure: the shop's database is slow

Three commands for the demo shop running on Azure (AKS): one starts the fault,
one reports whether it is on, one removes it. This is the Azure `scenario-03`
folder. It is not the EKS scenario "Increased DB connection count" in
`scenarios/scenario-02/`, and it is not the EKS "Scenario 3" (AZ or datacenter
zone down). The scripts in `scenarios/scenario-01/`, `scenarios/scenario-02/`
and `scenarios/scenario-04/` are the EKS way; use this guide on Azure.

## 1. What it does

The shop keeps its shipping cities and its product ratings in one MySQL
database, the `mysql-0` pod. The start command makes the database answer three
of its questions slowly: it adds a fixed wait of **2.5 seconds** to the two
shipping lookups and **0.5 seconds** to the ratings lookup. The answers are
identical to before, nothing fails, and no shop data is written; shoppers just
wait longer for the shipping cost and for ratings. Nothing removes the fault on
a timer.

## 2. What must already be running

1. `make setup-aks` has finished.
2. Every shop pod is Ready:

   ```bash
   kubectl get pods -n robot-shop
   ```

3. The load generator is running. It sends the shop its steady stream of
   shoppers, and the dashboards only show the slowdown while shoppers use the
   shop:

   ```bash
   kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f infra/azure/load-gen/load.yaml
   kubectl get pods -n loadgen
   ```

   The pod should say `Running`. To confirm shoppers are reaching the shop,
   check that the shipping log is moving:

   ```bash
   kubectl logs -n robot-shop deploy/shipping --tail=5
   ```

   Each run of the load generator ends after one hour and Kubernetes starts it
   again by itself, so traffic can pause briefly once an hour.

## 3. Start the fault

```bash
make aks-db-latency-start
```

It installs the database's query-rewriting plugin if it is missing, adds the
three rules, then sends test requests from the `web` pod for up to 30 seconds
until the lookups are slow:

```text
Installing the Rewriter plugin in mysql-0...
Adding the three rules and loading them...
Waiting up to 30s for the lookups to turn slow...
RESULT: fault active (shipping lookup 3.5s, ratings lookup 1.0s)
```

The first line appears only when the plugin was missing (a fresh database). The last line is the result line, `RESULT: fault active (…)`. Running it again
is safe: it makes no change and ends with `RESULT: fault already active`.

## 4. Check the state

```bash
make aks-db-latency-status
```

This never changes anything and answers within a few seconds. The answers:

| Line | Meaning |
|---|---|
| `RESULT: fault active (shipping lookup <n>s, ratings lookup <n>s)` | The rules are on and the test requests were slow. |
| `RESULT: fault not active` | The rules are off and the lookups are at normal speed. The healthy answer. |
| `RESULT: the fault is partly set (<n> of 3 rules enabled)` | Someone changed a rule by hand. Exit code 1. Start puts all three back; revert turns them all off. |
| `RESULT: the fault is set but the lookups were not slow: …` | The rules are on but the test requests were not slow. Exit code 1. |
| `RESULT: fault not active, but the lookups are slow for another reason: …` | The rules are off but the lookups are slow anyway. Exit code 1. Look at the database itself; this fault is not the cause. |

```text
Not shown: the last two lines could not be reproduced live. They need a second way to slow the database, so they are checked by reading the script only.
```

## 5. What to watch

In Grafana (set the time range to the last 15 or 30 minutes). The tables fill
within about a minute of the start and the panel within about 2 minutes, so do
not judge the result in the first few seconds:

- **Database dashboard**, panel **"MySQL Average Query Time"**: about 50
  milliseconds normally with the load generator running, and it rises about
  tenfold (to roughly 0.5 seconds) while the fault is on, because only three
  kinds of query are slowed and the rest still answer fast.
- **Azure Scenario Dashboards → "Slow shop requests"**: two tables listing
  shipping requests slower than 2 seconds and ratings requests slower than
  0.5 seconds. Pick a trace ID to open the step-by-step view of that request;
  the database step is most of its time.

Grafana's admin password:

```bash
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

## 6. Remove the fault

```bash
make aks-db-latency-revert
```

It turns the three rules off (the plugin stays installed) and sends test
requests for up to 30 seconds until the lookups are at normal speed:

```text
Disabling the rules...
Waiting up to 30s for the lookups to turn normal...
RESULT: fault removed (shipping lookup 0.9s, ratings lookup 0.3s)
```

Run again when nothing is on, it changes nothing and ends with
`RESULT: fault not active, nothing changed`. The dashboards recover within
about 5 minutes.

## 7. Good to know

- Installing the shop again (`make setup-robot-shop`) leaves the fault on, and
  reloads the shop's data, which takes about 2 minutes.
- Do not restart MySQL during a demo (for example by deleting `mysql-0`): it
  wipes the fault and takes the shop down for about 2 minutes. A cluster stop
  and start does the same; status then says `fault not active`.
- Anyone with access to the cluster can run status or revert.
- Each command finishes within 60 seconds, including its own check; status
  within 10.
- The commands refuse and change nothing when they are not on Azure
  (`STACK_MODE` is not `aks`), the cluster cannot be reached, the cluster is
  not an Azure (AKS) cluster, `mysql-0` is not running, or the `web` pod is
  missing or has no `curl`.
- When you run a command through `make`, any failure makes `make` itself exit
  with code 2 and print `Error <n>`, where `<n>` is the script's own code. The
  script's codes, which you see if you run
  `bash infra/azure/scenario-03/db-latency.sh <command>` directly: 0 means done
  and the check agreed, 1 means the check disagreed, 2 means a wrong argument,
  3 means a refusal.
