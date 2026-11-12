# Tasks: Install Keep on AKS with one command (story #123)

**Word overrun**: this file is 1405 words against the 600-word target. Declared with the developer's approval of the Implementation phase, 2026-11-09. Compacted 2026-11-09: finished tasks are one line each with their evidence.

## Now

- **Story**: 010, Install Keep on AKS with one command (#123).
- **Handoff (2026-11-12)**:
  - Done: AKS Steps 0 to 13 ran, except the cleanup real run (no `keep-*` names existed; the auto-mode classifier blocked it and it was not retried). Keep was reinstalled on AKS and was left installed. Evidence in `evidence/aks/`.
  - Open: FR-010 is not confirmed on AKS or k3d. The page shows a client-side error with no heading. Hypothesis: the browser's relative `/v2` and `/websocket` paths are not routed to the backend through a bare port-forward. Untested fix: `API_URL_CLIENT=/backend` (this also changes the backend's `KEEP_API_URL`). The k3d test did not run because Docker was not up.
  - Open: SC-011 on AKS is pending the developer's own decoy test. The agent did not run it.
  - Open: D10 (`keepappsecret` literal in keep.yaml, Architect decision, plan.md section 8). Architect confirmation of D1 to D9. Labels on PR #143. PR #142 overlaps #143 (per the Architect's earlier note).
  - Not done: converge has not passed.
  - Evidence outside the repo: earlier k3d runs in `/Users/patrickemmanual/keep-uninstall-evidence/`. Overlay and renders in `/private/tmp/claude-501/-Users-patrickemmanual-Desktop-devin-sre-stack/43c7e22b-2517-48dc-b894-c14bd37860fb/scratchpad/`.
- **Phase**: Verification done apart from the blocked items. Next: `/speckit-converge`, after the FR-010, SC-011 and D10 items are resolved.
- **Completed**: T001 to T018, T020 to T022, T024 to T030 (see the lines below and the evidence each names).
- **Converge (2026-11-09)**: NOT CONVERGED. Round not started: implementation tasks T019, T023 and T031 are open, so converge cannot begin. No tasks appended (no CRITICAL or HIGH agreed-scope gap found). Converge may be run again after T019, T023 and T031 are resolved; a round, if any, is recorded here once.
- **Current slice**: none. Waiting for the developer's decisions on T019, T023 and T031.
- **Blocker**: Written Architect confirmation of D1 to D9, and whether the existing labels cover the current spec and plan (both labels predate plan.md). No code task is blocked on this.
- **Accounting**: story-cost ran (T029) with partial accounting only. Developer action (not a task): set `cleanupPeriodDays` to 3650 in `~/.claude/settings.json`. It is currently null, and it must not be 0.
- **Tooling issue (separate)**: PyYAML is not declared in `install-deps.sh`; setup runs use ephemeral `uv run --with pyyaml`.
- **Open PRs**: two open PRs. #142 (branch `010-keep-install-aks`, no labels) is contained in #143; Architect to say which one to keep.
- **Developer decision (2026-11-09)**: proceeding with implementation before the Architect reconfirms the plan, at the developer's own risk. The Architect has been notified.
- **Cluster state**: the namespaces `keep-uninstall-control`, `keep-uninstall-test`, `keep-partial-test`, `keep-remove-test`, `keep-rebuild-test` and `keep-cleanup-test` do not exist now. Each control and no-hooks run deletes its namespace at the end (`NAMESPACE_CLEANUP=deleted` in both T027 folders).
- **Untested (2026-11-10, for the PR description)**:
  - AKS runs of SC-001 to SC-011 (T023). Procedure developer-approved 2026-11-10; Architect approval pending (D5). Run 2026-11-12: Steps 0 to 13 ran except the cleanup real run; evidence in `evidence/aks/`. SC-011 AKS cleanup decoy test pending the developer's own run (not run by the agent). FR-010 page content not confirmed (see below).
  - Azure access and cluster setup (developer steps): done 2026-11-12. Key file mode 600 (checked by the agent by mode only).
  - FR-011 on AKS: HAS EVIDENCE. Step 3 and step 12 pod lists (`fr011-pods-before.txt`, `fr011-pods-after.txt`): 144 non-keep pods before and after, same names and statuses, none disappeared.
  - SC-001 timing on AKS: HAS EVIDENCE. `make setup-keep` took 151 s (step 4, `step4-setup-keep.txt`), under 300 s.
  - SC-008 Azure-disk part: HAS EVIDENCE. PVC `keep-pvc` Bound on gp2, provisioner `disk.csi.azure.com` (step 8, `step8-storage.txt`).
  - SC-002 on AKS: HAS EVIDENCE, PASS (Step 9, `step9-fr008-second-run.txt`, test folder `fr008-second-run.vC8Ju6/`). Two setup runs; the four Secrets were unchanged (UID and creation time); the workload and credential diffs are empty. Helm recorded revisions 2 and 3 with the same chart and values, because `helm upgrade` always writes a revision. Earlier attempts are kept: `-inconclusive` (dummy key was mode 644, rejected by the mode check; fixed in `fr008-second-run.sh` with umask 077, checksum updated) and `-helm-path-attempt` (Helm v4 on PATH, refused).
  - SC-003 on AKS: HAS EVIDENCE (Step 10, `step10-result.txt`). 0 calls outside localhost in 25 s; backend log 0 uptime reports, 1 "reporting is disabled" line.
  - FR-010 on AKS: NOT CONFIRMED. No login form appeared, and a cookie-less browser ends with a session cookie without entering a credential (`step10-page-peek.json`). But the page does not render: the 2026-11-12 render check (15 s wait) shows "Application error: a client-side exception has occurred while loading localhost", with no title or heading (`step10b-render.json`, screenshot `step10b-page.png`). The earlier Step 10 result reported the page as loaded. That was wrong: it checked only for a login form. Console capture (2026-11-12, `evidence/aks/step10c-aks-console-requests.json`): page error "Cannot destructure property 'data' of ... as it is undefined". Three WebSocket failures to `/websocket/app/keepappkey` (wss on localhost:443 refused; ws on localhost:3000 closed before handshake). Every `/v2/*` request returned 200 once the browser had a session, so the 200 status alone does not show whether the body was JSON or HTML. No content-type was captured. Hypothesis, not yet confirmed: the relative `/v2` and `/websocket` paths reach the frontend, not the backend (curl probes, `step10c-curl-probes.txt`).
  - SC-004, SC-005, SC-007, SC-009, SC-010 on AKS: HAS EVIDENCE for SC-004 and SC-010 (image list, step 6), SC-005 (login exit codes, step 7), and the offline FR-009 test and lint (step 11). The FR-009 test and `make lint` were re-run after the fixture fix: 19 of 19 and exit 0.
  - Removal, reinstall and cleanup on AKS (SC-006, SC-011, step 13). Run 2026-11-12, developer-approved. Evidence in `evidence/aks/step13-*`. Uninstall with `--no-hooks` exit 0; the four `sre-keep-*` Secrets were kept; reinstall from the same local files exit 0 in 126 s; the same login behaviour as before; non-keep pods identical to baseline (144). SC-011 real cleanup run: NOT RUN. The dry run found zero `keep-*` Secrets, so there was nothing to review or delete. The real run was denied by the auto-mode classifier as an irreversible deletion and was not retried. Reinstall was run anyway because it is not a deletion. The cleanup script has run on AKS in dry-run mode only (and on k3d, D7).
  - D10 (open, Architect decision, 2026-11-12): `PUSHER_APP_SECRET=keepappsecret` is a literal in our `keep.yaml` (lines 48 and 49) and is rendered into the backend and websocket manifests. Low impact (cluster-internal, no Ingress address), but AD-008 says nothing secret in a values file. Options: accept as a documented limit, or generate it like `db-password` (a follow-up). Recorded in plan.md section 8. Not changed.
  - Rollback on AKS: not exercised. The rollback path (uninstall, then cleanup) was covered by Step 13's uninstall and dry run, not by a full rollback test.
  - Spot eviction, if the o11y pool is Spot. Diagnose it as a platform event; it is not a Keep defect unless Keep fails for another reason.
  - The node label `kubernetes.azure.com/cluster` on AKS: checked on the live cluster at Step 2 (2026-11-12). The value is the first 63 characters of the node resource group name, because AKS truncates label values (departure recorded in T023 step 2).
  - AKS 1.34 end of life (community Nov 2026, LTS Nov 2027); the D6 decision is still open.
  - The real cluster rebuild (not run; the edge case 4 equivalent was used instead).
  - Story 6a login (out of scope).

## Setup

**Purpose**: Confirm tool versions and the disposable cluster before any file changes. Evidence goes in `specs/010-keep-install-aks/evidence/`. It holds command output only, and no secret values.

- [X] T001 Tool versions with `PATH="$HOME/.local/opt/helm-3.14.4:$PATH"` (Helm v3.14.4 passes; Homebrew Helm v4.2.4 untouched). Evidence: `evidence/setup-versions.txt`.
- [X] T002 Cluster check (context, labels, taints, `gp2`). Evidence: `evidence/setup-cluster.txt`.

## Implementation

Each task gives the file, the FR or SC, the verification and the dependency. Finished tasks are one line; tasks that are partial or blocked are in full.

### A. setup-keep.sh (infra/azure/keep/setup-keep.sh)

- [X] T003 Key check first, before any kubectl or helm call; FR-009, SC-007. Evidence: `evidence/setup-keep-group1-checks.txt` (C3 to C5), `evidence/setup-keep-group2-checks.txt`, `evidence/fr009-test-output.txt`.
- [X] T004 Preflight: Bash 4 or newer, Helm v3.14.4, folder outside the repo. Evidence: `evidence/setup-keep-group1-checks.txt` (C1, C6, C9).
- [X] T005 Cluster check before any change; FR-009. Evidence: `evidence/setup-keep-group1-checks.txt` (C7), `evidence/fr009-test-output.txt`.
- [X] T006 Generate `db-password` and `nextauth-secret` only when missing (mode 600, folder 700); FR-004, FR-006, SC-005. Evidence: `evidence/setup-keep-group1-checks.txt` (C8).

### B. keep.yaml D4 change (infra/azure/chart-values/keep.yaml)

- [X] T007 Remove the `NEXTAUTH_SECRET` value from `frontend.env`; add `sre-keep-auth` (key `NEXTAUTH_SECRET`) to `frontend.envFromSecrets`; D4, FR-006, SC-006. Evidence: `evidence/fr009-and-t007-checks.txt`, `evidence/t007-render-check.txt`.

### C. Secret-metadata probe (SC-009)

- [X] T008 Dummy-value `kubectl describe secret` test: key names shown, value and base64 absent, no apply annotation. Evidence: `evidence/describe-probe.txt`.

### D. Secrets and install

- [X] T009 Create the four Secrets from files when missing; an existing Secret is never overwritten. DEPARTURE from the plan's "create or refresh": refresh would change UIDs and creation times (FR-008, D3), and `kubectl apply` is forbidden for Secrets (SC-009). No value printed; FR-006, SC-009. Evidence: `evidence/secrets-describe-live.txt`, `evidence/secrets-metadata-run1.txt`, `evidence/secrets-metadata-run2.txt`.
- [X] T010 Helm install with `--wait --timeout 10m`; FR-001, FR-008, SC-001, SC-002. Evidence: `evidence/setup-keep-live-runs.txt`, `evidence/ec4-rebuild-equivalent.txt`, the T027 folder.
- [X] T011 A part that fails to start exits non-zero; success printed only after Helm succeeds (edge case "A Keep part cannot start"). Evidence: `evidence/fr009-test-output.txt` (case I).

### E. makefile (makefile)

- [X] T012 `setup-keep` target with the `setup-aks` STACK_MODE guard; FR-001. Evidence: `evidence/t012-t013-dry-runs.txt`.
- [X] T013 `KEEP_SKIP_IF_NO_KEY=1 $(MAKE) setup-keep` as the last step before `get-service-endpoints`; FR-009, US3.2. Evidence: `evidence/t012-t013-dry-runs.txt`.

### F. .env (.env)

- [X] T014 `KEEP_SECRETS_DIR=~/.secrets/keep` (path only; the `~` form is a recorded departure from AD-008 in plan.md). Evidence: `.env`, `infra/azure/keep/README.md`, `specs/010-keep-install-aks/plan.md` (departure list).

### G. Runbook (infra/azure/keep/README.md)

- [X] T015 Runbook: install, `--no-hooks` uninstall, manual cleanup, `KEEP_SKIP_IF_NO_KEY=1`, Helm PATH note, rotation procedure, reinstall caveat. SC-011, FR-013. Evidence: `infra/azure/keep/README.md`.

### H. Tests (infra/azure/keep/tests/)

- [X] T016 FR-008 second-run test on the live release: PASS. SC-002. Evidence: `evidence/fr008-second-run.txt`, `/Users/patrickemmanual/keep-uninstall-evidence/2026-11-09-fr008-second-run/`.
- [X] T017 FR-009 test, 19 cases, all passing (missing key, empty key, cluster unreachable, skip in chain, unset folder, `~` forms, install failure, non-NotFound kubectl error, empty after newline strip). FR-009, SC-007. Evidence: `evidence/fr009-test-output.txt`, `evidence/fr009-and-t007-checks.txt`.
- [X] T018 Render checks, 8 of 8 (SC-010 rendered, SC-004, FR-002, FR-003 rendered hook). Evidence: `evidence/t018-render-checks.txt`, `evidence/t007-render-check.txt`.
- [X] T019 [US1] Live k3d checks on the final values (k3d part only; the AKS parts are under T023). Evidence: `evidence/k3d-live-checks.txt`, `evidence/ec4-rebuild-equivalent.txt`, `evidence/install-check-live.txt`, `evidence/playwright-run.txt`, the T027 folder.
  - PASS on k3d: SC-001 timing from setup logs (fresh install 77 s, re-run after namespace delete 74 s, both under 300 s); SC-005 password; SC-008 gp2 claim (k3d local-path backing); FR-011 other pods Running on this cluster (no monitoring pods here); SC-003 backend log (0 uptime reports); SC-010 pod-spec read; FR-003 image list.
  - FR-010 on k3d: NOT CONFIRMED; content not checked. Correction 2026-11-12: the earlier Playwright run (`playwright-run.txt`, `k3d-live-checks.txt` line 44) checked only HTTP 200, no password input and no form. The page content was not checked. The same chart on AKS renders "Application error" with no heading. Probe finding (AKS, `evidence/aks/step10c-*`): without cookies, `/v2/*` and `/websocket` return 307 to `/signin` from the frontend. `/backend/*` reaches the backend. The chart default `API_URL_CLIENT` is `/v2` because `global.ingress.enabled` defaults to true, and Keep's ingress has no address on either cluster. Hypothesis, not yet confirmed: the browser's relative `/v2` and `/websocket` paths hit the frontend. The k3d test of an overlay with `API_URL_CLIENT=/backend` is blocked: Docker is not running, so the k3d cluster is unreachable.
  - Hook Pod node (control run podwatch): `k3d-keep-uninstall-test-agent-1` (untainted).
  - Moved to T023 (AKS): FR-011 AKS half, SC-001 timing on AKS, SC-008 Azure-disk part.
  - SC-003 frontend part: done in T030.
- [X] T020 Removal and reinstall (FR-007, SC-006): the `--no-hooks` uninstall kept our Secrets; the reinstall waited for `keep-pvc` to finish terminating; the same password works and the database starts empty. Evidence: `evidence/k3d-remove-reinstall.txt`.
- [X] T021 Partial install (edge case "The install is cut off halfway"): interrupted, then re-run finished the job. Evidence: `evidence/partial-install.txt`.
- [X] T031 [US2] Closed: replaced by the edge-case-4 equivalent (developer decision, 2026-11-09, not an Architect approval). A real cluster rebuild was not run. Evidence: `evidence/ec4-rebuild-equivalent.txt`. The namespace keep-rebuild-test was deleted afterwards.

### I. Manual cleanup run (D7)

- [X] T022 D7: one real k3d run of `keep-manual-cleanup.sh` in a throwaway namespace; the `keep-*` decoy deleted, `sre-keep-*` kept. FR-013, SC-011. Evidence: `evidence/manual-cleanup-k3d.txt`.

### J. AKS verification (D5)

- [ ] T023 [US1] SC-001 to SC-011 on AKS. Procedure: developer-approved 2026-11-10; Architect approval pending (D5). Status 2026-11-12: Steps 0 to 13 ran except the cleanup real run (see step 13 below), and the SC-011 AKS cleanup decoy test is pending the developer's own run. The task stays open until that run and Architect approval. Depends: T010, T019, T020, T022. Steps 10 and 13 were each approved separately before they ran.
  - Open: FR-010 page content is NOT confirmed. The 2026-11-12 render check (`step10b-render.json`, `step10b-page.png`) shows "Application error: a client-side exception has occurred while loading localhost" with no heading. The earlier Step 10 result (`step10-result.txt`) confirmed only that no login form was shown. It did not check that the page rendered. Do not claim FR-010 passed on content.
  - Pending: SC-011 AKS cleanup decoy test, to be run by the developer. The agent did not run it.
  - Moved here from T019: FR-011 AKS half (other AKS workloads), SC-001 timing on AKS, SC-008 Azure-disk part (StorageClass `gp2` on AKS, provisioner `disk.csi.azure.com`).
  - Evidence folder: `specs/010-keep-install-aks/evidence/aks/`. The real `fireworks.key` is placed by the developer and is never read or printed by the agent. No secret value is printed in any output.
  - Step 0 (developer): `az login`; `az account set`; `az aks get-credentials -g rijo-john-improving-com-aks-452138 -n sre-stack-452138 --context sre-stack-452138`; owner's OK; cluster started; `chmod 600 ~/.secrets/keep/fireworks.key`.
  - Step 1 (read-only): `az account show` (name only); `az aks show -g rijo-john-improving-com-aks-452138 -n sre-stack-452138 --query "{powerState:powerState.code, provisioning:provisioningState, version:kubernetesVersion, nodeRG:nodeResourceGroup, tier:sku.tier}"`; `az aks nodepool list`. STOP unless Running, Succeeded, 1.34.x.
  - Step 2 (guards): context is `sre-stack-452138`; API server ends `.azmk8s.io`; every node carries `kubernetes.azure.com/cluster` and is Ready; at least one node has `workload=o11y`; namespace `keep` absent; `fireworks.key` is mode 600. STOP on any failure.
    - Departure (2026-11-12, developer-approved): the node label check compares `kubernetes.azure.com/cluster` with the first 63 characters of `nodeResourceGroup`, not the full name. Reason: AKS truncates label values to 63 characters, and the node resource group name on this cluster is 65 characters, so the full-name comparison fails on every node. The Ready check is unchanged. The first Step 2 run (2026-11-12) failed on this check and on the key mode; its evidence is kept with the `-failed` suffix in `evidence/aks/`.
  - Step 3 (FR-011 baseline): `kubectl get pods -A -o wide > fr011-pods-before.txt`.
  - Step 4 (SC-001, FR-001): `PATH="$HOME/.local/opt/helm-3.14.4:$PATH" STACK_MODE=aks make setup-keep`, timed; `kubectl wait --for=condition=Ready pod --all -n keep --timeout=300s`.
  - Step 5 (placement): `kubectl get pods -n keep -o wide`; every Keep Pod is on an o11y node.
  - Step 6 (SC-004, SC-010, FR-003): image list; frontend envFrom secret names (pod spec only).
  - Step 7 (SC-005): no-password login refused; generated password accepted (read inside the container, not printed).
  - Step 8 (SC-008): gp2 class, PVC class and phase, PV provisioner.
  - Step 9 (SC-002): `KEEP_NAMESPACE=keep fr008-second-run.sh`.
  - Step 10 (SC-003, FR-010), NEEDS SEPARATE APPROVAL: port-forward `svc/keep-frontend 3000:3000`; Playwright 1.64.1 ephemeral, deleted afterwards; backend log count.
  - Step 11 (SC-007, SC-009): `fr009-missing-key.sh`; `make lint`.
  - Step 12 (FR-011 after): `kubectl get pods -A -o wide`; non-keep pods unchanged.
  - Step 13 (SC-006, FR-007, SC-011), NEEDS SEPARATE APPROVAL (deletes AKS data): `helm uninstall keep -n keep --no-hooks`; `keep-manual-cleanup.sh` dry run, then real after review; reinstall with the same local files.
  - Stop conditions: any guard fails; a Pod is off the o11y pool or not Running in 10 minutes; Helm exits non-zero; a quota or SKU error; a secret value in any output; a non-keep pod disappears.
  - Spot eviction: stop, diagnose with events, describe pod and `az aks nodepool show`; record as a platform event, not a Keep defect.
  - Rollback: `helm uninstall keep -n keep --no-hooks`; cleanup script dry run, then real after review.

## Verification

Runs use the final `keep.yaml`. Evidence for live runs goes to a new dated folder outside the repo; earlier folders stay.

- [X] T024 Offline checks: manifest 19 of 19 OK; the seven offline suites exit 0; ShellCheck clean. Evidence: `evidence/offline-checks.txt`.
- [X] T025 Install check on k3d: four Pods on `k3d-keep-uninstall-test-agent-0`; no third-party cleanup image in the pods (FR-003). Evidence: `evidence/install-check-live.txt`; the T027 folder (`pods-control-before.txt`, `pods-nohooks-before.txt`).
- [X] T026 FR-008 second run returns PASS on k3d. Evidence: `evidence/fr008-second-run.txt`.
- [X] T027 Control and no-hooks on the final `keep.yaml`: both PASS, exit 0; each namespace deleted at its end. Evidence: `/Users/patrickemmanual/keep-uninstall-evidence/2026-11-09-t027-rerun/` (`control-run.log`, `nohooks-run.log`, `keep-uninstall-control.bucdml/`, `keep-uninstall-nohooks.YImSJi/`).
- [X] T028 `make lint` once (exit 0). Evidence: `evidence/make-lint-final.txt`.
- [X] T029 `make story-cost STORY=010-keep-install-aks` (exit 0). Partial accounting only: 1 row, $2.24, "no change"; `cleanupPeriodDays` is null, so older logs are lost after 30 days. Evidence: `evidence/story-cost-run.txt`.
- [X] T030 SC-003 frontend check through Playwright 1.64.1 (ephemeral, temp folder deleted afterwards): 0 calls outside localhost in 25.25 s; no login form. Evidence: `evidence/playwright-run.txt`. Chromium download: 99 MiB (measured); the CDN HEAD request had returned 400 earlier.

## Evidence name corrections

The earlier task text named two files that do not exist: `k3d-partial-install.txt` is `partial-install.txt`, and `install-check.txt` is `install-check-live.txt`. `make-lint.txt` is `make-lint-final.txt`.
