# Plan: Install Keep on AKS with one command (story #123)

**Spec**: [spec.md](spec.md) | **Research**: [research.md](research.md) | **Status** (2026-11-09): sections 1 to 8 have content; 7 and 8 draft, pending review.

Word count overrun: 919 against 600; section 1 keeps the AD-016 statuses, and evidence lives in research.md and the tests README.

## 1. Approach and reasons

`make setup-keep` installs Keep 0.1.97 from one values file and local-file Secrets.

1. **Values file.** One `keep.yaml`, no `--set`, with o11y placement. Difference: chart default placement is empty.
2. **Pinned images.** Digests: busybox, MySQL, cleanup Job. Difference: chart uses untagged busybox, `mysql:latest`, `bitnami/kubectl:latest`.
3. **Usage reporting off.** Difference: chart sets no switch; we set `POSTHOG_DISABLED`.
4. **Storage.** Claim on `gp2`, no PV. Difference: chart creates PV `keep-pv`.
5. **Secrets.** AI and database Secrets from local files. Difference: chart sets the connection string as a literal.
6. **Uninstall.** `--no-hooks`, then manual Secret cleanup. Difference: chart's pre-delete hook deletes `keep-*` Secrets.
7. **Shared ServiceAccount.** Accepted residual risk (AD-016 decision 4). Difference: none.

AD-016 status (developer-reported Architect acceptance, 2026-11-09): decision 1 accepted; 2 accepted, with FR-006 and FR-012 (D2); 3 no status item; 4 accepted as residual risk; 5 agreement recorded 2026-11-06; 6 mechanism accepted, enforcement not implemented.

PR #143's GitHub approval (2026-11-07) has no body text and is not evidence of Architect acceptance.

## 2. Technical Context

- **Versions.** Helm v3.14.4. Chart `keephq/keep` 0.1.97 (app 0.54.3). Test: k3d v5.9.0, kubectl 1.34. Target: AKS 1.34 (patch 1.34.11 unverified).
- **Support.** AKS 1.34 supported; end of life in section 8. Source: `learn.microsoft.com/azure/aks/supported-kubernetes-versions` (ms.date 09/15/2026).
- **Images.** Digests (SC-004): busybox 1.38.0, MySQL 8.4.13, alpine/k8s 1.34.11. Exact tags: keep-api and keep-ui 0.54.3, soketi 1.4-16-debian (exists on quay.io; last modified 2022-08-21; stability unverified).
- **Scripts.** Test scripts: Bash 3.2 and newer (3.2.57, 5.3 verified). Setup script: Bash 4 or newer.
- **Storage.** `gp2` on AKS; on k3d, `gp2` from `infra/local/gp2-storageclass.yaml`.

## 3. Constitution Check

- **II.** Chart values in `*/chart-values/`. Check: `grep -rn -- '--set' infra/azure/keep infra/azure/chart-values/keep.yaml | wc -l` is 0.
- **III.** Chart settings are "Principle II's exception" (AD-006, line 335); `KEEP_SECRETS_DIR` is the only Keep `.env` key, planned. Check: not yet in `.env` (grep count 0).
- **V.** Placement (nodeSelector, tolerations) renders on four workloads in `helm template`. k3d NODE column (transcribed): all four on agent-0. AKS research run (Finding 6) used earlier values; final `keep.yaml` unrun on AKS.

## 4. Changed paths and dependencies

Done: `infra/azure/chart-values/keep.yaml`, `infra/azure/keep/tests/`, `specs/010-keep-install-aks/plan.md` (untracked). `specs/010-keep-install-aks/research.md`, `docs/architectural-decisions.md` (modified, tracked).

Planned: `infra/azure/keep/setup-keep.sh`, `infra/azure/keep/README.md`, FR-008 and FR-009 tests under `infra/azure/keep/tests/` (untracked). `makefile`, `.env` (modified, tracked). None matches `agent/hooks/protected-paths.txt`.

Dependencies: Helm 3.14.4, kubectl, k3d 5.9.0 (tests only), jq (FR-008 snapshot, planned), Bash 4 or newer (setup script).

## 5. Security and secrets

Rule (AD-008, Decision): "Nothing secret is in `.env`, a values file, a manifest, or a template." Credentials stay in an untracked folder, `$HOME/.secrets/keep`. Folder mode 700, file mode 600 (research.md lines 650 to 652; AD-008 line 465).

Tested: the hook deletes `keep-*` Secrets (research Finding 6, AKS throwaway, 2026-10-29). Final control (k3d, 2026-11-09): the hook deleted `keep-decoy-control` and kept `sre-keep-decoy-control`.

Not tested: `setup-keep`; folder modes; FR-008 and FR-009; frontend key isolation; manual cleanup (stub-tested only); SC-009 key-name method (not approved); the `NEXTAUTH_SECRET` blocker (section 8). Not run on AKS.

Residual risk: backend Secret permissions are namespace-wide (research Finding 18; developer-reported Architect acceptance, 2026-11-09).

## 6. Test and cleanup procedure

1. Offline: `shasum -a 256 -c SHA256SUMS`; the five offline test scripts; `bash -n`; shellcheck.
2. Setup: k3d with o11y label and taint, gp2 class; `helm install` under Helm 3.14.4 with `keep.yaml` and dummy test Secrets.
3. Live: control, then no-hooks with `CONTROL_EVIDENCE`. Exit 0 PASS, 1 FAIL, 2 REFUSED, 3 INCONCLUSIVE.
4. Cleanup: `keep-manual-cleanup.sh` (stub-tested only).

Evidence: run folder with `run.log`, watch files, hook logs, `script-hashes.txt`, pod listing.
- AKS verification (SC-001 to SC-011): in scope (D5); procedure written in tasks.md and approved at the gate before any AKS run.

## 7. Verification and live results (draft, pending review)

- **AKS.** Throwaway installs ran 2026-10-29 (research Findings 3, 6 to 8); `setup-keep` and uninstall have not run on AKS.
- **k3d.** Final-file runs PASS: control, no-hooks. Earlier runs superseded.

## 8. Risks, departures and open decisions (draft, pending review)

- **Decisions D1 to D9** (developer-reported Architect acceptance, 2026-11-09; full text in research.md): D1 FR-003 wording adopted; D2 FR-006 and FR-012 accepted; D3 FR-008 reads Secret uid and creation time only; D4 `NEXTAUTH_SECRET` generated like `db-password`; D5 AKS verification in scope, procedure in tasks.md; D6 stay on AKS 1.34 (end of life 30 Nov 2026); D7 one real k3d cleanup run; D8 Architect updates the ADR after the gate; D9 runbook path confirmed.
- **Blocker for AKS.** `NEXTAUTH_SECRET=secret` stays in `keep.yaml` until D4 is implemented.
- **Hook placement.** Cleanup Job has no placement keys; it lands on any untainted node (AD-003).
- **D10 (open, Architect decision, recorded 2026-11-12).** `PUSHER_APP_SECRET=keepappsecret` is a literal in our own `infra/azure/chart-values/keep.yaml` (lines 48 and 49, restating the chart default). It is also rendered into the backend and websocket manifests. Impact is low: the websocket is cluster-internal and Keep has no Ingress address. But AD-008 says nothing secret goes in a values file. Options: (a) accept as a documented limit, or (b) generate it like `db-password` and move it into a Secret (a follow-up change, not made here). keep.yaml is not changed.
- **Departure (2026-11-09).** T009 creates the four Secrets only when missing; it does not "create or refresh". Reason: a refresh deletes and recreates the Secret, which changes its UID and creation time (the FR-008 test, D3), and `kubectl apply` is forbidden for Secrets (SC-009). Rotation is the README procedure in T014.
- **Departure (2026-11-09): `~` form of KEEP_SECRETS_DIR.** AD-008 says `.env` holds `$HOME/.secrets/keep`, not `~`. The makefile includes `.env` (make expands `$HOME`), and `agent/tools/story-cost.sh` sources `.env` as shell (`$$HOME` would expand to the process ID). So `.env` holds `~/.secrets/keep`, and setup-keep.sh expands a leading `~/` only. A bare `~` or a literal `$HOME` is refused. The ADR is not edited.
- **Path.** Path matches AD-011, AD-013, architecture.md and `_bmad-output` story; no departure.
