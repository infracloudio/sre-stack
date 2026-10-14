# Tasks: HTTP Abort Fault for the Demo Shop on Azure

**Input**: Design documents from `specs/006-aks-http-abort-fault/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/commands.md](contracts/commands.md), [quickstart.md](quickstart.md)

**Tests**: No offline tests (plan.md, Project Structure — developer's decision, 2026-10-14). Each task names the command that proves it; the live run in quickstart.md is the end-to-end proof.

**Organization**: Tasks are grouped by user story; each is written and approved one at a time (constitution principle IX).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: What all three commands share — setup, usage, and the refusals of data-model §5 (FR-006, EC-005).

- [ ] T001 Create `infra/azure/scenario-01/ratings-abort.sh` skeleton: shebang + header comment, `set -euo pipefail`, repo-root resolution and `source .env` copied from `infra/scripts/cluster/setup-aks-kiali.sh:15-24`, argument dispatch for `start|status|revert` (anything else or none → one-line usage on stderr, exit 2), and the seven pre-checks of data-model §5 in order (`STACK_MODE=aks`, cluster reachable, node label `kubernetes.azure.com/cluster`, `istiod` ready in `$ISTIO_NAMESPACE`, namespace `$APP_NS` + VirtualService `ratings` exist, `web` pod Running with a container named `istio-proxy` in `.spec.initContainers` or `.spec.containers` — native sidecar on this cluster, see research Pre-check note, `curl` inside `web` container), each failing with its message on stderr and exit 3. The start/status/revert bodies are stubs that print "not implemented" and exit 1 for now.
  - Proof: `bash infra/azure/scenario-01/ratings-abort.sh; echo "exit=$?"` → usage, `exit=2`; `KUBECONFIG=/dev/null bash infra/azure/scenario-01/ratings-abort.sh status; echo "exit=$?"` → "Could not reach the cluster…", `exit=3`; `shellcheck infra/azure/scenario-01/ratings-abort.sh` → clean; on the live cluster, `bash infra/azure/scenario-01/ratings-abort.sh status` passes all seven pre-checks and reaches the stub ("not implemented", exit 1, not exit 3) — proves pre-check 6 finds the native sidecar.
- [ ] T002 In `infra/azure/scenario-01/ratings-abort.sh` add two read-only helpers and replace the status stub with the real command: (a) rule reader — `kubectl get virtualservice ratings -n "$APP_NS" -o jsonpath='{.spec.http[0].fault}'` → `none` (empty), `ours` (exactly abort `httpStatus: 500`, `percentage.value: 100`), or `other` (any other fault content), per data-model §1; (b) probe — one `kubectl exec -n "$APP_NS" deploy/web -c web` sending 10 requests to `http://ratings/_health` with `curl -m 2`, stopping at the first request with no answer (`000`), the whole exec wrapped in `timeout 8`, printing the codes on one line and sorting them into all-healthy (10 × `200`), all-injected (10 × `500` with body `fault filter abort`), or other (plus the first odd body seen), per data-model §2; every `kubectl` call in the T001 pre-checks and here uses `--request-timeout=5s` (data-model §4, SC-005 slow path); (c) status — combine (a)+(b) into data-model §3 states 1–5, printing one `RESULT:` line; exit 0 for states 1–2, exit 1 for states 3–5; state 5 skips the probe.
  - Proof: `time bash infra/azure/scenario-01/ratings-abort.sh status; echo "exit=$?"` → ten `200`s, `RESULT: fault not active …`, `exit=0`, under 30 s; `shellcheck infra/azure/scenario-01/ratings-abort.sh` → clean. States 1 proven after T003; states 4–5 checked by reading the script (plan.md).

---

## Phase 3: User Story 1 — Start the fault with one command (Priority: P1) 🎯 MVP

**Goal**: One command makes every request to ratings fail with error 500 until reverted, and checks its own result (FR-001, FR-003, FR-004, FR-012).

**Independent Test**: On the running AKS shop, run start, then status; ten `500`s and `RESULT: fault active`.

- [ ] T003 [US1] In `infra/azure/scenario-01/ratings-abort.sh` replace the start stub: read the rule (T002 reader) → `other`: print what the rule holds, `RESULT: ratings rule holds a fault this command did not set`, exit 1, no change (state 5); `none`: `kubectl patch virtualservice ratings -n "$APP_NS" --type=json -p '[{"op":"add","path":"/spec/http/0/fault","value":{"abort":{"httpStatus":500,"percentage":{"value":100}}}}]'` (research Finding 1); `ours`: no patch, note "already active". Then add a wait-for helper (shared with revert in T004) that reruns the T002 probe every ~3 s until it reports the wanted kind, starting no new probe after 15 s (with the 8 s probe cap the wait ends within about 23 s, data-model §4). For start the wanted kind is all-injected → `RESULT: fault active` (or `fault already active`), exit 0; on timeout print the last codes/body seen, `RESULT: fault set but not taking effect`, exit 1, rule left with the fault so revert can remove it (data-model §4).
  - Proof (live): `time bash infra/azure/scenario-01/ratings-abort.sh start; echo "exit=$?"` → 10 × `500`, `RESULT: fault active`, `exit=0`, under 30 s; run start again → `RESULT: fault already active`, `exit=0` (SC-007); `bash infra/azure/scenario-01/ratings-abort.sh status` → state 1, `exit=0`; `kubectl get virtualservice ratings -n robot-shop -o jsonpath='{.spec}'` → fault present once, route unchanged.

---

## Phase 4: User Story 2 — Remove the fault with one command (Priority: P1)

**Goal**: One command removes the fault, restores the ratings rule exactly, and checks ratings answers normally (FR-002, FR-004, FR-012).

**Independent Test**: With the fault active, run revert, then status; ten `200`s and `RESULT: fault not active`.

- [ ] T004 [US2] In `infra/azure/scenario-01/ratings-abort.sh` replace the revert stub: read the rule (T002 reader) → `other`: `RESULT: ratings rule holds a fault this command did not set`, exit 1, no change (state 5); `ours`: `kubectl patch virtualservice ratings -n "$APP_NS" --type=json -p '[{"op":"remove","path":"/spec/http/0/fault"}]'` (research Finding 1); `none`: no patch, note "was not active". Then the T003 wait-for helper with wanted kind all-healthy → `RESULT: fault removed` (or `fault was not active`), exit 0; on timeout print the last codes/body seen, `RESULT: ratings still failing after the fault was removed — not caused by this fault`, exit 1 (data-model §4, contracts/commands.md).
  - Proof (live, fault on from T003): `time bash infra/azure/scenario-01/ratings-abort.sh revert; echo "exit=$?"` → 10 × `200`, `RESULT: fault removed`, `exit=0`, under 30 s; run revert again → `RESULT: fault was not active`, `exit=0` (SC-007); `kubectl get virtualservice ratings -n robot-shop -o jsonpath='{.spec}'` → `{"hosts":["ratings"],"http":[{"route":[{"destination":{"host":"ratings"}}]}]}`; status → `fault not active`, `exit=0`. Timeout branch, and the slow path staying under 30 s when ratings hangs (pre-checks + 15 s + one 8 s probe), checked by reading the script.
- [ ] T005 [US2] In `makefile` add, right after the `setup-aks-kiali` target (`makefile:233-236`), a short comment block and three one-line targets: `aks-ratings-abort-start:` → `bash infra/azure/scenario-01/ratings-abort.sh start`, `aks-ratings-abort-status:` → `… status`, `aks-ratings-abort-revert:` → `… revert`; and three help lines in the "Azure (AKS) setup/cleanup commands" block after the `setup-aks-kiali` line (`makefile:31`), same column alignment, describing start / report / remove of the scenario 01 ratings HTTP 500 fault on AKS. No `$(error)` STACK_MODE gate in make — the script's pre-check 1 refuses with exit 3 and make passes it through (contracts/commands.md). No `.PHONY` (the makefile has none). No existing line changes (FR-009, SC-008). Serves US1 as well; kept as one task because it is one small edit to one file.
  - Proof: `make help | grep aks-ratings-abort` → three lines; `make aks-ratings-abort-status; echo "exit=$?"` → `RESULT: fault not active`, `exit=0`; `make -n aks-ratings-abort-start aks-ratings-abort-revert` → shows the two `bash` calls, runs nothing; `git diff main -- makefile | grep '^-[^-]'` → prints nothing.

---

## Phase 5: User Story 3 — Find the instructions (Priority: P2)

**Goal**: A person new to the project can start, check and remove the fault on Azure using only the guides (FR-008, FR-011).

**Independent Test**: From a running Azure shop, follow only `infra/azure/scenario-01/README.md` for one start → status → revert cycle.

- [ ] T006 [P] [US3] Create `infra/azure/scenario-01/README.md`, the Azure scenarios guide (FR-008), in plain language (principle VII), sections in order: (1) what it does — ratings answers every request with error 500 until reverted; only ratings, plus the knock-on failure in web's ratings calls (FR-005); (2) what must already be running — `make setup-aks` finished, every robot-shop pod Ready (`kubectl get pods -n robot-shop`), load generator running: how to start it (`kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -` then `kubectl apply -f infra/azure/load-gen/load.yaml`, as `makefile:259-261` prints), how to confirm traffic is flowing, and that it ends each run after one hour and is restarted automatically, so traffic can pause briefly (EC-001); (3) start — `make aks-ratings-abort-start`, sample output, `RESULT:` line; (4) status — `make aks-ratings-abort-status`, the two normal answers and what the non-zero ones mean (data-model §3 states 3–5), and that while the fault is set status cannot see whether ratings itself is healthy — revert's own check shows that (FR-013); (5) what to watch — Grafana Application Dashboard → "Non-2xx Responses by Service" `ratings ->` tile and "5xxs", about 15 s to appear; warn that the Istio Service Dashboard "Server …" panels and ratings logs stay blank, the `user ->` tile is always red from normal `404`s, and "Global Success Rate" may show `NaN` (research Finding 5); (6) revert — `make aks-ratings-abort-revert`, errors clear in about 60 s; (7) good to know — the fault survives `make setup-robot-shop` (Finding 2, EC-002); nothing removes it on a timer and anyone can revert (EC-003); refusals and exit codes (contracts/commands.md); the scripts in `scenarios/scenario-01/` are for EKS, not Azure (EC-006). Load-generator behaviour settled during `/speckit-analyze`: the image's `/load/entrypoint.sh` runs `locust … -t $RUN_TIME` and exits, and the Deployment's `restartPolicy: Always` (`infra/azure/load-gen/load.yaml:33`) restarts it; T010 confirms the pause length if a run passes the hour.
  - Proof: `ls infra/azure/scenario-01/README.md`; `grep -c "make aks-ratings-abort-" infra/azure/scenario-01/README.md` → 3 or more; `make lint` passes. SC-006 proven in the polish phase (plan Verification row 5).
- [ ] T007 [P] [US3] In `scenarios/README.md` append, after the last line, one blank line and one new paragraph (existing lines untouched): on Azure (AKS), scenario 1's ratings errors run with `make aks-ratings-abort-start` / `-status` / `-revert` — see [infra/azure/scenario-01/README.md](../infra/azure/scenario-01/README.md); the scripts in `scenario-01/` are for EKS. Relative link, not a `tree/main` URL (the target does not exist on `main` until merge). Blank line needed because the last existing line (`Scenario 3 - …`) has no trailing markdown line break, and adding one would change an existing line (SC-008).
  - Proof: `git diff main -- scenarios/README.md | grep '^-[^-]'` → prints nothing; `git diff main -- scenarios/README.md` → exactly 2 added lines; `test -f infra/azure/scenario-01/README.md && echo link-target-ok`.
- [ ] T008 [US3] In `docs/aks-explained.md` make scenario 01 version 1 describe the new Azure commands (FR-011), leaving version 2's text as it is: (a) "Scenario 01, version 1" (`:574-602`) — "What the script actually does" → what `make aks-ratings-abort-start` does (adds the 500 fault to ratings' routing rule, stays on until revert, does not change shopper numbers); fix "What you should see" per research Finding 5 — "Non-2xx Responses by Service" `ratings ->` tile and "5xxs" within about 15 s; "Global Success Rate" may show `NaN` (replaces "Drops below 100%"); add rows warning that the Istio Service Dashboard "Server …" panels stay blank and the `user ->` tile is always red from normal `404`s. (b) "How to start a scenario" (`:634-647`) — version 1 → `make aks-ratings-abort-start` / `-status` / `-revert` with a link to `infra/azure/scenario-01/README.md`; version 2 keeps its `bash ./scripts/mis-config-health-probs.sh` line and 10-minute text. (c) Text that still calls every scenario timed and 5,000-shopper (plan.md file table): section 8 "In short" (`:545-549`), "How every scenario works" (`:551-563`) and "Turning the dial" (`:531-537`) say version 1 runs at normal traffic until reverted and the timed 4-step flow describes version 2 only; repo map (`:749`, `:755`) names `infra/azure/scenario-01/` as the Azure scenario 01 commands.
  - Proof: `grep -n "aks-ratings-abort-" docs/aks-explained.md` → start/status/revert named; `grep -n "Drops below 100%\|inject-vs-fault" docs/aks-explained.md` → prints nothing; `grep -n "mis-config-health-probs" docs/aks-explained.md` → version 2 line still present; `make lint` passes. Reviewer read-through for conflicting steps in polish (plan Verification row 6).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Evidence for the PR (`evidence:attached`) — static checks first, then the live run, then the human checks.

- [ ] T009 Static checks before the live run, from repo root, output saved for the PR: (1) `make lint` — full output, must pass (hooks, secrets, protected paths, shellcheck of `infra/azure/scenario-01/ratings-abort.sh`, YAML, Spec Kit, loom drift); (2) `git diff --stat main -- scenarios/scenario-01 scenarios/scenario-02 scenarios/scenario-04` → prints nothing (FR-009, SC-008); (3) `git diff main -- makefile .env scenarios/README.md | grep '^-[^-]'` → prints nothing (SC-008); (4) `git diff --name-only main` → only `infra/azure/scenario-01/ratings-abort.sh`, `infra/azure/scenario-01/README.md`, `makefile`, `scenarios/README.md`, `docs/aks-explained.md`, `specs/006-aks-http-abort-fault/*`, plus `.gitignore` (`.playwright-mcp/`, commit `4cab1b9`, outside story scope — name it in the PR; Architect decides per plan Constitution Check). Fix any failure in the task that owns the file, then re-run. Plan Verification rows 1 and 4.
  - Proof: the four outputs above, pasted into the PR.
- [ ] T010 Live validation: run `specs/006-aks-http-abort-fault/quickstart.md` prerequisites 1–4 and steps 1–14, including step 7a (restart ratings with the fault on, EC-004), on the AKS cluster, in order, capturing for the PR: terminal output of every step; the `time` lines of steps 3 and 9 (SC-005, under 30 s); clock times at steps 3, 4, 9, 10 (SC-001 ≤ 60 s; SC-003 ≤ 10 s / 60 s / 2 min); two Grafana screenshots of the Application Dashboard — fault on (`ratings ->` tile red, "5xxs" up) and 2 min after revert (tile gone or 0) — plan Verification rows 2–3. Stop before step 1 if any robot-shop pod is not Ready (prerequisite 2) and record why instead of running. Step 8 runs `make setup-robot-shop` (Helm upgrade of the live shop, re-runnable). Finish with the quickstart "Clean up" block. If the run passes the load generator's one-hour mark, record the pause before it restarts and correct the T006 guide wording if it differs. **Open**: prerequisite 1 asks for a fresh `make setup-aks`; the existing research cluster `sre-stack-452138` is not fresh — developer chooses before running, and the PR states which was used (affects SC-009).
  - Proof: captured output and screenshots attached to the PR (`evidence:attached`).
- [ ] T011 Human checks, recorded in the PR: (1) newcomer walkthrough (SC-006, plan Verification row 5) — a person new to the project, not the builder, follows only `infra/azure/scenario-01/README.md` for one start → status → revert cycle on the running AKS shop without help; PR records their name, first-attempt yes/no and a one-line note; any step they got stuck on is fixed in the guide (T006 file) and the walkthrough repeated; (2) read-through (FR-011, plan Verification row 6) — reviewer compares `docs/aks-explained.md` section 8 and the repo map against `infra/azure/scenario-01/README.md` and ticks "no conflicting steps" in the PR; (3) the PR description names what is not proven by running (plan, Verification Strategy): the six pre-check refusals other than "cluster not reachable", status states 4 and 5, EC-003 (anyone can revert) as proven by design — the fault lives only in the cluster's ratings rule, no local state (plan Storage), revert's "still failing" branch, ratings itself answering `500`, and a reinstall across a change to the chart's ratings rule.
  - Proof: the three PR entries above.

---

## Dependencies & Execution Order

- **Phase 2 (T001 → T002)** blocks everything: shared setup, refusals, rule reader, probe.
- **US1 (T003)** needs T002. **US2 (T004)** needs T003's wait-for helper; T005 needs T002–T004 so all three targets can be proven live.
- **US3**: T006 and T007 need only the command names fixed in T005; T008 needs T006 (it links to the guide).
- **Polish**: T009 after T001–T008; T010 after T009; T011 after T010 (the newcomer needs a working cluster and the finished guide).

Story order: US1 → US2 → US3. US2 is not independent of US1 in code (shared wait-for helper), but each has its own live test.

## Parallel Opportunities

- T006 and T007 [P]: different files, both need only T005's command names.
- T001–T005 all edit the one script or depend on it — sequential.
- T010's live run and T011 (2) read-through can overlap; T011 (1) cannot.

## Implementation Strategy

- **MVP = Phase 2 + US1 (T001–T003)**: start and status work on the cluster; restore with the raw `kubectl patch … remove` from research Finding 1 if needed.
- **Increment 2 = US2 + targets (T004–T005)**: the full one-command start / status / revert.
- **Increment 3 = US3 (T006–T008)**: the guides.
- **Then T009–T011** for evidence. One commit per task is fine.

**Totals**: 11 tasks — Foundational 2, US1 1, US2 2, US3 3, Polish 3; 2 parallel [P].
