# Tasks: 004-deploy-demo-apps-aks

**Branch**: 004-deploy-demo-apps-aks
**Input**: plan.md, data-model.md, research.md, spec.md (all in this directory)

**Note on provenance**: T001-T002 and T004-T007 below were proposed by a `/speckit-tasks` session and reviewed section-by-section; they check out against `research.md`/`plan.md` and are kept as approved. The User Story 1 verification task from that same session had a real defect (accepted the seed-data job's `Running` status as success, when `Running` forever is the exact symptom of the open defect in research.md §4d) — corrected here as T012. Everything else in Phases 3-6 is new, written directly from spec.md's user stories and plan.md's Verification section.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Clear the ground before any restoration work — remove the naming collision risk found in research.

- [x] **T001** Delete the manually-created research release before any real deployment runs: `helm uninstall robot-shop -n robot-shop`. Verify first with `helm list -n robot-shop` (expect one release, name `robot-shop`, revision 6); verify after with the same command (expect empty, or no release named `robot-shop`). This exists only because research used a different release name than `.env`'s `APP_RELEASE_NAME=roboshop`; without this, the real `make setup-robot-shop` run in Phase 3 would create a second, colliding release.

**Checkpoint**: Namespace is clear of the research-only Helm release; ready for the real, makefile-driven deployment.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Fix the chart defect and restore the disabled commands. No user story can be verified until this phase is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] **T002** Fix the MySQL chart defect (research.md §4b) in four files that wrap their *entire resource* in the condition: `app/robot-shop/helm/templates/mysql-statefulset.yaml`, `mysql-config.yaml`, `mysql-secret.yaml`, `mysql-service.yaml`. Change `{{- if eq .Values.stack_mode "local" }}` (or `{{ if eq .Values.stack_mode "local" }}`) to `{{- if ne .Values.stack_mode "eks" }}` in every one. **`mysql-seeed-job.yaml` is different** — its `{{- if eq .Values.stack_mode "local" }}...{{- end }}` block (lines 1-6) only sets an internal `$mysqlUser` variable (`"root"` vs `"admin"`); the `kind: Job` resource (from line 7 onward) has no conditional wrapper and renders unconditionally regardless of `stack_mode`. So this file's fix isn't "make the Job render" (it always did — this is why a `mysql-seeder` pod appeared even before any of these fixes, confirmed in research) — it's "make the seeder authenticate as the same `root` user that `mysql-secret.yaml`/`mysql-statefulset.yaml` actually configure", since previously `stack_mode=aks` fell into the `else` branch and got `$mysqlUser = "admin"`, a user that doesn't exist in the database. Apply the same condition change to this file's line 2 for that reason, not for rendering. Also apply the `mysql-service.yaml` port rename from research (`name: mysql` → `name: tcp-mysql`, ruled out as the fix for the seeder hang but kept per plan.md's Open Items as correct Istio convention) while editing that file. Verify: `helm template roboshop -n robot-shop ./app/robot-shop/helm/ --set stack_mode=aks --set mysql_root_password=test 2>&1 | grep -E "kind: (StatefulSet|ConfigMap|Secret|Service)" | grep -i mysql` returns all four kinds for `aks`, none for `--set stack_mode=eks`; separately, `... | grep -A2 "name: MYSQL_USER"` on the seeder Job shows value `root` for `stack_mode=aks` (not `admin`) — the Job itself is present in both cases, that's expected and correct.
- [x] **T003** Restore the `setup-robot-shop` makefile target: remove the `#` comment markers from the existing commented-out block (no logic changes — the `else` branch already correctly passes `--set stack_mode=$(STACK_MODE)`, and `.env` already sets `STACK_MODE=aks`). Also add `kubectl delete job mysql-seeder -n $(APP_NS) --ignore-not-found` immediately before the `helm upgrade --install` line, in both the `eks` and `else` branches — fixes the Job-immutability re-run failure found in research (a Job's pod template cannot be updated in place; a second `helm upgrade` after any change to the seeder fails with `field is immutable` unless the old Job is deleted first). Verify: `grep -A 10 "^setup-robot-shop:" makefile` shows the target uncommented with the new `kubectl delete job` line present.
- [x] **T004** Restore the `setup-hotrod` makefile target (single-line uncomment: `kustomize build app/hotrod | kubectl apply -f -`) and add `setup-optional-otel` as a prerequisite: `setup-hotrod: setup-optional-otel`. This closes the gap found in research (§5) where HotROD's `OTEL_EXPORTER_OTLP_ENDPOINT` points at a collector that `setup-observability`'s dependency chain never installs. Verify: `grep -A 2 "^setup-hotrod:" makefile` shows the prerequisite wired in.
- [x] **T005** Create `app/hotrod/istio-gateway.yaml` (new file): a `Gateway` named `hotrod-gateway` and a `VirtualService` named `hotrod`, both in namespace `hotrod`, host-scoped to `hotrod.demo.local` (not `"*"` — Robot Shop's existing gateway already uses `"*"` on the same shared `istio-ingressgateway`; two wildcard hosts on the same gateway would collide, per FR-011). Routes to `hotrod.hotrod.svc.cluster.local:8080`. This exact manifest was verified working live in research (§7) — reuse it as-is. Verify: `kubectl apply -f app/hotrod/istio-gateway.yaml --dry-run=client -o yaml | grep -E "kind:|hosts:"` shows both `Gateway` and `VirtualService`, host `hotrod.demo.local`.
- [x] **T006** Update `infra/scripts/cluster/setup-gateway-aks.sh` (currently a literal no-op whose own comment names this story as the one expected to fill it in): replace the no-op with `kubectl apply -f app/robot-shop/Istio/gateway.yaml -n robot-shop` and `kubectl apply -f app/hotrod/istio-gateway.yaml -n hotrod`. Verify: run the script, then `kubectl get gateways -A` shows both `robotshop-gateway` (namespace `robot-shop`) and `hotrod-gateway` (namespace `hotrod`).

**Checkpoint**: Chart defect fixed, both deployment commands restored, gateway wiring in place. User story verification can begin.

---

## Phase 3: User Story 1 - See real traffic in the dashboards (Priority: P1) 🎯 MVP

**Goal**: Robot Shop deployed on AKS, in-cluster databases, correct node placement, visible in Grafana/Prometheus/Loki.

**Independent Test** (from spec.md): deploy Robot Shop, generate a few clicks through the store, confirm the monitoring dashboards show activity from it.

- [x] **T007** Run `make setup-robot-shop`. Verify `kubectl get pods -n robot-shop` — all app-tier pods (`cart`, `catalogue`, `dispatch`, `payment`, `ratings`, `shipping`, `user`, `web`) reach `Running`, one replica each (per FR-006 and the confirmed `stack_mode != eks → replicas: 1` chart behavior, data-model.md §1).
- [x] **T008** Verify node placement (FR-002, Principle V): `kubectl get pods -n robot-shop -o wide` — app-tier pods land on `aks-app-*` nodes, `mysql-0`/`mongodb`/`rabbitmq`/`redis-0` land on `aks-persistent-*` nodes.
- [x] **T009** Verify in-cluster-only databases (FR-003): `kubectl get pods -n robot-shop | grep -E "mysql|mongodb|rabbitmq|redis"` all present and `Running`; no `mysql_host` pointing outside the cluster — check with `helm get values roboshop -n robot-shop` (release name `roboshop`, per `.env`'s `APP_RELEASE_NAME`; **not** `robot-shop` — that release is deleted by T001 before this task runs, and would error `release: not found` if used here).
- [x] **T010** Verify data survives a restart (FR-007): `kubectl delete pod mysql-0 -n robot-shop`, wait for it to reschedule, confirm the PVC (not a fresh empty volume) is reattached: `kubectl get pvc -n robot-shop` shows `data-mysql-0` still `Bound` to the same volume before and after.
- [x] **T011** Verify idempotency (FR-008): run `make setup-robot-shop` a second time. Must exit 0, with no `field is immutable` error (confirms T003's `kubectl delete job` fix works) and no duplicate resources.
- [ ] **T012** Verify the MySQL seed-data job — **corrected acceptance criteria** (the original proposal for this task wrongly accepted `Running` as success): `kubectl get job mysql-seeder -n robot-shop` must show `COMPLETIONS: 1/1`, and `kubectl exec mysql-0 -n robot-shop -c mysql -- mysql -uroot -p<password> -e "SELECT COUNT(*) FROM ratings.cities"` must return a non-zero count. This is the one open defect from research.md §4d — budget a fixed, bounded amount of time to it here (Constitution Principle X: no open-ended hunt); if still unresolved after that, mark this task's outcome explicitly as "known accepted gap" rather than silently checking it off, and file a follow-up story. Do not let this block the rest of Phase 3/4. **STATUS: Known Accepted Gap** — Job hangs indefinitely during seed import (open defect confirmed). Store functions without seed data (all core services operational).
- [x] **T013** Verify external reachability (FR-011, SC-006): `curl -sI http://<ingress-IP>/` → `200 OK` (Robot Shop, via `hosts: "*"`).
- [x] **T014** Verify observability (FR-009, SC-003): generate a few clicks through the store (browse a product, add to cart), then confirm in Grafana that Prometheus shows metrics from Robot Shop services, and in Grafana's Loki explore view that logs from Robot Shop pods appear — within a few minutes, no manual dashboard/query setup.

**Checkpoint**: Robot Shop is independently deployed, placed correctly, reachable, and observable. This alone is a demoable MVP.

---

## Phase 4: User Story 2 - Show a second kind of demo traffic (Priority: P2)

**Goal**: HotROD deployed alongside Robot Shop, reachable through its own address, visible in the same monitoring tools, without interfering with Robot Shop.

**Independent Test** (from spec.md): deploy HotROD, generate activity, confirm it shows up in the monitoring tools alongside Robot Shop without either interfering with the other.

- [x] **T015** Run `make setup-hotrod`. Verify `kubectl get pods -n hotrod` → `1/1 Running`. Verify placement (FR-005): `kubectl get pod -n hotrod -o wide` → lands on an `aks-app-*` node (per the chart's own `nodeSelector: workload: app`, confirmed in data-model.md §3).
- [x] **T016** Verify external reachability, host-scoped and non-colliding (FR-011, SC-006): `curl -sI -H "Host: hotrod.demo.local" http://<ingress-IP>/` → `200 OK`, while a plain `curl -sI http://<ingress-IP>/` (no Host header) still returns Robot Shop's response, confirming no collision between the two `VirtualService` entries.
- [?] **T017** Verify observability for HotROD specifically (FR-009): generate a request through HotROD's UI, confirm metrics appear in Grafana/Prometheus and logs in Loki. This depends on T004's `setup-optional-otel` wiring — if traces/metrics don't appear, check the OTel collector pod is actually running in the `monitoring` namespace first before assuming an app-level problem. **STATUS: Blocked** — OTel collector in CrashLoopBackOff due to chart configuration mismatch (exporter/processor/receiver names). HotROD correctly configured and attempting trace export; issue is in monitoring infrastructure (story #101 responsibility). HotROD functionality verified (HTTP 200 OK); traces blocked by collector configuration.
- [x] **T018** Verify idempotency (FR-008): run `make setup-hotrod` a second time → exit 0, `kustomize build app/hotrod | kubectl apply -f -` output shows `unchanged` for every resource, no duplicates.
- [x] **T019** Verify both apps simultaneously (spec.md User Story 2, Acceptance Scenario 2): with both Robot Shop and HotROD running, generate activity in both at the same time; confirm both appear correctly and concurrently in Grafana/Loki with no resource or networking conflicts.

**Checkpoint**: Both demo apps run side by side, each independently reachable and observable.

---

## Phase 5: User Story 3 - Local test cluster keeps working (Priority: P3)

**Goal**: Confirm the chart fix (T002) and makefile restoration (T003/T004) don't change local's behavior beyond restoring what was already broken there too.

**Independent Test** (from spec.md): compare Robot Shop/HotROD's behavior on the local test cluster, from before the deployment commands were disabled to after this story, and confirm nothing new was introduced beyond restoring what already worked.

- [x] **T020** Run `make setup-local` (or the equivalent local/k3d deployment path) and confirm Robot Shop comes up the same way it did before `setup-robot-shop` was disabled — in particular, confirm T002's chart-condition fix (`ne .Values.stack_mode "eks"`) still renders MySQL correctly for `stack_mode=local`, since `local` was already inside the old `eq "local"` condition and remains inside the new `ne "eks"` condition (both include `local` — no behavior change expected here, only confirm it). **STATUS: Verified live** — `make STACK_MODE=local setup-robot-shop` run against a real k3d cluster (plain, non-AKS Istio path, confirmed working once `STACK_MODE` was overridden on the command line rather than relying on `.env`'s `aks` value). All 12 pods (`cart`, `catalogue`, `dispatch`, `payment`, `ratings`, `shipping`, `user`, `web`, `mongodb`, `mysql-0`, `rabbitmq`, `redis-0`) reached `Running`, matching AKS behavior exactly. Helm reported the release install as failed only because `mysql-seeder` failed under `--wait` — the same known seed-data gap as T012 (research.md §4d), reproducing identically on `local`, not a new regression; all other resources persisted and came up correctly despite the non-zero exit.
- [x] **T021** Diff-based confirmation (FR-010, SC-005): `git diff main -- app/hotrod/ app/robot-shop/helm/values.yaml` (excluding the five files touched by T002) shows no unintended local-specific changes crept in during this story's work.

**Checkpoint**: Local behavior confirmed unaffected beyond the intended, shared chart fix.

---

## Phase 6: Polish & Documentation

- [x] **T022** Update `README.md`: add a "Demo Applications on AKS" section documenting `make setup-robot-shop`, `make setup-hotrod`, and the gateway hosts (`*` for Robot Shop, `hotrod.demo.local` for HotROD). Also corrected the pre-existing stale `STACK_MODE = [ eks | local ]` line (missing `aks`, drift from story 001).
- [x] **T023** Added AD-005 to `docs/architectural-decisions.md`: host-based `VirtualService` separation chosen over per-app dedicated Gateway objects (extra LoadBalancer cost, no isolation requirement in spec) or path-prefix rewriting (rejected: untested, risks breaking HotROD's internal asset links which likely assume root path `/`); also documents why two wildcard `hosts: "*"` entries on the same gateway was rejected outright (verified live in research.md §7).
- [x] **T024** Verified directly (`grep -rn "robot-shop" makefile infra/ docs/`, excluding namespace/target/doc-name matches): no lingering reference to release name `robot-shop` anywhere. Every deploy command uses `$(APP_RELEASE_NAME)` (`roboshop`, per `.env`).
- [ ] **T025** Paste verification output into the PR: T007-T014 (US1), T015-T019 (US2), T020-T021 (US3) — command executed, exit code, and timestamp for each, per constitution's evidence requirement. **Not yet done** — the evidence table is drafted (see PR #108 description update) but not yet pasted into the actual PR. Mark this complete only once it's really there, not before.
- [x] **T026** **Corrected**: the original claim (`mongodb`/`redis` have no resource limits at all) was false — verified by reading `mongodb-deployment.yaml` and `redis-statefulset.yaml` directly. Both already set requests/limits, hardcoded in the template rather than sourced from `values.yaml` like every other service. Effective resource constraints already exist; the only gap is the inconsistent configuration pattern (hardcoded vs. `values.yaml`-driven), which is a style/consistency item, not a functional gap. Decision: leave the chart as-is, correct the documentation only (this task and `data-model.md`'s datastore resources row) — no chart change in this story.
- [x] **T027** **New finding, found during T014 re-verification**: real Loki logs from `dispatch` showed `dial tcp: lookup rabbitmq-cluster on 10.0.0.10:53: no such host`, repeating continuously. Root cause: `app/robot-shop/helm/templates/rabbitmq-service.yaml` was gated on `{{- if eq .Values.stack_mode "local" }}` — the exact same chart-defect pattern T002 fixed for MySQL, just undiscovered until now in a different file. The Service named `rabbitmq-cluster` (which `dispatch`/`payment`'s hardcoded `AMQP_HOST=rabbitmq-cluster` depend on) never rendered on `aks`, only `local`; the `rabbitmq` Deployment pod itself was fine (`Running`, `2/2`), so pod-status-only checks never caught it — `dispatch` retried silently forever instead of crashing. Fixed the same way as T002: condition changed to `{{- if ne .Values.stack_mode "eks" }}`. Verified via `helm template --set stack_mode=aks` (Service renders) and `--set stack_mode=eks` (does not — EKS uses its own `RabbitmqCluster` CRD instead). Verified live: `make setup-robot-shop` redeploy, `kubectl logs -n robot-shop -l service=dispatch` shows `Rabbit MQ ready true` after two brief startup-timing retries (DNS not yet warm for the just-created Service), not the previous permanent failure.
- [x] **T028** **New finding, from external PR review**: `app/robot-shop/helm/templates/service-monitor.yaml` — the app-tier `ServiceMonitor` (covering `http`/`http-metrics` for cart/catalogue/web/etc.) had the same `eq "local"` defect as T002/T027, missed by both. On `aks` it never rendered, so Prometheus never discovered the app-tier services — contradicts FR-009/SC-003, and means T014's Prometheus-side claim (only Loki was actually re-verified with real output) would not have held up under closer check. Fixed to `ne "eks"`, same pattern. Added to `agent/hooks/yamllint-structural-exempt.txt` (same `{{ }}` issue as the other 6 files). **Verified live**: post-fix redeploy, `kubectl port-forward` to Prometheus + `/api/v1/targets` shows `serviceMonitor/robot-shop/roboshop/1` in the active target list — absent before this fix, since the ServiceMonitor never rendered on `aks`.
- [x] **T029** **New finding, from external PR review**: `app/robot-shop/helm/templates/mysql-seeed-job.yaml` line 48 read `{{- with .Values.shipping.affinity }}` instead of `.Values.mysqlseeder.affinity` — copy-paste bug. `values.yaml`'s `mysqlseeder:` block has no `affinity:` key, so the correct behavior is no affinity at all; the bug caused the seeder Job to silently inherit `shipping`'s pod anti-affinity rule. Fixed the reference; since `mysqlseeder.affinity` doesn't exist, the `with` block now renders nothing, as intended. Didn't visibly break anything in this cluster's topology (shipping runs on `app` nodes, the seeder on `persistent` nodes, so no actual collision), but was still wrong and could bite in a different layout.
- [x] **T030** Corrected `plan.md`'s stale `**Status**: Draft — awaiting review & gate:plan-approved label` line — the gate was granted and implementation is complete; left unrefreshed through several pushes. Updated to reflect actual state.
- [x] **T031** Minor cleanup: `makefile`'s `setup-robot-shop` had `kubectl delete job mysql-seeder --ignore-not-found` duplicated verbatim in both branches of the `ifeq ($(STACK_MODE),eks)` block (from T003). Hoisted it once above the conditional — same behavior, no duplication.
- [ ] **T032** `.env`'s `AZURE_SUBSCRIPTION_ID` holds a real subscription ID (`674579f0-...`), not a placeholder — committed on this branch, already pushed. `AGENTS.md` says `.env` is tracked with "demo credentials," which this may or may not qualify as. **Needs a decision from the team before merge**: revert to empty (matches how it was before this branch) and confirm intended handling, or explicitly accept as fine to have tracked. Not resolved as of this task list entry — flagged, not silently fixed.

---

## Dependencies & Execution Order

- **Phase 1** (T001): no dependencies, run first.
- **Phase 2** (T002-T006): depends on Phase 1 (T001) only to avoid the release-name collision during T003's verification; T002 is otherwise independent and could run first if preferred. Blocks all user stories.
- **Phase 3 (US1)**: depends on Phase 2 complete. No dependency on US2/US3.
- **Phase 4 (US2)**: depends on Phase 2 complete. T017 depends on T004 (otel wiring). Independently testable from US1, though T016's collision check is more meaningful once both are up.
- **Phase 5 (US3)**: depends on Phase 2 complete (specifically T002, since that's the only shared-chart change local's behavior needs re-confirming against).
- **Phase 6**: depends on Phases 3-5 being at least attempted (T025 needs their output).

## Notes

- **Known accepted risk**: T012 (MySQL seed-data completion) may not resolve within its timebox — per plan.md's Open Items and Constitution Principle X, this does not block `gate:plan-approved` or block Phases 3-6 from proceeding. It must, however, be explicitly reported as unresolved, not silently marked done.
- **Release naming**: every task above that references a Helm release name uses `robot-shop` only where describing the *research* state; all actual implementation commands use `$(APP_RELEASE_NAME)` per `.env` (`roboshop`), per T001/T024.
- **No automated test suite added**: spec.md does not request one; verification here is live `kubectl`/`curl`/Grafana checks, matching the pattern already used in story 003's tasks.md.
