# Implementation Plan: Out-of-Memory Kill of the Demo Shop Cart Pod on Azure

**Branch**: `007-aks-oom-kill` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from [spec.md](spec.md)

## Summary

Give presenters on Azure one documented command that makes the demo shop's cart
pod run out of memory and be killed by the cluster, one that reports whether
the fault is active, and one that restores the shop — each safe to run twice,
each checking its own result, each refusing safely on the wrong cluster
(spec FR-001–FR-014).

Approach, settled on the live AKS cluster `sre-stack-452138`
([research.md](research.md)): start lowers the cart container's memory
allowance to `24Mi` (with `8Mi` asked, because the API server rejects a limit
below an unchanged request — Finding 1) and writes an annotation marker on the
cart Deployment; the cluster kills the container with `OOMKilled` status
within 15 s and repeatedly after that (three kills inside 44 s, wait growing
`10s → 20s → 40s → 1m20s` as EC-007 predicts). Revert reads the allowance the
shop is installed with out of the Helm release manifest at run time (Finding 4,
which is how FR-008's no-replay rule is kept) and removes the marker. Status
reports active only when the marker is present *and* the live allowance is
lowered — the two inputs, one marker and one allowance, so a shop redeploy
(which clears the fault, Finding 3) and a hand-set allowance (EC-008) are
never mistaken for this fault.

The kills and restarts of every pod in every namespace (not only cart, developer
decision 2026-10-21, deviation D16) are shown by adding a Restarts section to the existing
Application Dashboard (FR-011 as clarified; no dashboard the setup installs
tracked restarts or out-of-memory kills before, Finding 2 — the two Prometheus
queries a presenter points at were proven live). New files live in
`infra/azure/scenario-02/` following story 006's Azure pattern; the EKS
scenario folders are untouched.

## Technical Context

**Language/Version**: Bash 5 scripts (`GNU bash, version 5.2.21(1)-release`) called from GNU make targets. No application code changes; the shop runs upstream images.

**Primary Dependencies**:
- `kubectl` (client `v1.33.4`) against the AKS cluster in the current context. `helm` `v3.18.6` is needed to read the allowance the shop is installed with (FR-008).
- `az` CLI `2.91.0`, already signed in to subscription `Pune - Sandbox (TPM)` (`az account show`), where AKS cluster `sre-stack-452138` (southindia, Kubernetes `1.34.11`, `az aks list`) lives. The cluster was stopped when planning began and was started on the developer's go-ahead on 2026-10-21 for Phase 0; `kubectl config use-context sre-stack-452138` and `kubectl get nodes` then listed 9 nodes `Ready` at `v1.34.11`.
- The shop's own cart Deployment, `app/robot-shop/helm/templates/cart-deployment.yaml`: one replica on every target other than EKS (`:8–12`), memory allowance taken from `.Values.cart.resources` (`:38–39`). AKS installs the chart with `infra/azure/chart-values/robot-shop.yaml`, which for cart only sets tolerations — so AKS cart runs at the chart default `limits.memory: 100Mi`, `requests.memory: 50Mi` (`app/robot-shop/helm/values.yaml:44–50`).
- `make setup-robot-shop` (`makefile:289`) runs `helm upgrade --install … --values ./infra/azure/chart-values/robot-shop.yaml --set stack_mode=aks` (`makefile:296`). Any allowance change made by hand therefore has to survive, or be re-applied after, that call — the resolution is a Phase 0 finding (EC-002, FR-008).
- Monitoring already installed by `make setup-aks-o11y`; the dashboards it applies are the five files in `monitoring/dashboards/` (`makefile:151–160`), of which `application.yaml` is the shop's own dashboard. No `OOMKilled` mention exists anywhere in the repo today (`grep -rn OOMKilled` over the tree, outside `.claude/`): the repo has no panel for it yet, so what the installed dashboards actually show is a Phase 0 question (FR-011).

**Storage**: None. Whether the fault is on is held only by the cart Deployment in the cluster; no local state file, so anyone can run status or revert (EC-003).

**Testing**:
- No offline (fake-`kubectl`) tests — following the developer's decision on story 006 (2026-10-14), re-confirmed for this story on 2026-10-21.
- Live: start → status → revert → status on `sre-stack-452138` with the load generator running, timed against SC-001, SC-002, SC-003, SC-005, SC-006; output pasted into the PR.
- `make lint` for every change.

**Target Platform**: AKS only (`STACK_MODE=aks`, `.env:5`), shop namespace `robot-shop` (`.env:38`, `APP_NS=robot-shop`). EKS and local are not tested (out of scope per the issue).

**Project Type**: Operations glue — make targets (start, status, revert) calling one Azure-only script, plus guide text.

**Performance Goals**: The kill shows within 60 s of start and 3 kills within 3 minutes (SC-001, SC-002); the pod is back to normal within 60 s of revert and the dashboards are clean within 2 minutes (SC-003); each command under 90 s including its own check (SC-005); status under 10 s (SC-006).

**Constraints**:
- FR-013 / SC-009: no line changes in `scenarios/scenario-01/`, `scenario-02/`, `scenario-04/`. `makefile` and `.env` may gain Azure-only lines; existing lines stay.
- Principle I: every command safe to run twice (FR-005, SC-008).
- Only cart's memory allowance changes; every other service keeps its allowance (FR-006). No traffic change (spec Out of Scope).
- SC-010: a normal setup where the fault was never started keeps zero pods `OOMKilled` for 5 minutes — the new code must not touch the live stack until someone runs start.
- FR-009: start and revert each wait for their own result and report what they saw if it does not arrive.

**Scale/Scope**: One Deployment, one namespace, one presenter at a time.

**Questions Phase 0 settled on `sre-stack-452138`** (all five answered in `research.md` Findings 1–5; kept as the record of what the plan could not answer from files):
1. cart's real memory use against its `100Mi` allowance, and how far the allowance must be lowered to kill it within 60 s but not so far that it dies before the shop is usable at all (SC-001, SC-002, and the spec's "Not yet checked" assumption).
2. Whether the installed dashboards show a pod's `OOMKilled` reason and rising restart count, or only one of the two (FR-011; the spec allows the Architect a different panel if not).
3. Whether `make setup-robot-shop` during an active fault restores the chart's allowance and so clears the fault, which EC-002 expects and FR-008 must tolerate.
4. How status tells "killed by our fault" from "cart ran out of memory on its own" (FR-010, EC-006) — today the repo holds no marker to read, so the marker is a Phase 0 decision.
5. Whether the load generator's traffic actually reaches cart often enough to trigger the kill (the spec's "Not yet checked" assumption, SC-001).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `.specify/memory/constitution.md` v1.4.0. Result: **pass, no
violations**, so Complexity Tracking stays empty. First run before Phase 0
research; **re-run after Phase 1 design** against what the three artifacts and
the live findings actually settled — the rows below record both rounds where
they changed.

| Principle | How this plan meets it | Status |
|---|---|---|
| I. Re-runnable scripts | The script resolves the repo root and sources `.env` as story 006's `infra/azure/scenario-01/ratings-abort.sh` does. start applies the lowered allowance only when it is not already applied, revert restores the allowance the shop is installed with and confirms it is already correct when nothing is active, so running either twice ends in the same state (FR-005, SC-008). Backed by Finding 3's live proof: a second revert against correct values rolled **no new ReplicaSet** — revision unchanged, pod untouched, exit 0. | Pass |
| II. Pinned versions | No new chart, image or tool: the commands patch an existing Deployment and use `kubectl` / `helm` already required by the repo. No inline `--set` chain is added. | Pass |
| III. One configuration surface | The namespace comes from `.env` (`APP_NS`, `:38`) and the mode from `STACK_MODE` (`:5`). The pre-research open question is settled: **no `.env` addition** — the lowered values and the target values live in `data-model.md` §1 and come from the Deployment and the Helm release manifest at run time (FR-008), so `.env` gains no line and every existing line stays (FR-013, SC-009). | Pass |
| IV. No secrets in Git | Nothing secret is read or written; no new file holds credentials. | Pass |
| V. Workload placement | No new workload and no placement change: the commands change one existing container's memory allowance and one annotation. Post-Phase-1 correction: the pre-checks do **not** require the mesh (nothing in this fault sits behind it — `data-model.md` §5), unlike 006; the sidecar itself is injected per pod and untouched (FR-006 holds, Finding 1). Node pool labels and spot taints are untouched (AD-003). | Pass (nothing to place) |
| VI. Specs without technical detail | The story did need one spec change, decided between author and developer — FR-011 rewritten when the live instance showed no dashboard could meet the original wording (Finding 2), and the Clarifications section records why. The amendment names outcomes ("a section on a dashboard already installed"), and the PromQL, datasource, panel shape stay here and in quickstart. | Pass (one amendment, recorded) |
| VII. Plain language | Plan, research and the guide explain terms on first use — "allowance", "out-of-memory kill", "restart count" — with the cart pod as the worked example. | Pass |
| VIII. Try it before you plan it | Completed against the live `sre-stack-452138`: six findings, every output block verbatim from the terminal — including failures and the three transcription slips caught and rewritten in place. No substitute was requested and none was granted; at no point did planning run on remembered output. The five open questions in Technical Context are all answered in `research.md` Findings 1–5 (Finding 6 is a file-check). | Pass |
| IX. Author in steps | Technical Context proposed, corrected on the developer's reading, approved; FR-011 amended on the developer's instruction; each Phase 0 finding and each Phase 1 artifact proposed, approved, then moved past. Nothing in any artifact was written "for context" ahead of approval. | Pass |
| X. Converge to agreed scope | Fourteen FRs, ten SCs and nine ECs are covered by quickstart steps that name them, or explicitly named as not live-exercisable (Part C note and the missing-refusals list); nothing beyond the agreement was added. No offline tests — the developer's 2026-10-14 decision on story 006 carries, and what that leaves unproven is named in the named-for list. | Pass |

**Verification and evidence**: `make lint` for every change; the quickstart live
run (Parts A, B, C) timed against SC-001, SC-002, SC-003, SC-005, SC-006, SC-008
and SC-010, with its output attached to the PR (`evidence:attached`); two
Application Dashboard screenshots — the new Restarts section with the fault on
and after revert (FR-011 as clarified).

**Protected paths**: `agent/hooks/protected-paths.txt` matches none of the files
this story writes — new `infra/azure/scenario-02/*`, the
`monitoring/dashboards/application.yaml` section, the `makefile` and
`scenarios/README.md` additions, and this story's `specs/007-aks-oom-kill/`.
No hook, policy, workflow or generated adapter file changes.

**Named for the Architect at the plan gate** (three, collected here):
1. The dashboard section ships through the same apply the existing dashboards
   use — `setup-dashboards` is the ConfigMap lifecycle for `application.yaml` on
   AKS (`makefile:151–160`), so the new section lands with the same `make`
   command that already runs on every o11y setup; it does not need to be
   applied a second way.
2. The new folder is `infra/azure/scenario-02/` (Azure-only lineage, the
   developer's call after the number came up): `scenario-01/` → `-02/` keeps
   006's numbering continuous, while the EKS `scenarios/scenario-02/` folder
   keeps its own. The paths never overlap; the new README says once which EKS
   folder it is not, and the makefile help lines read as its siblings.
3. **What the live run cannot prove** (named, not hidden): the quickstart
   runs two refusals live (unreachable cluster, and `STACK_MODE=eks` from a
   scratch repo copy; step 11); the unreadable-`.env`, missing-shop,
   missing-release and "not an AKS cluster" node-label refusals, and EC-006's
   genuine "cart failing on its own characteristics" case are checked by
   reading the script (status rows 2 and 4 are run live by hand in T004) — 006 named the
   same gap, and it costs the same single read-through in review.

## Project Structure

### Documentation (this feature)

```text
specs/007-aks-oom-kill/
├── spec.md              # approved specification (FR-011 clarified 2026-10-21)
├── plan.md              # this file
├── research.md          # Phase 0: live findings 1–6
├── data-model.md        # Phase 1: object, marker, truth table, waits, pre-checks
├── contracts/
│   └── commands.md      # Phase 1: targets, RESULT lines, exit codes, budgets
├── quickstart.md        # Phase 1: live validation run steps 1–14
├── tasks.md             # Phase 2: tasks T001–T014 and the deviations table
└── evidence/            # T010/T011: run output, screenshots, PR entries (as story 006)
```

### Source Code (repository root)

```text
infra/azure/scenario-02/                 # NEW folder (Azure numbering; NOT the EKS scenarios/scenario-02/)
├── cart-oom-kill.sh                     # NEW: start | status | revert (one script, 006 pattern)
└── README.md                            # NEW: the Azure cart-OOM guide (FR-012)

makefile                                 # ADD only: 3 targets after aks-ratings-abort-revert, 3 help lines after the 006 block (:24–35)
monitoring/dashboards/application.yaml   # EDIT only: new "Restarts" section (FR-011 as clarified)
scenarios/README.md                      # ADD only: one Azure line (sibling of the 006 line)
docs/aks-explained.md                    # EDIT: cart-OOM section, dictionary rows, stale "3 copies" line fixed (task T008)
infra/azure/chart-values/robot-shop.yaml # EDIT: shipping CPU, seeder CPU and fileTimeoutSeconds (D21, T015)
app/robot-shop/helm/templates/mysql-seeed-job.yaml  # EDIT: optional bounded-and-retried seed import (D21, T015); EKS render unchanged
.yamllint.yaml                           # EDIT: one ignore line removed for application.yaml (D17, the lint ratchet)
agent/policies/allowed-mcp-servers.md    # PROTECTED, one row added by the developer, commit 15fdc74 (D11)
```

| File | Change | Why | Spec |
|---|---|---|---|
| `infra/azure/scenario-02/cart-oom-kill.sh` | new | the one script behind all three commands; `data-model.md` §1–§5 and `contracts/commands.md` are its complete behavioural spec: pre-checks, marker, allowance change, waits, RESULT lines, exit codes | FR-001–FR-010, FR-013 |
| `infra/azure/scenario-02/README.md` | new | the guide: what must be running (shop pods Ready, loadgen), the three commands, what each RESULT line means, the restart counter resetting to 0 on revert, the growing back-off windows (EC-007), traffic requirements (EC-001), that re-deploying the shop clears the fault (EC-002), that a genuine cart failure at its own allowance is not this fault (EC-006), and that EKS `scenarios/scenario-01|02|04/` are the EKS way, not this (EC-009) | FR-012, EC-001, EC-002, EC-006, EC-007, EC-009 |
| `makefile` | add 3 targets + 3 help lines | the documented one-line commands; wording copied from `contracts/commands.md` §1 | FR-001–FR-003, FR-013, SC-008 |
| `monitoring/dashboards/application.yaml` | edit: one new section | the Restarts section proving FR-011 for every pod: a restarts-per-pod line (`increase(kube_pod_container_status_restarts_total[5m])` by namespace and pod), a stat counting pods whose last kill was `OOMKilled` and that restarted in the last 5 minutes, and a table naming them. All on the `prometheus` datasource. The 5-minute window is what makes the stat clear again, because `last_terminated_reason` stays 1 after a pod recovers (Finding 2, addendum). No memory-usage panel | FR-011, SC-004, SC-011 |
| `infra/azure/chart-values/robot-shop.yaml`, `mysql-seeed-job.yaml` | edit | shipping starved at 200m CPU (JVM `GC overhead limit exceeded`, 1/2 Ready, `helm --wait` timeout) and a seed import that stalled; permanent fix gated to Azure by values (D21). Not in the first plan | FR-014 (setup behaves as today when the fault was never started), FR-013 |
| `.yamllint.yaml` | edit: one line removed | the repo's lint ratchet requires a touched legacy file to leave the ignore list; the whole dashboard block of `application.yaml` is re-indented to make that possible (D17, review with `git diff -w`) | FR-013 (wording), SC-009 (exception recorded) |
| `docs/aks-explained.md` | edit | the Azure explainer page gains the cart-OOM scenario and the dictionary rows, and line 206 ("each runs as 3 copies") is corrected because every service runs one copy on this cluster; added at the developer's request, spec FR-012 widened to name it | FR-012 |
| `scenarios/README.md` | add one line | so someone browsing the scenarios README finds the Azure cart-OOM guide next to 006's line; unchanged lines stay (SC-009) | FR-012, SC-009 |

**Not changed**: anything under `scenarios/scenario-01/`, `scenario-02/`, `scenario-04/` (FR-013, SC-009); `.env` (no new setting — data-model §6); the shop's Helm chart including `cart-deployment.yaml` and `infra/azure/chart-values/robot-shop.yaml` (the allowance the shop is installed with is left exactly as shipped, which is what FR-008's revert reads); the monitoring chart values; every protected path.

**Structure Decision**: one Azure-only folder, `infra/azure/scenario-02/`,
holds the script and its guide, following `infra/azure/scenario-01/` (story
006) and `infra/azure/load-gen/`. Shared files only gain lines. The "02"
repeats a number the EKS `scenarios/scenario-02/` folder carries — deliberate,
developer's decision recorded in the Constitution Check; the two paths never
overlap.

## Verification Strategy

What the builder runs, when, and what goes into the PR as evidence
(`evidence:attached`). Mirrors `quickstart.md`'s run list; each row names the
finding behind it.

| # | Check | When | Proves | Evidence in PR |
|---|---|---|---|---|
| 1 | `make lint` | every commit | shell lint of the new script, YAML lint of the dashboard section and guidance, no protected path touched, Spec Kit and loom unchanged | full output |
| 2 | Live run of [quickstart.md](quickstart.md) steps 1–14 on the AKS cluster, shop pods `2/2 Ready`, loadgen running (Part A), refusals shown with `KUBECONFIG=/dev/null` and a scratch repo copy with `STACK_MODE=eks` (step 11; only `sre-stack-452138` is used), redeploy tolerance (step 12), the never-faulted window (step 13), owner passthrough (step 14) | once, after implementation | FR-001–FR-014 (FR-007's one exercised refusal: not-AKS cluster), SC-001–SC-009, SC-010, EC-001, EC-002, EC-004, EC-007, EC-009 | verbatim output of each step, `time` lines for SC-005, both `RESULT:` lines for run-twice checks |
| 3 | Grafana screenshots of the Restarts section: healthy baseline, fault on (cart in the table, stat 1) and after revert and the 5-minute window (stat 0, table empty) | during step 2, Part A | FR-011 as clarified, SC-003, SC-004 | `01-baseline.png`, `02-fault-on.png`, `03-after-revert.png` |
| 3b | The Restarts section with a pod other than cart restarting and being killed for running out of memory (throwaway pods `oom-proof` and `crash-proof` in a scratch namespace, deleted afterwards; done 2026-10-21 with the developer's approval, `04-other-pods.png`), and the three queries returning that pod | after T012 | FR-011 (every pod), SC-011 | a screenshot and the query output |
| 4 | `git diff --stat main -- scenarios/scenario-01 scenarios/scenario-02 scenarios/scenario-04` empty; `git diff main -- makefile .env scenarios/README.md monitoring/dashboards/application.yaml` adds lines only (none removed), except the whitespace re-indent of `application.yaml` forced by the yamllint ratchet (tasks.md D17, review with `git diff -w`); `git diff main -- docs/aks-explained.md` removes only the lines tasks T008 names | before opening the PR | FR-013, SC-009, SC-010 untouched | all outputs |
| 5 | The owner follows only `infra/azure/scenario-02/README.md` for one start → status → revert cycle (the SC-007 test, from a shop the story does not set up) | once, before review | SC-007, FR-012 | a one-line note in the PR |

**Not proven by running** (named in the PR, per the Constitution Check):
the refusals not run live (unreadable `.env`, missing cart Deployment, missing
Helm release, and the "not an AKS cluster" node-label check; the unreachable
cluster and `STACK_MODE=eks` refusals are run), and EC-006's genuine
"cart failing on its own" status suffix — checked by reading the script, the
same single read-through 006 named for review. **Known cluster conditions** that
can fail check 2 for reasons outside the story (research.md steps 189–190:
fresh-setup `shipping` stalls, the seeder job): quickstart prerequisite 1
catches both before the run begins. Quickstart step 12 (redeploy the shop while the fault is on) was run live on the third ask and found one gap, a failed Helm release, now fixed (tasks D20). Also not proven by running: step 14 (waived by the developer 2026-10-21, deviation D18) (the owner's walkthrough) is the developer's; extra check (a) is a comparison with the Helm release taken after the run, not a before/after diff.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

None — both Constitution Check rounds (pre-research and post-Phase-1) passed
with every principle at **Pass**.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
