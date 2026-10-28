# Evidence for the story #122 pull request (robot-shop alert rules)

Run date: 2026-10-28. Cluster: AKS sre-stack-452138, started at 16:02 and kept running.

## Evidence files (this folder)

- `quickstart-run.txt`: tool versions, the gate label, cluster state, wiring checks, static checks, rule apply (twice), the monitoring rerun summary, and the rules API.
- `lint-before.txt`, `lint-after-doc-update.txt`, `lint-output.txt`: `make lint` before the apply, after the doc updates, and at the end. All exit 0.
- `scope-before.txt`, `scope-check.txt`: the committed, unstaged, staged and untracked file lists, plus the shared-file diffs (all empty). The Bookinfo rule is still present.
- `rules-api.json` (inactive, quiet), `rules-api-cart.json`, `rules-api-database.json`, `rules-api-both.json`: the rules API during each run. Active alerts show their `service` and `namespace`, and each rule has a valid `severity`.
- `replicas-unavailable-rules.yaml`, `replicas-unavailable-test.yaml`, `replicas-unavailable-test.txt`: local stateful-set test (mysql has 1 wanted copy and 0 ready). Passes.
- `traffic-guards-rules.yaml`, `traffic-guards-test.yaml`, `traffic-guards-test.txt`: local zero-traffic, very-few-requests and high-traffic cases for the three request-based rules. Passes.
- `quiet-30m-poll.txt`: 30 minutes with no fault. All polls empty, and the 30-minute count is empty.
- `redeploy-poll.txt`: cart and shipping restarts. Nothing fired (one pending entry, cleared on the next poll).
- `cart-fault-run.txt`, `cart-fault-poll.txt`, `cart-revert-poll.txt`: cart memory fault, its start, poll and clear.
- `db-fault-run.txt`, `db-fault-poll.txt`, `db-revert-poll.txt`: slow-database fault, its start, poll and clear.
- `no-traffic-precheck.txt`, `no-traffic-drain.txt`, `no-traffic-run.txt`, `no-traffic-cart-fault-run.txt`, `no-traffic-cart-poll.txt`, `no-traffic-revert-poll.txt`: no-traffic check.
- `both-faults-run.txt`, `both-faults-poll.txt`, `both-revert-poll.txt`, `both-faults-result.txt`: both faults at once, and the clear times.
- `limit-change-run.txt`, `limit-decisions.txt`: the ratings limit change check (0.10 to 0.12, in use in about 70 seconds, no chart upgrade), restored from git, and the "no limit changes" decision.
- `final-status.txt`: fault status (both not active), load generator (1/1), positive shop traffic query, and no alerts firing.
- `setup-aks-o11y-rerun.txt`: full monitoring setup rerun, exit 0.
- `monitoring-before/shop-traffic-query.txt`: the positive shop traffic query (see the gap below).
- `screenshots/`: `alerts-page-quiet.png` (all inactive), `alerts-page-cart-fault-firing.png` (four firing), `alerts-page-database-fault-firing.png` (two firing), `alerts-page-both-faults-firing.png` (five firing).

## Departures from plan.md (each with its reason)

1. **Both faults at once: five alerts, not six.** `RobotShopShippingSlowRequests` cannot fire while the cart is down, because no requests reach shipping and the rule needs at least 30 requests in its window. The developer accepted this on 2026-10-28. Research Finding 9, plan.md "Departures", quickstart check 9, tasks T027 and spec EC-006 are updated to match. Shipping's own firing is proven alone in the slow-database check (fired 3m31s after the start).
2. **Monitoring baseline taken after the rule apply, not before.** The shop-traffic query was recorded after the rules were applied (plan asked for before). The dashboard screenshot and trace steps were not taken (see the gap below).
3. **Helm release revision moved from 3 to 4** during the `make setup-aks-o11y` rerun ("Upgrade complete"). The rule object's resourceVersion did not change (557210). This is reported as it happened, as the plan asks.
4. **Start-up residue.** `RobotShopHTTPErrors` fired for about a minute during the cluster start, while `web` was restarting. It cleared on its own. Three shop deployments (`payment`, `rabbitmq`, `web`) failed their first start because `istiod` was not ready yet. They were restarted and became Ready.
5. **Cart fault, no traffic: `RobotShopReplicasUnavailable` flapped.** It fired at 18:13:51, dropped to pending at 18:15:21, and fired again by 18:16. This is within the 5-minute window and is recorded as seen.
6. **Limit change check used a temporary value.** The ratings limit was changed from 0.10 to 0.12 for the check and restored from git (see `limit-change-run.txt`).

## Three plain statements

1. **SC-009 is not proven on a new cluster.** It has wiring evidence only (`make -n setup-aks` lists the rule step after the monitoring chart). Developer decision on 2026-10-28.
2. **The limits come from one run each, plus this verification run.** The verification run confirms the cart, database and no-traffic results. The limits were not tuned again.
3. **The database branch of the no-ready-copy rule is covered only by a local `promtool` test** (`replicas-unavailable-test.txt`). Redeploys were tested for cart and shipping only, and not for the databases.

## Gaps still open

- **Dashboard and trace evidence (FR-017, plan check 7 step 5).** The "Slow shop requests" dashboard screenshot and an opened trace were not taken. They need Grafana, and the Grafana login is a credential I do not handle. Someone with access needs to take them.
- **The cluster is still running.** It costs money while it runs. Stopping it is a decision for the developer (`az aks stop`).
