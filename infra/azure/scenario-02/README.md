# Scenario 02 on Azure: the cart runs out of memory

Three commands for the demo shop running on Azure (AKS): one starts the fault,
one reports whether it is on, one removes it. This is the Azure `scenario-02`
folder. It is not the EKS scenario "Increased DB connection count" in
`scenarios/scenario-02/`, and the scripts in `scenarios/scenario-01/`,
`scenarios/scenario-02/` and `scenarios/scenario-04/` are the EKS way; use this
guide on Azure.

## 1. What it does

Every container on Kubernetes has a **memory allowance**: the most memory it may
use. The shop's **cart** container is normally allowed `100Mi` and uses about
`31Mi`. The start command lowers cart's allowance to `24Mi`, which is less than
cart needs. When a container goes past its allowance the cluster stops it by
force; this is an **out-of-memory kill**, and the pod shows the reason
`OOMKilled`. Kubernetes then starts the container again, it is killed again, and
so on. Each start counts as one **restart**, and the number of them is the
pod's **restart count**. Cart is the worked example: its restart count climbs
every time the cluster kills it.

Only the cart container's memory allowance changes, plus one marker note
(an annotation) on the cart Deployment that says this fault put it there. No
other shop service is touched. Nothing changes the number of shoppers, and
nothing removes the fault on a timer.

## 2. What must already be running

1. `make setup-aks` has finished.
2. Every shop pod is Ready:

   ```bash
   kubectl get pods -n robot-shop
   ```

3. The load generator is running. It sends the shop its steady stream of
   shoppers, and cart only runs out of memory when shoppers use it:

   ```bash
   kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f infra/azure/load-gen/load.yaml
   kubectl get pods -n loadgen
   ```

   The pod should say `Running`. To confirm shoppers are really reaching cart,
   check that its log is moving (lines about `/cart/...`, `/add/...`):

   ```bash
   kubectl logs -n robot-shop deploy/cart -c cart --tail=5
   ```

   Without traffic, cart may sit idle and the first kill can take longer than a
   minute. Each run of the load generator ends after one hour and Kubernetes
   starts it again by itself, so traffic can pause briefly once an hour.

## 3. Start the fault

```bash
make aks-cart-oom-start
```

It lowers cart's memory allowance, writes the marker, then waits up to 60
seconds for the cluster to kill the cart container for running out of memory:

```text
Lowering the cart memory allowance to 24Mi (cart container only)...
deployment.apps/cart resource requirements updated
deployment.apps/cart annotated
Waiting up to 60s for the cluster to kill the cart container for running out of memory...
RESULT: fault active (cart container was killed for running out of memory within 60s)
```

The last line is the result line, `RESULT: fault active (…)`. Running it again is
safe: it makes no change and ends with `RESULT: fault already active`.

## 4. Check the state

```bash
make aks-cart-oom-status
```

This never changes anything and answers within a few seconds. The four answers:

| Line | Meaning |
|---|---|
| `RESULT: fault active (cart allowance 24Mi, …)` | The lowered allowance and the marker are both in place. The pod may be waiting for its next restart. |
| `RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)` | Cart runs at the allowance the shop is installed with. The normal, healthy answer. |
| `RESULT: the cart allowance (<value>) was not set by this fault — it is not active` | Someone lowered the allowance by hand. The command leaves it alone, and exits with code 1. Revert puts it back. |
| `RESULT: fault not active (the shop's allowance is correct); a leftover marker can be cleared with the revert command` | The marker is still there but the allowance is already back to normal, for example after the shop was installed again. |

If cart is killed for running out of memory even at its normal allowance, the
first line ends `but cart is failing for another reason — this fault is not
active`. Look at cart's own logs; the fault is not the cause.

```text
Not shown: the live run could not reproduce this case. It needs cart to fail for its own reasons, which is checked by reading the script only.
```

## 5. What to watch

In Grafana, open the **Application Dashboard** and scroll down to the
**Restarts** row:

- **"Pod restarts (last 5 minutes)"**: one line per pod that restarted. The
  cart line climbs while the fault is on. This row covers every pod in every
  namespace, so a different pod failing shows here too.
- **"Pods killed for running out of memory (last 5 minutes)"**: turns red and
  counts the pods that were killed for running out of memory and restarted in
  the last 5 minutes. `0` when healthy. It clears about 5 minutes after the
  last kill.
- **"Pods restarting or killed (last 5 minutes)"**: a table naming each pod,
  its restarts, and whether its last kill was out of memory.

Grafana's admin password:

```bash
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

On the command line:

```bash
kubectl get pods -n robot-shop -l service=cart
```

The pod's status alternates between `OOMKilled` and `CrashLoopBackOff` (the
cluster waiting before it starts the container again). The wait grows after
each kill, `10s`, then `20s`, `40s`, `1m20s`, so the restart count climbs fast
at first and then in bigger steps.

```text
NAME                    READY   STATUS             RESTARTS      AGE
cart-769b547b68-mk8jr   1/2     CrashLoopBackOff   3 (15s ago)   66s
```

## 6. Remove the fault

```bash
make aks-cart-oom-revert
```

It reads the memory allowance the shop is installed with from the shop's Helm
release (the record of what the shop was installed with), puts it back, removes
the marker, and waits up to 60 seconds for one cart pod to be running with no
fresh kill:

```text
Restoring the cart memory allowance the shop is installed with (requests 50Mi, limits 100Mi)...
deployment.apps/cart resource requirements updated
deployment.apps/cart annotated
Waiting up to 60s for cart to run cleanly...
RESULT: fault reverted (cart runs at the allowance the shop is installed with, no further out-of-memory kills)
```

The restart count goes back to 0. That is expected: putting the allowance back
replaces the cart pod with a new one, and a new pod starts counting from zero.
Read 0 as "a fresh, healthy pod", not as "nothing happened". The dashboard
clears in about 2 minutes.

## 7. Good to know

- Installing the shop again (`make setup-robot-shop`) puts the normal
  allowance back and so ends the fault, but the marker stays until revert
  clears it (the fourth answer in section 4).
- Nothing removes the fault on a timer, and anyone with access to the cluster
  can run revert.
- Each command finishes within 90 seconds, including its own check.
- The commands refuse and change nothing when they are not on Azure
  (`STACK_MODE` is not `aks`), the cluster cannot be reached, the cluster is
  not an Azure (AKS) cluster, the shop's cart is not installed, or the shop's
  Helm release is missing.
- When you run a command through `make`, any failure makes `make` itself exit
  with code 2 and print `Error <n>`, where `<n>` is the script's own code. The
  script's codes, which you see if you run
  `bash infra/azure/scenario-02/cart-oom-kill.sh <command>` directly: 0 means
  done and the check agreed, 1 means the check disagreed with what was asked
  (or, for status, the allowance was lowered by someone else), 2 means a wrong
  argument, 3 means a refusal.
