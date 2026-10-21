# Quickstart — Live Validation Run for the Cart OOM Kill Story

The end-to-end run the builder does once, after implementation, and pastes into
the pull request as evidence (`evidence:attached`). Every step names the
requirement, success criterion or edge case it proves, so review traces it.

Commands are the contract in
[contracts/commands.md](contracts/commands.md); the state behind each step is
[data-model.md](data-model.md); the live findings any number here came from are
in [research.md](research.md).

## Prerequisites

1. A running AKS stack (`make setup-aks` or a previously started cluster):
   cluster reachable in the current kubeconfig context, monitoring installed and
   applied, shop deployed — **every shop pod `Running` and `2/2 Ready`** (ship,
   mysql and the seeder job can stall on a fresh setup; they are prerequisites,
   not part of this story).
2. The load generator running (the Azure setup only prints how to start it):
   ```
   kubectl -n loadgen get pods
   NAME                   READY   STATUS    RESTARTS   AGE
   load-<suffix>          1/1     Running   0          …
   ```
   (EC-001: without traffic the kill may take longer or never happen.)

## The run

### Part A — the fault, from start to clean recovery

3. **Status before anything** (FR-003 base case; SC-006):
   ```
   make aks-cart-oom-status
   RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)
   ```
4. **Start, timed** (FR-001, SC-001, SC-005):
   ```
   time make aks-cart-oom-start
   RESULT: fault active (cart container was killed for running out of memory within 60s)
   ```
   The `time` line must show under 90 s (live run: first kill at 15 s).
5. **The status the demo points at** (SC-002, SC-004, EC-007): within 3 min of
   step 4 the cart pod's restarts climb and the last state names `OOMKilled`
   (exit `137`), even while the cluster backs off between restarts:
   ```
   kubectl get pods -n robot-shop -l service=cart
   NAME                 READY   STATUS             RESTARTS   AGE
   cart-<suffix>        1/2     CrashLoopBackOff   4 (3m ago) …
   ```
6. **The dashboard section shows it** (FR-011 as clarified, SC-001): open the
   Application Dashboard in Grafana, the new **Restarts** section: the cart
   line in "Pod restarts" climbs, the out-of-memory stat reads 1 and the table names the cart pod. Screenshot
   this and the recovery one in step 10 — FR-011's two proofs.
7. **Status mid-fault, and idempotent re-start** (FR-005/SC-008, the
   2026-10-21 clarification while a back-off is under way):
   ```
   make aks-cart-oom-status
   RESULT: fault active (cart allowance 24Mi, restarts currently climbing / waiting for the next restart)
   make aks-cart-oom-start
   RESULT: fault already active
   ```
   The cluster is unchanged by both.
8. **Revert, timed** (FR-002, SC-003, SC-005):
   ```
   time make aks-cart-oom-revert
   RESULT: fault reverted (cart runs at the allowance the shop is installed with, no further out-of-memory kills)
   ```
   Within 60 s of step 8 cart runs at the chart's allowance. Note for the
   guide, stated plainly: the counter **resets to 0** on the new pod, which the
   demo reads as "no further kills" (research.md Finding 1).
9. **Status after revert and re-revert** (SC-008, FR-003):
   ```
   make aks-cart-oom-status
   RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)
   make aks-cart-oom-revert
   RESULT: fault not active; nothing changed
   ```
   Exiting `0` twice and not touching the object is the whole SC-008 check.
10. **The dashboard recovery** (SC-003, SC-004): within 2 min of step 8 the new
    section shows the out-of-memory flag line drop back to 0 and no further
    climbing for the cart row. Screenshot: same section as step 6, later.
    **Extra checks** (added after `/speckit-analyze`): (a) save every other
    Deployment's resources before step 4 and after step 9 and diff them: empty
    diff (FR-006); (b) time one whole cycle, start to recovery on the
    dashboard, with a stopwatch: at most 2 minutes (SC-004); (c) with the fault
    on, delete the cart pod and confirm the replacement is killed again and
    status still says active (EC-004), and that status still says active 5
    minutes later (FR-004).

### Part B — the refusals and the redeploy tolerance, without shop time lost

11. **Refusals** (FR-007, EC-005). Only the cluster `sre-stack-452138` is used
    (developer's decision 2026-10-21), so no other context is switched to. Run
    `KUBECONFIG=/dev/null make aks-cart-oom-status` → "Could not reach the
    cluster…", exit `3`. Then run the script from a scratch copy of the repo
    whose `.env` says `STACK_MODE=eks` → "This command is for Azure…", exit
    `3`. Same convention as 006: the refusal message and `Nothing was changed.`
    go to stderr and no `RESULT:` line is printed. The "not an AKS cluster"
    node-label check is checked by reading the script. (Start/revert share the
    same pre-checks.)
12. **Shop redeployed while the fault is active** (EC-002, FR-008's "shop was
    deployed again" case): set the fault active again with step 4, then run
    `make setup-robot-shop` and check:
    ```
    make aks-cart-oom-status
    RESULT: fault not active (the shop's allowance is correct); a leftover marker can be cleared with the revert command
    make aks-cart-oom-revert
    RESULT: fault not active; nothing changed (leftover marker cleared)
    ```
    This is research.md Finding 3 plus Finding 4 as a demonstration, not a new
    run.
13. **The cluster with the fault never started** (SC-010, FR-014): with the
    fault reverted, all pods at the chart's allowances and the load generator
    running, watch for 5 minutes in a timed loop: no shop pod shows
    `OOMKilled` and the Restarts section stays at 0.

### Part C — the owner's read-only guide passthrough (SC-007)

14. The owner, reading only `infra/azure/scenario-02/README.md`, follows one
    start → status → revert cycle without asking anything outside the guide.
    Look for what FR-012 lists: what must already be running, the two timed
    wait cycles, the `RESULT:` lines, where the dashboard section sits, and the
    two things that surprised a first-time presenter (the reset across revert
    and the growing back-off windows).

## Evidence collected in the PR

1. Verbatim terminal output of steps 3–14 (all `time` lines, all `RESULT:` lines, exit codes).
2. The two Grafana screenshots (step 6 and step 10).
3. `make lint` output.
4. `git diff --stat main` showing: changes only under
   `infra/azure/scenario-02/`, `monitoring/dashboards/application.yaml` and
   `docs/aks-explained.md`, plus the Azure-only lines added to `makefile` and
   `scenarios/README.md`, and
   **zero lines** changing `scenarios/scenario-01/`, `scenario-02/` (the EKS
   one), `scenario-04/` (FR-013/SC-009).

## What this run deliberately does NOT exercise live

Name for the Architect at the plan gate (and in the PR, as story 006's plan
did): the live run exercises two refusals (unreachable cluster, and
`STACK_MODE=eks` from a scratch repo copy; step 11); unreadable `.env`,
missing/unready shop Deployment, missing Helm release and the "not an AKS
cluster" node-label check are checked by reading the script alone. The
remaining EC-006 "cart is failing for its own reasons at its own allowance" is
verifiable only by a genuine production fault and is left to reading — its
status behaviour (the "but cart is failing for another reason — this fault is
not active" suffix) is the contract table row the run cannot hit.
