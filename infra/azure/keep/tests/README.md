# Keep uninstall tests (story #123)

**Status (2026-11-09).** Both live k3d runs passed, with no script edits between them. Control: fresh namespace `keep-uninstall-control`, PASS, exit 0. No-hooks: namespace `keep-uninstall-test` deleted, recreated and installed, PASS, exit 0. Evidence copies: `/Users/patrickemmanual/keep-uninstall-evidence/2026-11-09-live-pass/` (`keep-uninstall-control.tEGNGC`, `keep-uninstall-nohooks.KnVT4e`). Throwaway Keep installs ran on AKS on 2026-10-29 (research Findings 3, 6, 7 and 8). `setup-keep` and the uninstall have not run on AKS. Both runs used the k3d overlay that has since been removed, and are superseded by the runs below. **Final-file runs (2026-11-09, `infra/azure/chart-values/keep.yaml`, no overlay): control PASS, no-hooks PASS.** Evidence: `/Users/patrickemmanual/keep-uninstall-evidence/2026-11-09-final-values/` (control `keep-uninstall-control.c3Znkh`, no-hooks `keep-uninstall-nohooks.eABlfZ`). The control's hook Pod ran on `k3d-keep-uninstall-test-agent-1`, the untainted agent. `--no-hooks` created no hook Pod.

**Versions.** k3d v5.9.0; k3s v1.36.4+k3s1 (API at `127.0.0.1:6443`); kubectl client 1.34; Helm v3.14.4+g81c902a (checksum from `get.helm.sh`); chart `keephq/keep` 0.1.97 (app 0.54.3).

**Proven on k3d (live).**
- Keep 0.1.97 installs with `keep.yaml` and the k3d overlay (superseded, see Status); all four pods reach 1/1 Ready; the pinned busybox, MySQL 8.4.13 and `alpine/k8s:1.34.11` digests ran.
- The control: the hook Job runs to `Complete 1/1` and is deleted; the hook Pod appears; the hook log shows the matching decoy deleted; `keep-decoy-control` is removed and `sre-keep-decoy-control` is kept.
- The watch layout on k3s v1.36.4: default table and `-o wide`, with an `EVENT` column.
- The no-hooks run: `helm uninstall --no-hooks` exits 0; `helm status` then reports `not found`; no hook Job or Pod is created; `events.txt` is empty; both decoys and every `keep-*` Secret remain; 18 OK health samples and no DEAD line.
- The gated sentinel Pod stays `SchedulingGated` and `Pending`, with no node and no container status; the readiness check passes on real watch data.
- The version check reads the server version from `/version` (1.36).

**Not proven.**
- Any step on AKS (Kubernetes 1.34).
- Helm 3.14.4 behaviour when a hook fails, and the Helm checksum signature (GitHub lists only `.asc` files for this build; not verified).
- Scheduling-gate and scheduler-name enforcement against another scheduler, or when another principal removes the gate.
- Watch gaps during long runs, and the 20 s and 60 s bounds under load.
- A plain `helm uninstall` (not the documented command), so the FR-003 gap remains.
- The runtime effect of usage reporting (no outbound-traffic test), frontend key isolation, Secret file permissions, and the `NEXTAUTH_SECRET` blocker.
- Digests on the registry beyond their use here (no arm64 check).
- The cleanup script on a live namespace (stub-tested only).
- FR-008, FR-009 and SC-009.

The watch design is Option B, checked offline against the raw probe output in `fixtures/`. The offline checks pass.

## Files

| File | Purpose |
|---|---|
| `lib-uninstall-test.sh` | Shared functions and watch rules. Sourced by the test scripts. Not run directly. |
| `keep-uninstall-control.sh` | Positive control. Passed live on 2026-11-09. |
| `keep-uninstall-nohooks.sh` | The documented command, `helm uninstall keep -n <ns> --no-hooks`. Passed live on 2026-11-09. |
| `keep-manual-cleanup.sh` | Administrator Secret cleanup after the documented uninstall. Delete loop fixed and stub-tested. Not run against a cluster. |
| `watch-rules-test.sh` | Offline tests of the watch rules, against `fixtures/` and negative cases made from them. No cluster call. |
| `log-capture-test.sh` | Offline tests of the hook log capture with a stub kubectl: two BadRequests then success; never succeeds; Pod disappears; success with empty output. The last three must be INCONCLUSIVE. |
| `fixtures/` | Raw probe output, 2026-11-09, k3s v1.36.4. |
| `SHA256SUMS` | SHA-256 manifest of the five scripts, the four fixtures and `keep.yaml`. |

The values file is `infra/azure/chart-values/keep.yaml`. It uses `gp2` on AKS and on k3d. On k3d, `gp2` is defined by `infra/local/gp2-storageclass.yaml` on `rancher.io/local-path`. The k3d overlay has been removed.

## Keep test install: keep-uninstall-control

**Test-only.** The Secrets exist only in `keep-uninstall-control` on the disposable cluster. They hold dummy values, except the database password, which `openssl rand -hex 24` generated once. The same password is used in `mysql-root-password` and inside `DATABASE_CONNECTION_STRING`. None of them is a real credential. No value is stored in a tracked file or printed. Each carries the label `keep-test-only=true`. The local folder `~/.secrets/keep` was not used and does not exist.

| Secret | Keys |
|---|---|
| `sre-keep-db` | `DATABASE_CONNECTION_STRING`, `mysql-root-password` |
| `sre-keep-ai-env` | `fireworks.key` (dummy) |
| `sre-keep-ai-frontend` | `OPEN_AI_API_KEY` (dummy) |

**Chart and tools.** The chart comes from `https://keephq.github.io/helm-charts`, the repository the Keep docs name. The pulled chart matches the local copy file by file. Helm 3.14.4 was downloaded from `get.helm.sh`, checked against its published `.sha256sum`, and kept in the scratchpad. It was used through PATH for these runs only. The GitHub release lists only `.asc` signatures for this build, so the signature was not checked.

**Install command used:**

```bash
helm install keep keephq/keep --version 0.1.97 -n keep-uninstall-control \
  -f infra/azure/chart-values/keep.yaml
```

**Checks.** `helm lint --strict` and `helm template` pass under 3.14.4. `keep.yaml` alone renders `storageClassName: gp2`, on both targets. Numeric env values render as quoted strings, such as `value: "1"` and `value: "6001"`.

### Deliberate differences from the chart defaults

These are intended. Helm replaces each list in full, so every restated list repeats the chart defaults and adds or changes only the items below.

1. `DATABASE_CONNECTION_STRING` is read from Secret `sre-keep-db`, not from a literal value. The literal entry is removed, because the chart would otherwise render the variable twice.
2. MySQL env: `MYSQL_ALLOW_EMPTY_PASSWORD` and `MYSQL_PASSWORD` are removed. `MYSQL_ROOT_PASSWORD_FILE` is added. The root password comes from a mounted key only. Without the `items` restriction, the whole Secret would be mounted.
3. The chart's busybox wait container is replaced by a digest-pinned copy, and the chart's own wait is disabled.
4. Images pinned by digest: MySQL `8.4.13`, and the cleanup Job's `alpine/k8s:1.34.11`.
5. Usage reporting off: `POSTHOG_DISABLED` on backend and frontend, `SENTRY_DISABLED` on frontend.
6. AI settings: `OPENAI_API_KEY` comes from Secret `sre-keep-ai-env` through `secretKeyRef`. `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME` are added to backend and frontend. The frontend loads `sre-keep-ai-frontend` through `envFromSecrets`.
7. Storage: `database.pv.enabled: false`. The claim's class is `gp2` in `keep.yaml`, on both targets.
8. Placement: `nodeSelector: workload: o11y` and the o11y and Azure spot tolerations on backend, frontend, websocket and database. The chart default is empty. The chart's cleanup Job has no placement keys, so it cannot be placed through values.

**Blocker for AKS.** `NEXTAUTH_SECRET` is `secret`, the chart default, and is kept for the test only. It must be replaced by a generated value before any AKS install.

## Run order (both live runs completed on 2026-11-09)

Run from the repository root.

```bash
# 1. Positive control first. Its evidence folder is printed at the end.
EXPECTED_CONTEXT=k3d-keep-uninstall-test bash infra/azure/keep/tests/keep-uninstall-control.sh
# 2. Documented command. Refuses unless the control passed on the same context.
EXPECTED_CONTEXT=k3d-keep-uninstall-test CONTROL_EVIDENCE=<control folder> \
  bash infra/azure/keep/tests/keep-uninstall-nohooks.sh
```

The control scripts expect release `keep` in their namespace. The no-hooks run needs a release in `keep-uninstall-test`, which does not exist yet.

Exit codes: 0 PASS, 1 FAIL, 2 REFUSED before any change, 3 INCONCLUSIVE. A missing event, a malformed row, a failed query, or a failed readiness check is INCONCLUSIVE, never PASS. Optional: `EVIDENCE_ROOT` (default `$TMPDIR` or `/tmp`) and `KEEP_NS=1` (keep the namespace).

## Integrity and static checks

```bash
cd infra/azure/keep/tests && shasum -a 256 -c SHA256SUMS && cd - >/dev/null
bash infra/azure/keep/tests/watch-rules-test.sh
for f in infra/azure/keep/tests/*.sh; do /bin/bash -n "$f" && bash -n "$f"; done
shellcheck -x -P infra/azure/keep/tests infra/azure/keep/tests/*.sh
```

The control and no-hooks scripts check the three test scripts against `SHA256SUMS` before any cluster change. They do not check the cleanup script or the values file. Those are checked only by the manual command above.

## Watch design (Option B)

Observed on the probe, with `--output-watch-events`:

- The first column is the event type, `ADDED`, `MODIFIED` or `DELETED`. The header `EVENT` is printed once.
- `custom-columns` was rejected. It printed no EVENT column and `<none>` for every object field.
- A gated sentinel Pod shows STATUS `SchedulingGated` (its phase is `Pending`), NODE and IP `<none>`, and a `DELETED` row whose STATUS is `Terminating`.
- A completing Job shows `ADDED Running 0/1`, then `MODIFIED SuccessCriteriaMet`, then `MODIFIED Complete 1/1`, then `DELETED Complete 1/1`. DURATION is blank until the Job starts, so positions shift.
- Repeated `MODIFIED` rows occur with no change in STATUS. They are object writes, not AGE timers. The rules never count them, and they never read AGE.

Rules, implemented in `lib-uninstall-test.sh`:

1. **Header.** The first line, split on whitespace, must equal the expected header for its watch. A mismatch is INCONCLUSIVE.
2. **Event type.** Column 1 of every later non-blank row must be `ADDED`, `MODIFIED` or `DELETED`.
3. **Jobs.** STATUS is field 3. COMPLETIONS is found by pattern `N/M` among fields 4 onward. Every Job row needs one.
4. **Job success (control).** An `ADDED` row, then a non-`DELETED` row with STATUS `Complete` and COMPLETIONS `1/1`, then a `DELETED` row. Any row with STATUS `Failed` or `FailureTarget` is a FAIL. A missing step is INCONCLUSIVE.
5. **Pods.** Every row has exactly 10 fields. A different count is INCONCLUSIVE, with the line number.
6. **Sentinel Pod.** The first row is `ADDED` and the last is `DELETED`. Every row has IP and NODE both `<none>`. Every row before the last two has STATUS `SchedulingGated`. Of the last two, only a `MODIFIED` or `DELETED` row may be `Terminating`. A `DELETED` row before the last row is a violation. Any other STATUS is a violation: the gate was removed or the Pod was processed. A violation is INCONCLUSIVE.
7. **AGE.** Never read or compared.

The Pod check cannot see the scheduling gate itself. The gate is verified by a read-back after creation, and the table STATUS `SchedulingGated` implies the gate is still in place. If the gate is removed, STATUS changes and rule 6 fails.

Offline result on 2026-11-09, under Bash 5.3 and Bash 3.2: 14 cases, 14 as expected, 0 failed.

| Case | Input | Expected | Result |
|---|---|---|---|
| P1 | ConfigMap default table, real output | accepted | pass |
| P2 | Job default table, real output, layout | accepted | pass |
| P3 | Job default table, control state | OK | pass |
| P4 | Pod `-o wide`, real output, layout | accepted | pass |
| P5 | Pod `-o wide`, sentinel rows | accepted | pass |
| N0 | Pod default table, not `-o wide` | rejected (header) | pass |
| N1 | Mutated header | rejected (header) | pass |
| N2 | Sentinel with no DELETED row | rejected | pass |
| N3 | Sentinel row with STATUS Running | rejected | pass |
| N4 | Sentinel row with a node name | rejected | pass |
| N5 | Job row with STATUS Failed | FAILED | pass |
| N6 | Pod row with nine fields | rejected | pass |
| N7 | Job with no Complete 1/1 row | MISSING | pass |
| N8 | Misspelled event type | rejected | pass |

The negative cases are synthetic mutations of real output. Only the Job `Failed` status is a guess at what kubectl prints, and it has not been observed on a live cluster.

## Helm 3.14.4 verification

Done on 2026-11-09, with the steps below, using the Helm binary from the scratchpad.

1. Platform: `Darwin` and `arm64`.
2. Downloaded `helm-v3.14.4-darwin-arm64.tar.gz` and its `.sha256sum` from `get.helm.sh`.
3. `shasum -a 256 -c helm-v3.14.4-darwin-arm64.tar.gz.sha256sum`: OK.
4. Extracted to a scratch folder. `helm version --short` reports `v3.14.4+g81c902a`.
5. `helm uninstall --help` lists `--no-hooks`.
6. Rendered chart 0.1.97 with the same binary. The `delete-keep-secrets` Job carries the `pre-delete` hook.

## Known limits

- The watch rules were checked offline against real probe output from one kubectl and k3s pair. Both live runs exercised them on k3s v1.36.4 and passed.
- A Job with STATUS `Failed` or `FailureTarget` has not been observed on a cluster. Rule 4 rests on the table's wording.
- A watch gap can hide an event. The health monitor detects dead processes, not gaps.
- Process termination is incomplete. `run_limited` signals only the command's own PID. Child processes of an `exec`-plugin kubeconfig could outlive a timeout. The risk is recorded in research.md.
- The sentinel Pod's `schedulerName` and `schedulingGates` depend on the API server honoring both fields. On k3s v1.36.4 the probe Pod stayed unscheduled and showed the expected gate. An authorized principal who can patch the Pod could remove the gate.
- The k3d cluster runs Kubernetes v1.36.4 with a kubectl 1.34 client. AKS runs Kubernetes 1.34, so AKS behaviour is unverified.
- The MySQL claim uses `gp2`, which on k3d is backed by `rancher.io/local-path`, so data is node-local and is not persistent across cluster recreation.
