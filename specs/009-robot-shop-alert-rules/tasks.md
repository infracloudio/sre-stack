---

description: "Task list for the robot-shop alert rules on Azure (story #122)"
---

# Tasks: Alert Rules for the Demo Shop on Azure

**Input**: `specs/009-robot-shop-alert-rules/` (`spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/alert-rules.md`, `quickstart.md`)

**Prerequisites**: `gate:plan-approved` on the pull request (CI blocks any change outside this story's `specs/` folder before that label). The AKS cluster is running (it costs money while it runs).

**Tests**: There are no unit tests in the repo for this story. Proof comes from the ten live/offline check groups and the local traffic-guard check 11 in `quickstart.md`, plus `promtool` and `yamllint` on the rule file. Evidence-only local rule tests are recorded below; they are not added to the repo’s automated test runner.

**How this file was written**: in one pass, because the developer explicitly asked for that on 2026-10-28. The constitution (principle IX) normally asks for one section at a time with approval between sections. The developer also explicitly approved all analysis fixes in one pass on 2026-10-28.

## Legend

- `T001`: a stable task number. Follow phase order and explicit dependencies; T035 was added after analysis and runs after T016, before T017.
- `[P]`: the task touches a different file from the tasks around it and needs nothing that is unfinished, so it can run in parallel.
- `[US1]` to `[US4]`: the user story the task serves, from `spec.md`. US1 is the cart memory fault alerts (must have). US2 is the slow-database alerts (should have). US3 is the healthy shop staying quiet (must have). US4 is the rules coming with the setup and being easy to change (nice to have).
- `FR-nnn`, `SC-nnn`, `EC-nnn`: Functional Requirement, Success Criterion and Edge Case numbers in `spec.md`.
- `plan.md lines A-B`: the exact text to copy. The plan's rule file is the checked scratch copy, so rule text is copied unchanged, not retyped.
- "Evidence" means a file under `specs/009-robot-shop-alert-rules/evidence/`. Paste real command output there, with times. "Should work" is not a pass.
- `ADDR` means the address printed by `make get-service-endpoints`. The alerts page is `http://ADDR/prometheus/alerts` and the rules API is `http://ADDR/prometheus/api/v1/rules`.

## Phase 1: Setup

**Purpose**: Make sure tools, the branch gate and the cluster are ready before any file changes.

- [ ] T001 Run `make hooks`, then confirm the tools: `promtool --version` (must say 2.47.1 to match the cluster), `yq --version`, `yamllint --version`. Paste the output into `specs/009-robot-shop-alert-rules/evidence/quickstart-run.txt` (create the folder and file). If a tool is missing, stop and tell the developer.
- [ ] T002 Confirm the gate: `gh pr list --head 009-robot-shop-alert-rules --json number,labels` must show the label `gate:plan-approved`. If it does not, stop. Nothing outside `specs/` may change before it.
- [ ] T003 Confirm the cluster is ready: `kubectl get nodes`, `kubectl get deploy,sts -n robot-shop` (every READY column complete), `kubectl -n loadgen get deployment load` (1 ready copy; if missing, `kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -` then `kubectl apply -f infra/azure/load-gen/load.yaml`), and `curl -s http://ADDR/prometheus/api/v1/rules` returns the Bookinfo group. Append the output to `specs/009-robot-shop-alert-rules/evidence/quickstart-run.txt`. Before any rule apply, also record the monitoring baseline in quickstart check 7 step 5: a successful shop-traffic query, a dashboard screenshot with new request data, and a trace opened from that data, under `evidence/monitoring-before/`. If the cluster is stopped, ask the developer before running `az aks start`.

---

## Phase 2: Foundational (the empty rule object and its make target)

**Purpose**: The file and the one command that applies it. Every story below adds rules to this file.

**Note**: No story work can start until this phase is done.

- [ ] T004 Create `infra/azure/alert-rules/robot-shop-alerts.yaml` with only the header comment (copy `plan.md` lines 183 to 196), `apiVersion`, `kind: PrometheusRule`, `metadata` (name `robot-shop-alerts`, namespace `monitoring`, label `release: prometheus-stack`) and `spec.groups` with one group named `robot-shop` and `rules: []` (copy `plan.md` lines 197 to 207, stopping before the first rule). Rules are added by later tasks.
- [ ] T005 In `makefile`, add the target `setup-aks-alert-rules` right after the `setup-aks-o11y-routes` block (which ends near line 241). Copy the target and its comment from `plan.md` lines 367 to 374. Recipe lines start with a tab, not spaces. It must refuse when `STACK_MODE` is not `aks`, the same way `setup-aks` does (`grep -n "STACK_MODE" makefile` to see the existing pattern at about line 296).
- [ ] T006 In `makefile`, add `setup-aks-alert-rules` to the prerequisites of `setup-aks-o11y` (line 205), right after `setup-aks-prometheus-stack`, so the line matches `plan.md` line 361 exactly. In the same file, add the help line after line 30 (the `setup-aks-o11y-routes` help line), copied from `plan.md` line 380. Use `grep -n "setup-aks-o11y-routes" makefile` first to confirm the line numbers have not moved.
- [ ] T007 Check the wiring without touching the cluster state: `make -n setup-aks-alert-rules` prints the `kubectl apply -f infra/azure/alert-rules/robot-shop-alerts.yaml` line; `make -n setup-aks | grep -c "infra/azure/alert-rules/robot-shop-alerts.yaml"` prints at least 1; `make -n setup-aks-o11y | grep -n "robot-shop-alerts.yaml\|prometheus-stack"` shows the prometheus-stack step before the rule step. The server dry run is deferred to T017, after the complete rule file passes the offline gate. Append the output to `evidence/quickstart-run.txt` (this is quickstart check 1, step 4).

**Checkpoint**: One command applies the rule object, and the one-shot setup runs it. No rules exist yet.

---

## Phase 3: User Story 1 - Alerts fire when the cart runs out of memory (must have)

**Goal**: Four alerts exist for the cart memory fault: out of memory, restarting, no ready copy, server errors (FR-001 to FR-004, FR-007 to FR-010).

**Independent test**: Quickstart check 2 (done later in Phase 7, because it must come after the quiet run). Here the rules are written and checked without the cluster.

All four tasks edit the same file, so they run one after another.

- [ ] T008 [US1] In `infra/azure/alert-rules/robot-shop-alerts.yaml`, replace `rules: []` with the first rule, `RobotShopContainerOOMKilled`. Copy the comment and rule from `plan.md` lines 208 to 228 unchanged (indentation is 8 spaces for the comment and `- alert:`).
- [ ] T009 [US1] Add `RobotShopContainerRestarting` after it. Copy `plan.md` lines 230 to 250 unchanged.
- [ ] T010 [US1] Add `RobotShopReplicasUnavailable` after it. Copy `plan.md` lines 252 to 274 unchanged. It covers deployments and the two stateful sets (`mysql`, `redis`).
- [ ] T011 [US1] Add `RobotShopHTTPErrors` after it. Copy `plan.md` lines 276 to 301 unchanged.
- [ ] T012 [US1] Static check of the four rules: `yamllint -c .yamllint.yaml infra/azure/alert-rules/robot-shop-alerts.yaml` prints no findings, and `yq '.spec' infra/azure/alert-rules/robot-shop-alerts.yaml > specs/009-robot-shop-alert-rules/evidence/spec-groups.yaml` then `promtool check rules specs/009-robot-shop-alert-rules/evidence/spec-groups.yaml` says `SUCCESS: 4 rules found`. Append the output to `evidence/quickstart-run.txt`. Delete `evidence/spec-groups.yaml` afterwards (it is scratch).
- [ ] T013 [US1] After T012, independently extract the four-rule file with `yq '.spec' infra/azure/alert-rules/robot-shop-alerts.yaml > specs/009-robot-shop-alert-rules/evidence/replicas-unavailable-rules.yaml`. Retain this snapshot; do not consume T012’s deleted scratch file. Write `evidence/replicas-unavailable-test.yaml` referencing the snapshot, with `kube_statefulset_replicas{namespace="robot-shop",statefulset="mysql"}` set to 1 and `kube_statefulset_status_replicas_ready{namespace="robot-shop",statefulset="mysql"}` set to 0. Expect the alert after the 2-minute wait with `service="mysql"`, `namespace="robot-shop"`, and `severity="warning"`. Run `promtool test rules` and save real output and exit code as `evidence/replicas-unavailable-test.txt`; it must report success. This is evidence only, not a test the repo runs. Finish the extraction and test before T014 edits the source rule file.

**Checkpoint**: Four cart-fault rules are in the file and pass the static checks.

---

## Phase 4: User Story 2 - Alerts fire when the shop's database is slow (should have)

**Goal**: Two slow-request alerts, for shipping and for ratings (FR-005).

**Independent test**: Quickstart check 3 (Phase 7).

- [ ] T014 [US2] Add `RobotShopShippingSlowRequests` after the last rule in `infra/azure/alert-rules/robot-shop-alerts.yaml`. Copy `plan.md` lines 303 to 330 unchanged. The limit and the reason are in the comment, which satisfies SC-012.
- [ ] T015 [US2] Add `RobotShopRatingsSlowRequests` after it. Copy `plan.md` lines 332 to 353 unchanged.
- [ ] T016 [US2] Static check of all six rules: the same `yamllint` and `yq | promtool check rules` commands as T012 must now say `SUCCESS: 6 rules found`. Also run `grep -c "^        - alert: RobotShop" infra/azure/alert-rules/robot-shop-alerts.yaml`, which must print 6. Append the output to `evidence/quickstart-run.txt` (quickstart check 7, step 1). Delete the scratch `evidence/spec-groups.yaml` again. Before any server dry run or rule apply, run `make lint` and the offline file-scope checks from quickstart check 6 step 1, including working-tree and untracked files. Save actual output and exit code as `evidence/lint-before.txt`, and the scope lists/diffs as `evidence/scope-before.txt`. All must pass; final checks T021 and T030 still run after later edits.

- [ ] T035 [US1] [US2] After T016 and before T017, run quickstart check 11 for the actual server-error, shipping and ratings expressions: absent series, zero counters, fewer than 30 bad requests per window, and a high-traffic positive control for each rule. Retain `evidence/traffic-guards-rules.yaml`, `evidence/traffic-guards-test.yaml`, and the real output and exit code in `evidence/traffic-guards-test.txt`. All cases must pass. These are local invented test inputs, not claimed live measurements (FR-004, FR-005, EC-001, EC-005).

**Checkpoint**: All six rules, the local traffic guards, initial lint and file-scope checks pass before the first live rule apply.

---

## Phase 5: User Story 4 - Rules come with the setup and can be changed (nice to have)

**Goal**: One command installs the rules, a second run changes nothing, and the new target can be found in the docs (FR-013 to FR-015, SC-008, SC-009, SC-010).

**Independent test**: Quickstart checks 1 and 6 here; check 5 (change a limit) runs last, in Phase 8.

- [ ] T017 [US4] Apply and prove repeat-safety (quickstart check 1, steps 1 to 3 and 5). Needs T016 and T035 to pass first. Run `kubectl apply --dry-run=server -f infra/azure/alert-rules/robot-shop-alerts.yaml` and require success before applying. Run `make setup-aks-alert-rules` and note `kubectl get prometheusrule robot-shop-alerts -n monitoring -o jsonpath='{.metadata.resourceVersion}'`; run it again and the version must be unchanged. Record `helm history prometheus-stack -n monitoring` and `kubectl get prometheusrule -A`, run `make setup-aks-o11y`, and record both again: exit 0, same `resourceVersion`, same list of rule objects, and report any new Helm revision as it is (the spec reads SC-008 as "this story's step changes nothing"). Then save `curl -s http://ADDR/prometheus/api/v1/rules` to `specs/009-robot-shop-alert-rules/evidence/rules-api.json` and confirm all six `RobotShop` names show as inactive with an allowed static `severity`, and that the two slow-request rules have their expected static `service`. Namespace and the other service labels are produced by expressions; verify them on active alert instances in T024 and T025 (SC-006). Append all commands and output to `evidence/quickstart-run.txt`. If a required static label is missing, stop and report it. Do not require expression-derived labels on inactive rule definitions.
- [ ] T018 [P] [US4] Edit `README.md` as `plan.md` section 3 says: on line 144 add "the robot-shop alert rules" to the list in the `make setup-aks-o11y` comment; in the paragraph at lines 162 to 165 add `setup-aks-alert-rules` after `setup-aks-prometheus-stack` and add the sentence "The alert rules are in `infra/azure/alert-rules/robot-shop-alerts.yaml`; change a limit there and run `make setup-aks-alert-rules` (no chart upgrade)." Check the line numbers with `grep -n "setup-aks-o11y" README.md` first.
- [ ] T019 [P] [US4] Edit `AGENTS.md` line 35: in the `make setup-aks-o11y` bullet, change "(Prometheus, Grafana," to "(Prometheus, the robot-shop alert rules via `setup-aks-alert-rules` (specs/009), Grafana,". Keep the file on one page. Confirm the path is not protected: `grep -n "AGENTS" agent/hooks/protected-paths.txt` prints nothing.
- [ ] T020 [P] [US4] Append `## AD-015` at the end of `docs/architectural-decisions.md` (newest last; the last entry now is AD-014 at line 940). Follow the layout of AD-014: the decision (the alert limits live in the rule file, not in `.env`, as the exception to principle III in the plan's Complexity Tracking table; and the shipping rule counts the share of slow requests, not the 95th percentile), why (research Findings 5, 7 and 8), and what was given up (one configuration surface, and the simpler 95th-percentile rule). Keep it to one entry.
- [ ] T021 [US4] Repeat quickstart check 6 after T018, T019 and T020. Record `git diff --name-only main...HEAD`, `git diff --name-only`, `git diff --cached --name-only`, and `git ls-files --others --exclude-standard` so committed, unstaged, staged and untracked files are covered. Allow only `infra/azure/alert-rules/robot-shop-alerts.yaml`, `makefile`, `README.md`, `AGENTS.md`, `docs/architectural-decisions.md`, and this story’s `specs/` files. Inspect all shared-file diffs: only the Azure-only wiring/help and explanations may change; local/AWS behavior and shared settings must stay unchanged. Check all three diffs of `monitoring/chart-values/prometheus-values.yaml` are empty, and `kubectl get prometheusrule kube-prometheus-stack-rule-name -n monitoring` still exists. Save lists, diffs and output in `evidence/scope-check.txt`. Repeat the file-scope check after the final edits, before hand-off.

**Checkpoint**: The rules install with one command, setup is safe to repeat, and local and AWS setup behavior is unchanged; shared-file edits are limited to the agreed Azure-only additions. SC-009's full new-cluster proof is not run (developer decision, 2026-10-28); the wiring check in T007 is its evidence.

---

## Phase 6: User Story 3 - A healthy shop raises no alerts (must have)

**Goal**: No alert fires on a healthy shop under load (FR-011, SC-003, EC-002, EC-007).

**Independent test**: Quickstart check 4. These checks run before any fault, so no fault leaves residue in the 30 minutes.

- [ ] T022 [US3] Run the quiet 30 minutes (quickstart check 4). Start the clock only when `kubectl get deploy,sts -n robot-shop` shows every READY column complete, the load generator is running, no fault is active and the alerts page shows nothing firing. Take a screenshot of the alerts page showing all six inactive (save in `evidence/`). After 30 minutes run `curl -s "http://ADDR/prometheus/api/v1/query" --data-urlencode 'query=count_over_time(ALERTS{alertstate="firing", alertname=~"RobotShop.*"}[30m])'`. The result list must be empty. Record the start time, end time and output in `evidence/quickstart-run.txt`. If any alert fired, do not widen a limit by guess: follow the failure rule in `plan.md` (fix the cause, new research finding, departure line, comment in the rule file).
- [ ] T023 [US3] Run the redeploy check (quickstart check 10). `kubectl -n robot-shop rollout restart deployment/cart`, wait for it to finish (`kubectl -n robot-shop rollout status deployment/cart`), about 3 minutes later restart `deployment/shipping` the same way. During both redeploys and for 10 minutes after the second, no alert may show firing (pending is allowed). Poll `curl -s http://ADDR/prometheus/api/v1/alerts` every minute and record each result in `evidence/quickstart-run.txt`.

**Checkpoint**: A healthy shop and a normal redeploy stay quiet.

---

## Phase 7: Live fault checks (prove User Stories 1 and 2)

**Purpose**: Run each fault with the rules loaded. Run these in order, one fault at a time, as `plan.md` ("Order, and why") says. Wait until the alerts page shows nothing firing between tasks.

- [ ] T024 [US1] Cart memory fault (quickstart check 2). `make aks-cart-oom-start` must end with `RESULT: fault active`. Within 5 minutes the alerts page must show four firing: `RobotShopContainerOOMKilled`, `RobotShopContainerRestarting`, `RobotShopReplicasUnavailable`, `RobotShopHTTPErrors` (for `web`). The two slow-request alerts must not fire. Each firing alert must show `service`, `namespace` and `severity` from the allowed five. Save the rules API response as `evidence/rules-api-cart.json`, take a screenshot with four firing and save it in `evidence/`. Then `make aks-cart-oom-revert` must end with `RESULT: fault reverted`; every alert must clear within 10 minutes and none may return in the next 10 minutes. Record the fire time and clear time of each alert against `plan.md`'s table.
- [ ] T025 [US2] Slow-database fault (quickstart check 3). `make aks-db-latency-start` must end with `RESULT: fault active`. Within 5 minutes `RobotShopShippingSlowRequests` and `RobotShopRatingsSlowRequests` must fire, and the four cart-fault alerts must not. Each active alert must carry its expected `service`, `namespace="robot-shop"` and an allowed `severity`; save the rules API response as `evidence/rules-api-database.json`. Screenshot with two firing. `make aks-db-latency-revert` must end with `RESULT: fault removed`; both alerts clear within 10 minutes and stay clear for the next 10. Record times.
- [ ] T026 [US1] [US2] No shop traffic (quickstart check 8). Scale `deployment/load` in `loadgen` to 0. Wait at least 5 minutes to drain both request windows and record the measured counts; they must be below 30 before starting the fault. Run `make aks-cart-oom-start`. Within 5 minutes the out-of-memory, restarting and no-ready-copy alerts must fire. Throughout the check, the server-error, shipping-slow and ratings-slow alerts must not fire; record all three states and any background traffic. T035 separately proves zero-traffic behavior for all three expressions. Revert the cart fault, restore load to 1, and wait until nothing fires. Save commands, counts and states in `evidence/quickstart-run.txt`.
- [ ] T027 [US1] [US2] Both faults at once (quickstart check 9). With a quiet shop and load running, `make aks-cart-oom-start` then `make aks-db-latency-start`. Within 5 minutes five alerts must fire: the four cart alerts and `RobotShopRatingsSlowRequests`. `RobotShopShippingSlowRequests` is not expected to fire here, because the cart is down and no requests reach shipping (developer decision, 2026-10-28; see research Finding 9). Screenshot with five firing; save shipping's request count in `evidence/`. Then `make aks-cart-oom-revert` and `make aks-db-latency-revert`; every alert clears within 10 minutes.
- [ ] T028 [US1] [US2] If any live check in T022 to T027 differed from `plan.md`'s limits table by enough to need a limit change, record it as the plan says: new value and reason in the rule file comment, a new finding in `research.md` with the real numbers, and a one-line departure in `plan.md`, all in one commit. Then re-run the failed check and any check the change could affect. If nothing changed, write "no limit changes" in `evidence/quickstart-run.txt`. Do not weaken a check to make it pass.

**Checkpoint**: Both faults raise only their own alerts, clear on their own, and every edge case with a live check has output.

---

## Phase 8: Change a limit, polish and hand-off

- [ ] T029 [US4] Change a limit and see it used (quickstart check 5), after the fault checks, as the last check that changes a rule. Note the time, change one limit in `infra/azure/alert-rules/robot-shop-alerts.yaml` (for example the ratings `0.10` to `0.12`), run `make setup-aks-alert-rules`, and within 2 minutes `curl -s http://ADDR/prometheus/api/v1/rules` must show the new value in that rule's `query`. `helm list -n monitoring` must show the same `prometheus-stack` revision as before. Then restore the file with `git checkout -- infra/azure/alert-rules/robot-shop-alerts.yaml` and run `make setup-aks-alert-rules` again. Record all of it in `evidence/quickstart-run.txt`. If T028 changed the file and the change is not yet committed, commit it first so the restore does not undo it.
- [ ] T030 Fault scripts, monitoring and final lint (quickstart check 7, steps 2 to 5). Repeat the monitoring baseline from T003 after all faults are removed and the rule limit is restored: successful positive shop-traffic query, current dashboard request data and a newly opened trace with its steps. Save actual output, trace ID and screenshots under `evidence/monitoring-after/`, compared with `evidence/monitoring-before/` (FR-017, SC-011). With no fault active run `make aks-cart-oom-status` and `make aks-db-latency-status`; each must end with its own "fault not active" message. Run `make lint`, then save its real output and exit code to `evidence/lint-output.txt`. It must pass with 0 errors. Confirm each of the three tuned limits (shipping slow, ratings slow, server-error share) has its value and reason in the rule file comments (SC-012). If lint fails, fix the cause; do not edit hooks, ratchets or protected paths.
- [ ] T031 Write `specs/009-robot-shop-alert-rules/evidence/pr-entries.md`: the list of evidence files (`quickstart-run.txt`, `lint-output.txt`, `scope-check.txt`, `rules-api.json`, `rules-api-cart.json`, `rules-api-database.json`, `replicas-unavailable-*`, `traffic-guards-*`, `lint-before.txt`, `scope-before.txt`, monitoring before/after evidence, screenshots), every departure from `plan.md` with its reason, and these three plain statements: SC-009 has wiring evidence only and is not proven on a new cluster; the limits come from one run each plus this verification run; the database branch of the no-ready-copy rule is covered only by the local `promtool` test, and redeploys were tested for cart and shipping only.
- [ ] T032 Run `make story-cost` for this story if the `after_tasks` hook has not done so, and make sure `specs/009-robot-shop-alert-rules/usage.tsv` and `cost.md` are updated (AD-014).
- [ ] T033 Clean up. Confirm both faults are removed (`make aks-cart-oom-status`, `make aks-db-latency-status`), the load generator is back at one copy, and the rule file matches the committed one (`git diff -- infra/azure/alert-rules/robot-shop-alerts.yaml` prints nothing). Then ask the developer whether to stop the cluster with `az aks stop` (it costs money while it runs). Do not stop it without an answer.
- [ ] T034 Draft, but do not file, the three follow-ups from `plan.md` "Departures and follow-ups": (1) a one-line issue to correct `_bmad-output/specs/spec-keep-alert-management/SPEC.md` line 65 (the metrics source is Istio, with Beyla repeating it); (2) the text for Story #122 on GitHub, which still says payment where this story uses shipping and ratings; (3) a later story to fix the Bookinfo rule's `severity: P1`, which Keep would read as info. Show the three texts to the developer and wait for approval before filing anything.

---

## Dependencies and Execution Order

### Phase dependencies

- Phase 1 (Setup) has no dependencies. T002 blocks everything outside `specs/`.
- Phase 2 (Foundational) needs Phase 1. It blocks all later phases.
- Phase 3 (US1) and Phase 4 (US2) edit the same file, so they run one after the other: T008 to T016 in order.
- Phase 5 (US4) needs Phase 4, including T016’s initial lint/scope gate and T035’s traffic-guard tests, because T017 applies and checks all six rules on the cluster.
- Phase 6 (US3) needs T017 (rules loaded) and must finish before any fault in Phase 7.
- Phase 7 needs Phase 6.
- Phase 8 needs Phase 7. T029 is the last check that changes a rule; T030 follows with read-only monitoring checks and final lint.

### Dependencies inside a story

- T004 before T005 to T006 (the target applies the file). T005 before T006 is not required by logic, but both edit `makefile`, so they run in order.
- T008 to T011 and T014 to T015 each edit the same file: no parallel runs.
- T013 needs T012, makes and retains its own snapshot, and completes before T014. T035 needs T016 and blocks T017. T003 records monitoring before installation; T030 repeats the same checks after verification.
- T021 needs T018, T019 and T020.

### Parallel opportunities

- T018, T019 and T020 touch three different files and can run together once T017 is done. Example: start one agent on `README.md`, one on `AGENTS.md` and one on `docs/architectural-decisions.md`.
- T013 runs after T012 and before T014; it must finish its snapshot and test before later rule-file edits. It has no parallel marker.
- Nothing else is parallel: the live checks share one cluster and one alerts page.

## Implementation Strategy

### Smallest useful result (must have first)

1. Phase 1 and Phase 2: the file, the make target and the wiring.
2. Phase 3: the four cart-fault rules and their static check.
3. For an optional US1-only demo, use the apply command described in T017 and the cart-fault procedure in T024, adjusting the expected rule count to four. This does not complete either task or bypass the full-build offline gate. This is the first visible "something is wrong" signal for the later Keep stories.

The full build must still follow phase order: T016 and T035 before T017, then the quiet check T022 before any fault. A quick demo of US1 alone is the shortcut, not the path to the pull request.

### Then, in order

4. Phase 4: add the two slow-request rules (US2).
5. Phase 5: apply, prove repeat-safety, update the docs and the decision record (US4).
6. Phase 6: quiet 30 minutes and the redeploy check (US3).
7. Phase 7: each fault, no-traffic and both-faults checks.
8. Phase 8: limit change, lint, evidence, cleanup, follow-ups.

## Notes

- Out of scope for this story (spec, "Out of Scope"): sending alerts anywhere, payment alerts, hotrod, node or disk alerts, and any change to the Bookinfo rule.
- Never touch `.env`, `monitoring/chart-values/prometheus-values.yaml`, `infra/azure/chart-values/prometheus-stack.yaml`, the fault scripts, or anything under `agent/`, `.github/` or `.specify/`. Shared-file changes are limited to the Azure-only additions and explanations allowed by FR-013.
- scenario-02 intentionally degrades RDS and is not part of this story. Do not "repair" it.
- Commit after each task or small group. A change to a limit or a wait always needs three things in one commit: the value and reason in the rule file, a new finding in `research.md`, and a departure line in `plan.md`.
- After this file is generated the `after_tasks` hook asks for `make story-cost`.
