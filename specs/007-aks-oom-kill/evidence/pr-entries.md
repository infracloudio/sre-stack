# PR entries for story 007 (cart out-of-memory kill on AKS)

Evidence for the pull request. Terminal output is in `quickstart-run.txt` in this folder.

## Done live (cluster sre-stack-452138 only)

- Quickstart steps 3–9: status, timed start (8.5 s), mid-fault status, idempotent start, timed revert (8.6 s), status, re-revert. All as the contract says.
- EC-004: the deleted cart pod's replacement was OOMKilled again; status stayed active.
- FR-004: status stayed active for about 6 minutes with no action.
- Step 11 refusals: unreachable cluster (exit 3) and `STACK_MODE=eks` in a scratch copy (exit 3).
- T004 by-hand cases: row 2 (allowance set by hand) and row 4 (leftover marker), both correct.
- Step 13 (never-faulted window): 10 samples over about 5 minutes with the fault off; zero shop pods showed an `OOMKilled` last state.
- Dashboard (Grafana, Playwright): `02-fault-on.png` and `03-after-revert.png`. Console had 0 errors.
- `make lint`: exit 0.

## Not done

- Step 12 (redeploy the shop while the fault is on): denied by the permission check as a change to shared resources. Not run. The redeploy-tolerance behaviour is covered only by reading the script and research Finding 3/4.
- Step 14 (owner follows only the guide): developer's to do.
- Extra check (a) (other Deployments' resources before and after): not captured before the run, so not proven.
- Extra check (b) (one full cycle on a stopwatch, start to dashboard recovery): not timed as one run.
- SC-006 (ten status runs, each under 10 s): not run ten times. Single status runs took about 2.3 s.
- Baseline screenshot before the fault: not taken. Only fault-on and after-revert were captured.
- Shipping pod shows 1/2 Ready on the cluster both before and after the run. Pre-existing and not caused by this story.

## Dashboard widened (T012, deviation D16)

- The Restarts row first watched only the `cart` container. At the developer's request it now covers every pod in every namespace over the last 5 minutes, with a table naming the pod. Proof (T013, developer approved 2026-10-21): a throwaway `oom-proof` namespace held `oom-proof` (16Mi limit, killed for running out of memory) and `crash-proof` (exits 1, a plain crash). With both broken, `04-other-pods.png` shows both by name, and the stat counted the `oom-proof` pod. Then cart's fault was started: `02-fault-on.png` lists cart, `oom-proof` and `crash-proof` in the table, `Last kill was out of memory` Yes for cart and `oom-proof`, No for `crash-proof`. The namespace was deleted (confirmed NotFound) and cart reverted (`RESULT: fault reverted`, status not active); `03-after-revert.png` was taken after the 5-minute window aged the old rows out. Two things seen live and kept as known behaviour: a replaced or deleted pod's row lingers up to 5 minutes (the window), and restart counts are whole numbers because decimals are set to 0.

## Checks done by reading only

- Unreadable `.env`, missing cart Deployment, missing Helm release, "not an AKS cluster" node-label check.
- EC-006 suffix ("cart is failing for another reason"). The live run could not reproduce it; the README sample for it is marked as not captured.
- Start and revert wait-loop logic (the race guard on the newest ReplicaSet, and the revert's clean-run condition).

## Open for the developer

- Step 14 (owner follows only the guide).
- Decision on the redeploy step (12): run it later with approval, or accept the read-only evidence.
- Labels `gate:spec-approved` and `gate:plan-approved` (waived for now; CI blocks changes outside `specs/` until `gate:plan-approved` is set).
- The Restarts-row generalisation to all pods.

## Update after T011 (2026-10-21)

- Done: SC-006 (ten status runs, all under 10 s), FR-013/SC-009 diffs, `make lint` exit 0 (`lint-output.txt`), deviation-table items checked.
- Extra check (a) is only a comparison with the Helm release today, not a before/after diff. Weaker than planned.
- T010 stays open: step 12 (redeploy while the fault is on), a timed stopwatch cycle, and a pre-fault baseline screenshot were never captured. `03-after-revert.png` is the healthy-state shot.
- T011 item (6), the owner's step 14, stays the developer's.

## Final update (2026-10-21)

- Stopwatch cycle done: 70 s from start to dashboard recovery (SC-004 pass). `01-baseline.png` taken before it.
- Step 12: denied twice, then run on the third ask (see the section below).
- T010 stays open only for step 12.
- Step 14 (owner follows only the guide): developer's.

## Whitespace re-indent of application.yaml (deviation D17)

- The pre-commit ratchet forced a yamllint fix on `monitoring/dashboards/application.yaml`, so its dashboard block is re-indented by 2 spaces and `.yamllint.yaml` lost one ignore line. Review with `git diff -w`: only this story's panel additions remain. Parsed data identical; cluster ConfigMap reported unchanged.

## Step 12 done (T014 (a), 2026-10-21)

- Ran live. The redeploy timed out on the pre-existing unready `shipping` pod, leaving Helm release `roboshop` in status `failed` (revision 6). The first script refused status and revert in that state. Fixed (D20): `failed` is accepted. After the fix status and revert printed the two lines the quickstart expects and the marker was cleared.
- Left on the cluster: release `roboshop` still `failed`. Pods run normally. A later `make setup-robot-shop` will fail the same way until `shipping` is Ready.
- Step 14 (the owner follows only the guide): waived by the developer 2026-10-21 ("just approve step 14, I don't have time for it"). SC-007 is not proven by a first-time reader.
