# Quickstart — Live Validation Run for the Slow Database Fault

The end-to-end run the builder does once, after implementation, and pastes into the pull request as evidence (`evidence:attached`). Every step names the requirement, success criterion or edge case it proves, so review traces it.

Commands are the contract in [contracts/commands.md](contracts/commands.md); the state behind each step is [data-model.md](data-model.md); the live findings any number here came from are in [research.md](research.md).

## Prerequisites

1. A running AKS stack, with every shop pod `Running` and `2/2 Ready` (MySQL `3/3`). If a deployment sits at `FailedCreate` after a cluster start (the mesh injector was not ready yet), run `kubectl rollout restart` on it. These are prerequisites, not part of this story.
2. The load generator running (the Azure setup only prints how to start it): `kubectl -n loadgen get pods`. Without traffic the dashboards stay flat (EC-001) and the `ratings` table stays empty (Finding 14).
3. Record the baselines before anything: `cities` row count and checksum, `codes` rows, and the two shipping output hashes (Finding 12).

## The run

### Part A — the fault, from start to clean recovery

4. **Status before anything** (SC-007): `make aks-db-latency-status` prints `RESULT: fault not active`, in under 10 s.
5. **Start, timed** (FR-001, SC-001, SC-006): `time make aks-db-latency-start` prints `RESULT: fault active (shipping lookup …, ratings lookup …)`, in under 60 s.
6. **The requests** (SC-001, SC-002, SC-003, FR-005): 10 shipping and 10 ratings requests, all answered and all slow; 10 requests to a part of the shop that does not use the database, all at normal speed.
7. **Status mid-fault and idempotent re-start** (FR-004, SC-010): `RESULT: fault active …`, then `RESULT: fault already active`, with nothing changed.
8. **The dashboards** (FR-010, FR-015, FR-016, SC-014, SC-015): on the Database dashboard the average query time panel rises within 2 minutes; then the new Azure-only "Slow shop requests" dashboard lists a slow shipping and a slow ratings request; a trace ID opens the span view with the database step as most of the time. Screenshot each.
9. **Revert, timed** (FR-002, SC-004, SC-006): `RESULT: fault removed (…)` in under 60 s; within 1 minute 10 out of 10 requests of each kind are at normal speed.
10. **Status after revert and a second revert** (FR-004, SC-010): `RESULT: fault not active`, then `RESULT: fault not active, nothing changed`, both exit 0.
11. **Dashboard recovery** (SC-004, SC-014): within 5 minutes the average query time panel is back at its earlier level. Screenshot.
12. **Data unchanged** (FR-006, SC-008): repeat the step 3 baselines; they match. Ratings is compared only as far as traffic added rows.
13. **Overlapping traffic with the fault on**, 2 minutes: no errors (SC-002, EC-008), as in Finding 12.
14. **One whole demo timed** with a stopwatch: start, point at the rise, revert, point at the recovery, within 2 minutes (SC-005).

### Part B — edge cases

15. **Refusals** (FR-007, EC-006): `KUBECONFIG=/dev/null make aks-db-latency-status` exits `3`; the script run from a scratch copy of the repo whose `.env` says `STACK_MODE=eks` exits `3`. Both print `Nothing was changed.`
16. **Shop re-deployed with the fault on** (EC-002, FR-013): start, run `make setup-robot-shop`, then status prints `fault active` (Finding 13).
17. **Database restart** (EC-003, EC-004): with the fault on, delete `mysql-0`; about 2 minutes later status prints `fault not active`, and start brings the fault back from scratch (Finding 14). Needs the developer's approval first: the shop is down for about 2 minutes.
18. **Slow for another reason** (EC-007): checked by reading the script unless a cheap way to slow the database another way is found.
19. **Fault never started** (SC-012): 5 minutes of traffic with the fault never started; every shipping request is at normal speed.
20. **No lines changed in the EKS scenarios** (SC-011, FR-012): `git diff --stat main` shows zero lines in `scenarios/scenario-01/`, `scenario-02/` and `scenario-04/`, and only Azure lines added to `makefile` and `scenarios/README.md`.

### Part C — the guide

21. The owner, following only `scenarios/README.md` and the script's `README.md`, completes one full start, check and revert cycle (SC-009). The guide must include the slow-requests dashboard steps and a warning not to restart MySQL during a demo (Finding 14).

## Evidence collected in the PR

1. Verbatim terminal output of steps 3 to 21 (all `time` lines, `RESULT:` lines and exit codes).
2. The Grafana screenshots from steps 8 and 11.
3. `make lint` output.
4. `git diff --stat main`, showing changes only under `infra/azure/scenario-03/`, `monitoring/dashboards/mysql.yaml`, `infra/azure/dashboards/`, `docs/aks-explained.md` and the Azure-only lines in `makefile` and `scenarios/README.md`.

## What this run deliberately does NOT exercise live

Named for the Architect at the plan gate: the "not an AKS cluster" check, an unready `mysql-0`, and step 18 (unless a cheap way is found) are checked by reading the script alone.
