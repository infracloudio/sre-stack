# Implementation Plan: Slow Database Fault for the Demo Shop on Azure

**Branch**: `008-aks-db-latency-fault` | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-aks-db-latency-fault/spec.md`

## Summary

The fault is a fixed wait added to three of MySQL's own queries by the Rewriter plugin that ships in the existing database image: 2.5 s for the two shipping queries and 0.5 s for the ratings query (`research.md` Findings 9 and 12). One Bash script with three verbs (`start`, `status`, `revert`) installs the plugin if it is missing and turns the rules on or off; revert only disables them (Finding 10). The shop gets slower with identical answers, no errors and no data change. A new panel on the Database dashboard shows the average query time, and a new Azure-only dashboard lists slow requests and opens their step-by-step view. The approach changed in Phase 0 from lowering the database's CPU limit to this plugin (Findings 8 and 9).

## Technical Context

**Language/Version**: Bash 5 scripts (`GNU bash, version 5.2.21(1)-release`) called from GNU make targets. No application code changes; the shop runs upstream images.

**Primary Dependencies**:
- `kubectl` client `v1.33.4`, `helm` `v3.18.6`, `az` `2.91.0`, signed in to `Pune - Sandbox (TPM)`. AKS cluster `sre-stack-452138` (southindia, Kubernetes 1.34, 9 nodes) is where every finding was run.
- The database is the `mysql-0` pod in `robot-shop` (containers `mysql`, `mysql-exporter`, Istio sidecar), MySQL 5.7.35 from the existing image `robotshop/rs-mysql-db:latest`. The fault uses the Rewriter plugin that ships inside that image (`/usr/share/mysql/install_rewriter.sql`): no new image, chart or pod (Findings 9 and 10).
- Only ratings and shipping use MySQL (Finding 3 and spec Assumptions).
- The mesh sidecars, Prometheus, Grafana, Beyla and Tempo from `make setup-aks-o11y` show the result (Findings 11 and 12). Grafana already has a Tempo datasource (`uid` `EbPG8fYoz`).

**Storage**: No local state file. The fault state is the `enabled` column of `query_rewrite.rewrite_rules` inside the database, read through `kubectl exec` into `mysql-0`, so anyone with cluster access can run status or revert (EC-005). A database restart wipes it (Finding 14).

**Testing**:
- No offline (fake-`kubectl`) tests, following the developer's decision on story 006, re-confirmed on 007.
- Live on `sre-stack-452138`: start → status → revert → status, with the load generator running, timed against SC-001 to SC-008, SC-010, SC-012, SC-014 and SC-015. The data check from Finding 12 (`cities` row count and checksum, both shipping route hashes) before and after. Output pasted into the PR.
- `make lint` for every change.

**Target Platform**: AKS only (`STACK_MODE=aks`), namespace `robot-shop`. EKS and k3d are out of scope.

**Project Type**: Operations glue: make targets calling one Azure-only script (new folder `infra/azure/scenario-03/`), guide text in `scenarios/README.md` and `docs/aks-explained.md` (FR-011, FR-014), one new panel in `monitoring/dashboards/mysql.yaml` (FR-015), and a new Azure-only dashboard in `infra/azure/dashboards/` (FR-016).

**Performance Goals**: Start shows slow answers within 60 s (SC-001). After revert, requests are normal within 1 minute and dashboards recover within 5 minutes (SC-004). Each command takes under 60 s including its own check (SC-006). Status takes under 10 s (SC-007).

**Constraints**:
- FR-012 / SC-011: no line changes in `scenarios/scenario-01/`, `scenario-02/`, `scenario-04/`. `makefile` and `.env` gain Azure-only lines only.
- Principle I: every command is safe to run twice (FR-004, SC-010). Start installs the plugin only if it is missing, then enables the rules; revert only disables the rules and leaves the plugin installed (Finding 10).
- FR-006 / SC-008: no data change. The rules rewrite `SELECT`s only (Findings 9 and 12).
- SC-002: slow answers only, no errors. The delays are fixed in the script: 2.5 s for both shipping statements and 0.5 s for ratings (Finding 12).
- The rules match the exact statement text, so a changed upstream image could stop them matching (Finding 9).
- SC-012 / FR-013: a normal setup with the fault never started must not touch the live stack. A shop re-deploy leaves a running fault on (Finding 13).

**Scale/Scope**: One database pod, one namespace, one presenter at a time.

**Phase 0 questions, with where each is answered**:
1. Mechanism: Rewriter plugin rules (Findings 8, 9, 12).
2. Timeouts: the fixed sleep does not time out under overlapping traffic (Findings 9, 12).
3. Normal speeds: shipping `/match` 0.16 to 0.29 s, ratings 0.017 to 0.056 s in the latest run (Finding 12).
4. Re-deploy: the fault stays on (Finding 13).
5. Status: the `enabled` column plus `Rewriter_number_loaded_rules`; the exact status design is a Phase 1 item (Findings 7, 10 and 12).
6. Dashboards: threads running, query rate and a new average-time panel move; a new Azure-only dashboard lists slow requests and links to traces (Findings 9 and 11).
7. Other MySQL users: none (Finding 3).

**Known unknown**: why the data is re-created on a MySQL restart although the data directory is a volume claim is not known (Finding 14). The guides state only the observed behaviour, and the PR lists this as not explained. The empty `ratings` table is explained by the load generator adding the rows (developer's explanation, consistent with Finding 14).

## Constitution Check

*Gate before Phase 0. Re-checked after Phase 1 design.*

| Principle | Status | Why |
|---|---|---|
| I. Re-runnable scripts | Pass | Start, revert and status are idempotent by FR-004 and SC-010. The script follows the pattern of `ratings-abort.sh` and `cart-oom-kill.sh`: resolve repo root, source `.env`, check before change. |
| II. Pinned versions | Pass | No chart or image is added. The plugin ships inside the existing image, whose tag is `latest` (an existing choice, not changed here). Finding 9 notes that a changed image could stop the rules matching. |
| III. One configuration surface | Pass | No new setting. The spec fixes the amounts (Out of Scope), so the delays are constants in the script. |
| IV. No secrets in git | Pass | The database password is read from the running pod's own environment inside `kubectl exec`. No credential is added to a file. |
| V. Workload placement | Pass | No new pod or workload, so no `workload=` pool or taint to choose. |
| VI. Specs without technical detail | Pass | `spec.md` was re-checked after the amendment: no mention of the plugin, MySQL or rules. Technical content lives here. |
| VII. Plain language | Pass | Each plan section is written in plain words. |
| VIII. Try it before you plan it | Pass so far | Findings 1 to 13 ran live on `sre-stack-452138`, with pasted output. Re-checked at the end of Phase 1. |
| IX. Author in steps | Pass | Written one section at a time; the developer asked for items together on 2026-10-22 and 2026-10-23. |
| X. Converge to agreed scope | Not yet applicable | Applies at `/speckit-converge`. |

**Gate result**: no violation. No entry for the Complexity Tracking table.

## Project Structure

### Documentation (this feature)

```text
specs/008-aks-db-latency-fault/
├── spec.md              # Feature specification
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output: Findings 1 to 14, live on sre-stack-452138
├── data-model.md        # Phase 1 output: the three rules, the fault states, the test requests
├── quickstart.md        # Phase 1 output: the live validation run
├── contracts/
│   └── commands.md      # Phase 1 output: make targets, exit codes, RESULT lines
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
infra/azure/scenario-03/
├── db-latency.sh        # new: start | status | revert
└── README.md            # new: short guide beside the script
infra/azure/dashboards/
└── slow-requests.yaml   # new: Azure-only "Slow shop requests" dashboard (FR-016)
monitoring/dashboards/
└── mysql.yaml           # edit: one new average-query-time panel (FR-015)
makefile                 # edit: three aks-db-latency-* targets and help lines; one Azure-only apply line in setup-dashboards
scenarios/README.md      # edit: Azure scenario 03 section
docs/aks-explained.md    # edit: Azure scenario 03 section
```

| File | Change | Requirement |
|---|---|---|
| `infra/azure/scenario-03/db-latency.sh` | New. The pre-checks, the state detection, the three rules, the test requests (`contracts/commands.md`) | FR-001 to FR-009 |
| `infra/azure/scenario-03/README.md` | New. Short guide beside the script, like scenario-01 and scenario-02 | FR-011 |
| `infra/azure/dashboards/slow-requests.yaml` | New ConfigMap with a Grafana dashboard: a Tempo table of slow shipping and ratings requests, trace IDs linking to the span view. Applied only on AKS | FR-010, FR-016 |
| `makefile` | Three targets after `makefile:267`, three help lines after `makefile:37`, and in the `aks` branch of `setup-dashboards` (`makefile:154`) one extra apply of `infra/azure/dashboards/`. No existing line changes | FR-001, FR-012, FR-013 |
| `monitoring/dashboards/mysql.yaml` | One new panel, average statement time, in the "MySQL Dashboard" (uid `549c2bf8936f7767ea6ac47c47b00f2a`). No existing panel changes | FR-015 |
| `scenarios/README.md` | Azure scenario 03 section; says which scenario it is to avoid the EKS "Scenario 02/3" mix-up | FR-011, EC-009 |
| `docs/aks-explained.md` | Azure scenario 03 next to the others; correct anything the fault shows to be wrong | FR-014 |
| `.env` | No change planned: no new setting (Constitution III) | FR-012 |

**Structure Decision**: The script goes in a new `infra/azure/scenario-03/` folder, continuing `scenario-01/` and `scenario-02/`. The slow-requests dashboard goes in a new Azure-only folder `infra/azure/dashboards/`, not in the shared `monitoring/dashboards/`, so it appears only on Azure and EKS or k3d never see an empty trace table (developer decision, 2026-10-23). The average-query-time panel goes in the shared `mysql.yaml` (precedent: story 007 added a section to the shared `application.yaml`); it uses the same MySQL exporter metric on every stack. Nothing under `scenarios/scenario-01/`, `-02/` or `-04/` changes.

## Verification Strategy

- **Live run:** `quickstart.md`, once after implementation, with output pasted into the PR.
- **Lint:** `make lint` for every change, with its real output.
- **Dashboards:** `kubectl apply --dry-run=client` on both ConfigMaps, then loaded in Grafana and checked with the Playwright browser. `helm template` is not needed: no chart changes.
- **Reading the script** covers what the live run cannot reach, as named in `quickstart.md`.
- **No offline (fake-`kubectl`) tests**, following stories 006 and 007.

## Complexity Tracking

No Constitution Check violations, so nothing to justify.
