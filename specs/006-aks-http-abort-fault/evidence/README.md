# Evidence: quickstart run (T010), 2026-10-14

Cluster: existing research cluster `sre-stack-452138` (not a fresh `make setup-aks`; affects SC-009).
Full terminal output: `quickstart-run.txt`.

| Quickstart step | Result |
|---|---|
| 1 baseline (5 min with load) | ratings 500 increase[5m] = 0; red tile is `user` 404s. Screenshot `01-baseline.png` |
| 3 start | 10 x 500, `RESULT: fault active`, exit 0, 2.5 s (20:25:31 to 20:25:33) |
| 4 dashboard | first ratings 500 in Prometheus 20:25:40 (7 s); `ratings ->` tile red (120) and 5xxs 0.151 ops/s at ~77 s. Screenshot `02-fault-on.png` |
| 5, 7 | start again: `fault already active`; status `fault active`, exit 0 |
| 6 | ratings 10 x 500; web, cart, catalogue, user, payment, shipping 10 x 200 |
| 7a | ratings restarted with fault on: still `fault active` |
| 8 | `make setup-robot-shop` (Helm revision 3): still `fault active` |
| 9 revert | 10 x 200, `RESULT: fault removed`, exit 0, 2.6 s (20:30:11 to 20:30:14) |
| 10 dashboard | ratings 500 rate 0 at +26 s, increase[1m] 0 at +61 s. Screenshot `03-after-revert.png` (2 min after): no ratings tile |
| 11, 12 | revert again: `fault was not active`; status `fault not active` |
| 13 | `KUBECONFIG=/dev/null`: refuses, script exit 3 (make prints `Error 3`), nothing changed |
| 14 | no diff in scenarios 01/02/04; no removed lines in makefile/.env |

Notes
- Step 4 timing was read from Prometheus, not by timing the dashboard by eye.
- In `03-after-revert.png` "5xxs" reads 0.551 ops/s: these are `shipping` 503s after step 8's reinstall (chart sets shipping back to 200m CPU; the seeder was re-running), not ratings (ratings 500 rate = 0).
- After the cluster restart, three cluster-only fixes were needed outside this story: `web`/`user`/`dispatch` rollout restart (sidecar injection race), and the Grafana `grafana` Postgres database recreated.
