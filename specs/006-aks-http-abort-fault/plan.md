# Implementation Plan: HTTP Abort Fault for the Demo Shop on Azure

**Branch**: `006-aks-http-abort-fault` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-aks-http-abort-fault/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Give presenters on Azure three one-line commands — start, status, revert —
that make the demo shop's ratings service answer every request with error 500
until reverted, check their own result, and refuse safely on the wrong
cluster (spec FR-001–FR-013).

Approach, settled on the live AKS cluster ([research.md](research.md)): start
adds a 100% abort fault to the shop's existing `ratings` routing rule (a
second rule is silently ignored, Finding 1) and revert removes it, restoring
the rule exactly. Each command checks the result with 10 requests sent from
inside the meshed `web` pod (Finding 3) and tells this fault apart from a real
ratings failure by the `fault filter abort` answer (Finding 4). A shop
reinstall keeps the fault (Finding 2). Errors show on the existing Application
Dashboard within about 15 s and clear about 60 s after revert (Finding 5).
New files live in `infra/azure/scenario-01/` (Finding 6); EKS scenario files
are untouched.

## Technical Context

**Language/Version**: Bash 5 scripts (`GNU bash 5.2.21` on the builder's machine) called from GNU make targets, plus one Istio routing file in YAML. No application code changes; the shop runs upstream images.

**Primary Dependencies**:
- `kubectl` (client `v1.33.4` here) talking to the AKS cluster named in the current context.
- Istio `1.30.4` (`.env` line 31, `ISTIO_VERSION=1.30.4`), installed by `infra/scripts/cluster/setup-istio-aks.sh`. The fault uses Istio's "fault injection" feature: a rule on a routing object (a *VirtualService*, Istio's per-service traffic rule) that answers a share of requests with an error instead of passing them on.
- The shop's own routing object for ratings, made by the Helm chart from `app/robot-shop/helm/templates/ratings-vs.yaml` (plain route to host `ratings`, no fault). Seen live: `kubectl get virtualservice -n robot-shop` lists `ratings` with host `["ratings"]`.
- The ratings Service listens on port 80 (`app/robot-shop/helm/templates/ratings-service.yaml`, port name `http`).
- Monitoring already installed by `make setup-aks-o11y` (Prometheus, Grafana); no new dashboards (FR-007).

**Storage**: None. Whether the fault is on is held only by the ratings routing object in the cluster; no local state file, so anyone can run status or revert (EC-003).

**Testing**:
- No offline (fake-`kubectl`) tests — developer's decision, 2026-10-14; see Project Structure.
- Live: start → status → revert → status on the AKS cluster with the load generator running, timed against SC-001, SC-003, SC-005; output pasted into the PR.
- `make lint` for every change.

**Target Platform**: AKS only (`STACK_MODE=aks`, `.env` line 5), shop namespace `robot-shop` (`.env` line 38, `APP_NS=robot-shop`). EKS and local not tested (out of scope).

**Project Type**: Operations glue — three make targets (start, status, revert) calling one Azure-only script.

**Performance Goals**: Each command under 30 s including its own check (SC-005); dashboards show errors within 60 s (SC-001); ratings answers normally within 10 s of revert (SC-003).

**Constraints**:
- FR-009 / SC-008: no line changes in `scenarios/scenario-01/`, `scenario-02/`, `scenario-04/`. The existing `makefile` and `.env` only gain Azure-only additions.
- Principle I: every command safe to run twice (FR-004, SC-007).
- No timer: the fault stays until revert (FR-003), unlike `scenarios/scenario-01/scripts/inject-vs-fault.sh`, which sleeps `SCENARIO_01_TIMEOUT` and then removes it.
- Commands must not change shop traffic (spec Out of Scope), unlike the old script, which sets `NUM_CLIENTS=5000`.

**Scale/Scope**: One routing object, one namespace, one presenter at a time.

**Settled in Phase 0 on the live cluster** — see [research.md](research.md):
1. Apply the fault by changing the chart-owned `ratings` rule in place; a second rule for the same host is ignored by Istio (Finding 1).
2. EC-002: re-running `make setup-robot-shop` keeps an active fault while the chart's ratings rule file is unchanged (Finding 2).
3. Test requests: one `kubectl exec` into the `web` pod sends 10 requests to `http://ratings/_health`; a pod without a sidecar bypasses the fault (Finding 3).
4. "Our fault" vs "ratings really failing": the rule holds the fault and answers carry body `fault filter abort`; a real outage answered `503 no healthy upstream` (Finding 4).
5. Dashboards: Application Dashboard → "Non-2xx Responses by Service" (ratings tile) and "5xxs"; errors seen at t+15 s, back to zero t+62 s after revert; "Server" panels and ratings logs stay blank (Finding 5).
6. New files live in `infra/azure/scenario-01/` (Finding 6, developer's choice).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `.specify/memory/constitution.md` v1.4.0. Result: **pass, no violations**, so Complexity Tracking stays empty.

| Principle | How this plan meets it | Status |
|---|---|---|
| I. Re-runnable scripts | The script resolves the repo root, sources `.env`, and looks before it changes anything: start only adds the fault when it is missing, revert only removes it when it is present, so running either twice ends in the same state (FR-004, SC-007). A plain "remove" on a rule without the fault would fail, which is why revert checks first. | Pass |
| II. Pinned versions | No new chart, image or tool. Uses the Istio `1.30.4` already pinned in `.env` and the shop's existing images. The `curlimages/curl:8.10.1` pod was research only and is not part of the change. | Pass |
| III. One configuration surface | Reads the shop's namespace from `.env` (`APP_NS`); no new setting is needed. Any later addition to `.env` is Azure-only and keeps every existing line (FR-009, SC-008). | Pass |
| IV. No secrets in Git | Nothing secret is read or written. | Pass |
| V. Workload placement | No new workload; the commands only change an existing routing rule and run a check inside the existing `web` pod. | Pass (nothing to place) |
| VI. Specs without technical detail | `spec.md` is not changed by planning; all technical detail is here and in `research.md`. | Pass |
| VII. Plain language | Plan, research and both guide updates (FR-008, FR-011) explain terms on first use, for example "routing rule" and "sidecar". | Pass |
| VIII. Try it before you plan it | Findings 1–5 were run on the live AKS cluster `sre-stack-452138` with output pasted verbatim, failures included (a broken first polling attempt in Finding 5). No substitutes were used. Not tested, and stated in `research.md`: ratings itself answering `500` (Finding 4), and a shop reinstall across a chart change (Finding 2). | Pass |
| IX. Author in steps | Each section and finding was proposed and approved one at a time in this session. | Pass |
| X. Converge to agreed scope | The live quickstart traces each step to FR, SC and EC items; nothing is added beyond them. No offline tests (developer's decision); the refusals the live run does not exercise are named under Project Structure. | Pass |

**Verification and evidence**: `make lint` for every change; a live start → status → revert run timed against SC-001, SC-003 and SC-005, with its output attached to the PR (`evidence:attached`).

**Protected paths**: none of the files this story changes (`makefile`, `infra/azure/scenario-01/`, `docs/aks-explained.md`, `scenarios/README.md`) match `agent/hooks/protected-paths.txt`.

**Outside the story's scope, raised for the Architect**: one line added to `.gitignore` during research (`.playwright-mcp/`, the browser tool's screenshots). It is not part of this story; either keep it on this branch and name it in the PR, or move it to its own small change.

## Project Structure

### Documentation (this feature)

```text
specs/006-aks-http-abort-fault/
├── spec.md              # approved specification
├── plan.md              # this file
├── research.md          # Phase 0: live findings 1–6 + shipping note
├── data-model.md        # Phase 1: rule, check, states, pre-checks
├── contracts/
│   └── commands.md      # Phase 1: make targets, RESULT line, exit codes
├── quickstart.md        # Phase 1: live validation run for the PR
└── tasks.md             # Phase 2 (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
infra/azure/scenario-01/                 # NEW folder (research Finding 6)
├── ratings-abort.sh                     # NEW: start | status | revert
└── README.md                            # NEW: the Azure scenarios guide (FR-008)

makefile                                 # ADD only: 3 targets, 3 help lines
scenarios/README.md                      # ADD only: one Azure line linking the new guide
docs/aks-explained.md                    # EDIT: "Scenario 01, version 1" + "How to start" (FR-011)
```

| File | Change | Why | Spec |
|---|---|---|---|
| `infra/azure/scenario-01/ratings-abort.sh` | new | the one script behind all three commands; follows data-model §1–§5 and contracts/commands.md | FR-001–FR-006, FR-012, FR-013 |
| `infra/azure/scenario-01/README.md` | new | the Azure guide: what must be running, start, status, revert, which panels to watch, the blank "Server" panels, the always-red `user` tile, that a reinstall keeps the fault, that the old scenario-01 scripts are for EKS | FR-008, EC-001, EC-002, EC-006 |
| `makefile` | add `aks-ratings-abort-start`, `-status`, `-revert`; three lines in the "Azure (AKS)" block of `help` (`makefile:24–33`) | the documented one-line commands | FR-001, FR-002, FR-013, SC-008 |
| `scenarios/README.md` | add one line under the existing list | so someone browsing the scenarios finds the Azure guide; existing lines unchanged | FR-008, SC-008 |
| `docs/aks-explained.md` | rewrite "Scenario 01, version 1" (`:574–601`) and the version-1 part of "How to start a scenario" (`:634–645`) to use the new commands; fix its dashboard table (it says "Global Success Rate drops below 100%", which showed `NaN` in Finding 5, and does not warn about the blank "Server" panels); also reword the text that calls every scenario timed with 5,000 shoppers — section 8 "In short" (`:545–549`), "How every scenario works" (`:551–563`), "Turning the dial" (`:531–537`) — so version 1 runs at normal traffic until reverted, and name `infra/azure/scenario-01/` in the repo map (`:749`, `:755`) | the two guides must not give conflicting steps; version 2 (slow readiness) text stays | FR-011 |
| `.gitignore` | already changed during research (`.playwright-mcp/`) | not part of this story; raised in Constitution Check | — |

**Not changed**: anything under `scenarios/scenario-01/`, `scenario-02/`,
`scenario-04/` (FR-009, SC-008); `.env` (no new setting, data-model §6); the
shop's Helm chart, including `ratings-vs.yaml` and the shipping resources
(the in-cluster shipping fix in research.md is a follow-up story).

**Structure Decision**: one Azure-only folder, `infra/azure/scenario-01/`,
holds the script and its guide, following `infra/azure/load-gen/`; shared
files only gain lines.

**No offline tests** (developer's decision, 2026-10-14): the approved
Technical Context first planned fake-`kubectl` checks; the developer dropped
them, and Technical Context is updated to match. Proof comes from the live
run in [quickstart.md](quickstart.md) and `make lint` (shell lint covers the
new script). What that leaves unproven: of the seven pre-checks in
data-model §5, the live run exercises only "cluster not reachable"
(quickstart step 13); the other six refusals (wrong `STACK_MODE`, not AKS,
mesh down, shop missing, web pod not in the mesh, no `curl`), and status
states 4 and 5, are checked by reading the script in review, not by running
them. Named for the Architect at the plan gate and in the PR.

## Verification Strategy

What the builder runs, and what goes into the PR as evidence
(`evidence:attached`).

| # | Check | When | Proves | Evidence in PR |
|---|---|---|---|---|
| 1 | `make lint` | every commit | shell and YAML lint of the new script and makefile lines; no protected path touched; Spec Kit and loom unchanged | full output |
| 2 | Live run of [quickstart.md](quickstart.md) steps 1–14 (with 7a) on a fresh `make setup-aks` with every shop pod Ready and the load generator running | once, after implementation | FR-001–FR-013 (FR-006 for "cluster not reachable" only), SC-001–SC-009, EC-001, EC-002, EC-004 (step 7a), EC-005 (one case) | terminal output of each step, `time` lines for SC-005, the clock times of steps 4 and 10 |
| 3 | Grafana screenshots: Application Dashboard with the fault on (ratings tile red, "5xxs" up) and 2 min after revert (tile gone / 0) | during step 2 | FR-007, SC-001, SC-003, SC-004 | two screenshots |
| 4 | `git diff --stat main -- scenarios/scenario-01 scenarios/scenario-02 scenarios/scenario-04` empty; `git diff main -- makefile .env scenarios/README.md` shows added lines only | before opening the PR | FR-009, SC-008 | both outputs |
| 5 | The owner follows only `infra/azure/scenario-01/README.md` for one start → status → revert cycle | once, before review | SC-006, FR-008 | a one-line note in the PR |
| 6 | Read-through of `docs/aks-explained.md` "Scenario 01, version 1" and "How to start a scenario" against the new guide | before review | FR-011 (no conflicting steps) | the owner's note in the PR |

**Not proven by running** (named in the PR, per Project Structure): the six
pre-check refusals other than "cluster not reachable", and status states 4
("fault set but not taking effect") and 5 ("a fault this command did not
set") — checked by reading the script. From research: ratings itself
answering `500`, and a reinstall across a change to the chart's ratings rule.

**Known cluster conditions** that would fail check 2 for reasons outside this
story (research.md, Quickstart note): the database-loading job can stall and
`shipping` can be starved at its 200m CPU limit on a fresh setup. Quickstart
prerequisite 2 (every pod Ready) catches this before the run starts.

## Complexity Tracking

None — the Constitution Check found no violations.
