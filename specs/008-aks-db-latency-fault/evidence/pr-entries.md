# Evidence for the pull request (story 008, slow database fault on AKS)

Cluster `sre-stack-452138`, run on 2026-10-22/23 (UTC 19:44 to 20:12).

## Evidence list (quickstart.md, "Evidence collected in the PR")

1. Terminal output of the run: `quickstart-run.txt` (baselines, start 12.6 s, status 5.1 s, revert 11.1 s, requests, 2-minute overlapping run with 0 errors, data check, refusals, redeploy, database restart).
2. Screenshots: `01-baseline.png` (panel, before), `02-fault-on.png`, `03-after-revert.png` (one panel showing baseline, rise and recovery within about 2 minutes), `04-slow-requests.png` (Slow shop requests dashboard), `05-trace-spans.png` (a 3.54 s shipping request; the `SELECT cities` span is 2.51 s).
3. `lint-output.txt`: `make lint` exit 0.
4. `scope-check.txt`: zero lines changed in `scenarios/scenario-01/`, `-02/`, `-04/`; zero deletions in `makefile` and `scenarios/README.md`; `monitoring/dashboards/mysql.yaml` has the new panel plus three whitespace-only line changes required by the yamllint ratchet (D7); `docs/aks-explained.md` has the listed corrections (5 lines changed, 46 added).

## Deviations

See the table at the end of `tasks.md` (D1 to D7).

## Not exercised, or not explained

- The "not an AKS cluster" refusal and an unready `mysql-0` (checked by reading the script).
- Step 18, "slow for another reason", and status "On but not slow": checked by reading the script. During the database restart in step 17, status exited 1 for about 3.5 minutes while the database re-created its data; the message was not captured (my command hid it), so which line it printed is not recorded.
- Why the database re-creates its data on a restart although the data directory is a volume claim (research Finding 14).
- The revert check after a restart measured shipping 1.9 s against the 2 s limit (one run, load generator on); the margin is thin when the database is still warming up.
- Step 21 (SC-009): done by the developer on 2026-10-23 (about 01:44 to 01:50 IST), following the guides for one full cycle on the cluster. See "Step 21 result" below.
- Step 19 ran before the fault cycle in this run (150 requests, 0 slow, max 1.93 s, plugin Off), not after a fresh database.

## Open follow-up

- The "MySQL Average Query Time" panel reads about 220 ms during the fault with the load generator running (about 50 ms normally), because it averages every statement. A per-query line would show about 2.8 s (checked in Prometheus: shipping city query 2.77 s, all others about 0 s). Proposal: add a "Slowest query's average time" line (see the follow-up in `tasks.md`). Left as is by the developer's decision on 2026-10-23; to be revisited.
- Step 21: see "Step 21 result" below.

## Probe false alarm (found in step 21): fixed

`status` right after a revert reported "slow for another reason: shipping 3.3s" (exit 1). With the fault off and the load generator on, three parallel `/match` scans took up to 3.0 s (queued on MySQL's 200m CPU limit). Fix: two shipping requests one after another, ratings still parallel (deviation D6 in `tasks.md`). After the fix, 18 of 18 statuses were clean over three start/status/revert cycles, including three statuses right after each revert (`quickstart-run.txt`). Cost: status with the fault on takes 9.1 to 9.5 s against the 10 s limit (SC-007); thin margin.

## Step 21 result (SC-009)

Done by the developer, 2026-10-23, about 01:44 to 01:50 IST, following the guides for one full cycle (status, start, watch, revert, status). Findings, all handled:

1. Right after the start the panel and the trace tables looked empty: the tables need about a minute and the panel about 2 minutes. Fixed: the scenario-03 README section 5 now says so and tells the reader to set the time range.
2. The "MySQL Average Query Time" panel read only about 220 ms during the fault (it averages every query). Not changed, by the developer's decision; recorded as an open follow-up in `tasks.md`.
3. `status` right after a revert reported "slow for another reason" (exit 1) and was clean on the next try. Fixed in the probe: deviation D6 in `tasks.md`.

The developer saw the queries and the rise on the dashboards and the cycle completed.
