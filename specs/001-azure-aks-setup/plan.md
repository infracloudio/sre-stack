# Implementation Plan: Azure Cluster Support

**Branch**: `001-azure-aks-setup` | **Date**: 2026-09-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-azure-aks-setup/spec.md`

## Summary (in everyday words)

Today this project can build its empty practice cluster on Amazon ("eks")
or on your own laptop ("local"). We are teaching it a third place: Microsoft
Azure ("aks"). You flip one line in the settings file, sign in to Azure once,
and run the same start command as always. You get the same empty cluster —
same groups of machines, same names, same sizes, same special markings —
but living on Azure instead of Amazon. When you're done, the same cleanup
command takes it all away, so nothing keeps costing money.

**Important rule from the story owner**: before we write any script, a person
must first run the Azure commands **by hand, one at a time**, to prove they
work, and write down what they learned. Only then do we turn those proven
commands into scripts. The first task is that manual try-out.

## How it works (the simple picture)

```text
you edit .env:  STACK_MODE=aks        ← "please use Azure, not Amazon"
                AZURE_SUBSCRIPTION_ID ← "which Azure bill to charge"
                AZURE_LOCATION        ← "which part of the world"

you run:        az login              ← sign in to Azure (no passwords stored here)
                make setup            ← same command as always

what happens:   1. a "resource group" (a folder that holds everything,
                   so it can all be deleted at once) is created
                2. an AKS cluster (Azure's version of a Kubernetes cluster)
                   is created inside it
                3. four node pools (groups of machines) are created,
                   matching the Amazon ones machine-for-machine
                4. a "gp2" storage setting is added so the apps find
                   storage the same way as on Amazon

when done:      make cleanup-cluster  ← deletes the folder and everything in it;
                                         Azure also keeps a second, automatic
                                         folder (the "node resource group",
                                         named MC_...) holding the actual
                                         machines and disks — deleting the
                                         cluster removes that one too, and the
                                         cleanup script double-checks it's gone
```

## Technical Context

**Language/Version**: Bash (same language every other script here uses) calling the Azure command-line tool (`az`) and `kubectl`. No new language.

**Primary Dependencies**: Azure CLI 2.87.0 or newer (the minimum the Azure docs ask for), `kubectl` (already used here), `make` (already used here).

**Storage**: nothing new on the cloud. Inside the cluster we add a storage setting named `gp2` that points at Azure's disk system, the same trick the laptop setup already uses in `infra/local/gp2-storageclass.yaml`.

**Testing**: we test the scripts **without any cloud**: a pretend `az` command is put on the PATH. It writes down what it was asked to do and always answers the same fixed way. We then check the recorded answers. A real run is done once, by hand, by the story owner.

**Target Platform**: Azure AKS in the user's own Azure subscription; scripts run on the developer's own computer.

**Project Type**: a scripts-and-settings project — the deliverables are scripts, one settings file, and one small manifest. There is no application code.

**Performance Goals**: none — these are setup and teardown scripts.

**Constraints**:
- No passwords or keys are stored anywhere; Azure's own sign-in is used.
- The same settings must always create the same names (so a rerun finds what already exists instead of making a second copy).
- If a run stops halfway (bad network, no quota, missing permission), the script stops, says in plain words what was made so far, and deletes nothing on its own.
- Amazon and laptop behaviour must not change at all.

**Scale/Scope**: one cluster, four working node pools plus one small housekeeping pool, one resource group. Two new scripts, one shared helper, and small edits to three existing files.

## The node pools, one by one

Azure machines have different names from Amazon machines, so each Amazon
machine type gets its closest Azure match:

| What it's for | Amazon machine | Azure machine (closest match) | how many | label written on it | special marking (taint) |
|---|---|---|---|---|---|
| running the app | c6a.large (2 CPU / 4 GB) | Standard_D2s_v5 | 3–6 (can grow) | `workload=app` | none |
| holding data | t3.xlarge (4 / 16) | Standard_D4s_v5 | 2, never more | `workload=persistent` | `persistent=true:NoSchedule` |
| monitoring | t3.xlarge (4 / 16) | Standard_D4s_v5 | 2–3 | `workload=o11y` | `o11y=true:NoSchedule` |
| fake traffic | c5.xlarge (4 / 8) | Standard_F4s_v2 | 1, never more | `workload=loadgen` | `loadgen=true:NoSchedule` |

A **taint** is a "keep out" sign: pods that don't say they tolerate the sign
are not placed on that machine. The label is how pods find the right machines.
These are exactly the same labels and taints the Amazon cluster uses today.

Extra facts:
- **Cost first: spot preferred, checked above, not guessed.** The Amazon
  setup runs all four workload node groups on **spot** machines, and the
  Azure script prefers that too — but only because a measured check allows
  it (FR-014). One extra pre-check in the shared helper
  (`az vm list-usage --location <loc>`) decides the mode, before anything
  is created: if the subscription's spot vCPU allowance fits the whole
  shape (26 spot vCPU at minimum counts), the four pools are created as
  spot; else, when the regular allowances fit for every machine family at
  those same minimums (DSv5 needs 22, FSv2 needs 4), they are created as
  **regular**; else the script stops with a plain message naming the short
  allowance — nothing is half-created. The allowance is judged against
  minimum counts only; pools that can grow automatically are capped by the
  allowance rather than dodging it. The choice is all-or-nothing (no mixed
  pools), the
  system pool is always regular (Azure requires a non-spot first pool),
  and the spot command flags stay in research.md §3 so the helper and the
  contract can be re-synced in the same commit (AD-002).
- Before creating anything, the shared helper also checks that **every
  machine size in the table is actually offered in the chosen part of the
  world** (`az vm list-skus --location <loc> --all`). Azure regions differ;
  if one size is missing, the script stops with a plain message naming the
  missing size — it does not silently swap anything.
- The Azure version of Kubernetes is pinned in `.env`. The exact number is
  confirmed during the manual try-out (the Amazon pin, 1.27, is too old to
  request on Azure today).

## Names: how the cluster and folder get their names

Both names are made automatically, and the recipe is:

```text
resource group  =  <your-name>-aks-<short-code>
cluster name    =  sre-stack-<short-code>
```

- `<your-name>` comes from the Azure account you're signed in with
  (`az account show` tells us who you are). Never asked, never configured.
- `<short-code>` is a short fingerprint made from the subscription and
  location in the settings file. Same settings → same fingerprint → same
  names → a rerun finds the existing cluster and changes nothing.
- The Azure part of the world comes from `AZURE_LOCATION`; if you leave it
  empty, the documented fallback `eastus2` is used — **only** in that case.
  If you set a location yourself and its machines aren't offered there, the
  script stops with an error instead of moving elsewhere on its own.

## Constitution Check

*(The constitution is this repo's rulebook. Each row: does the plan obey the rule?)*

| Rule | Verdict | Why |
|---|---|---|
| I. Scripts can be run twice safely | Pass | Scripts read `.env`, check before they create or delete. Cleanup deletes only the generated folder. Half-finished runs are left alone, as the spec demands. |
| II. Pinned versions | Pass | Azure Kubernetes version, machine sizes, and the fallback location are pinned in `.env`. No Helm charts are installed in this story. |
| III. One settings file | Pass | All new settings live in `.env`. Names are generated, not configured — the spec says so. |
| IV. No secrets in git | Pass | Nothing secret is stored; the scripts use your existing Azure sign-in. |
| V. Same labels, taints, and storage on every cluster | Pass | The table above reproduces them exactly, plus the `gp2` storage setting, so the app files deploy unchanged. |
| VI. Spec stays non-technical | Pass | The spec talks only about behaviour and outcomes. |
| VII. Plain language everywhere | Pass | This plan, the research, and the quickstart are written for someone new to the project, with examples. (Constitution 1.2.0 added two more principles on 2026-09-10; they were checked below after this table was first written.) |
| VIII. Try it before you plan it | Pass | Phase 0 ran every original command by hand (T002, research.md). The one command the try-out did not cover — `az vm list-usage` for the allowance check (FR-014) — has a task (T023) that requires running it once by hand, together with the story owner, before any helper edit. |
| IX. Plan in steps, with the user in the room | Pass | This plan was first written before IX existed, so the original plan cannot retroactively claim it. Everything added after 1.2.0 (FR-014 / allowance check, T023, the AD document) was written in step-by-step review with the story owner (PR 98 comment threads), and the reviewer saw each piece before it landed. The formal signature for this row is the reviewer's fresh `gate:plan-approved` on that approval. |

No rule is broken, so no exception table is needed.

**Re-check after design was done**: still passes; nothing new was added that
touches a rule.

## Project Structure

### Documents this feature produces

```text
specs/001-azure-aks-setup/
├── plan.md              # this file
├── research.md          # what we learned about Azure, with sources
├── data-model.md        # every setting, name, and node pool on paper
├── quickstart.md        # the step-by-step try-out and check guide
├── ../../docs/architectural-decisions.md  # shared doc: the "why we chose
│                                         #   this" record (AD-001…), kept
│                                         #   outside specs/ because decisions
│                                         #   span stories
└── contracts/
    └── azure-cli-contract.md   # exactly which az commands we rely on,
                                # and what the pretend-az must imitate
```

### Files in the repository that this feature touches

```text
.env                                # EDIT: add the Azure settings (tracked file, demo values only)
makefile                            # EDIT: setup/cleanup look at STACK_MODE and pick the right script
infra/
├── azure/
│   └── gp2-storageclass.yaml       # NEW: the gp2 storage setting for Azure disks
└── scripts/cluster/
    ├── azure-common.sh             # NEW: shared helper — are you signed in? is the
    │                               #   subscription real? is the location real? are all
    │                               #   four machine sizes offered there? make the names
    ├── setup-cluster-aks.sh        # NEW: create folder + cluster + node pools + storage setting
    ├── verify-cluster-aks.sh       # NEW: look-only check that the cluster matches the table
    ├── setup-cluster.sh            # EDIT: hand over to the aks script when STACK_MODE=aks
    └── cleanup-cluster.sh          # EDIT: hand over to "delete the folder" when STACK_MODE=aks
```

**Structure Decision**: we follow the existing layout — cluster scripts live
in `infra/scripts/cluster/`, manifests in `infra/`, settings in `.env`. We do
not touch anything under `app/`, `monitoring/`, `scenarios/`, or any eks/local
file, because Amazon and laptop behaviour must stay exactly as it is.

## How the work will be ordered (for the tasks list)

1. **First: the manual try-out.** Run every Azure command by hand, one at a
   time (sign-in check → make folder → make cluster → add each node pool →
   apply the storage setting → look at the result → delete the folder), using
   the guide in quickstart.md. Write the real results — which commands
   worked, which Kubernetes versions Azure actually offers today, which
   machine sizes are actually available in your region — into research.md,
   in its "Manual pass findings" section.
2. **Then: write the scripts**, copying exactly the command shapes that the
   manual try-out proved.
3. Then the pretend-`az` offline tests, then the final check steps.

The tasks list must encode this order; it is a requirement of the story, not
a suggestion.

## Plan Departures (recorded during implementation)

- **T014 — cleanup sources the helper in a new cleanup mode.** Running the
  create-time pre-checks during teardown would let a changed quota, a
  vanished machine size, or a changed role block the command that stops the
  bill. `cleanup-cluster.sh` therefore sets `AZURE_CLEANUP=1`; the helper
  keeps sign-in and the generated names and skips the create-time probes,
  saying "Nothing was deleted" in refusals. One extra file beyond the task's
  list: the `makefile` `cleanup-cluster` target — its
  `destroy-cluster-autoscaler` / `destroy-yace` prerequisites are Amazon-only,
  so they are skipped when `STACK_MODE=aks` and kept unchanged otherwise.
- **T015 — `bad-provider` offline scenario dropped (story-owner decision,
  2026-09-10).** The refusal stays in the setup and cleanup dispatch scripts
  and in quickstart B1 (manual); contract §2 no longer lists the offline
  scenario.
- **T019 — live Amazon confirmation dropped (story-owner decision,
  2026-09-10).** No person with AWS access is available to this story;
  non-regression is proven by the T017 diff survey plus T018's unchanged
  `make lint` (AD-004).
- **T025 — offline tests added to CI (story-owner request, 2026-09-10).**
  A new `.github/workflows/ci.yml` job runs
  `bash agent/tests/azure/run-offline-tests.sh` on every pull request
  (~80 s, no cloud). Workflows are a protected path, so a human applies the
  job change with `PROTECTED_OVERRIDE=1`.
- **T005/T023 — size pre-check reads the Resource Skus REST API, and the
  create-time probes run in parallel (2026-09-10 speed pass).**
  `az vm list-skus` downloads every resource type and filters client-side —
  90 s+ per run even with exact filters (azure-cli issues #31592/#30389).
  The helper calls the same API directly instead (`az rest` +
  `Microsoft.Compute/skus`, api-version 2021-07-01), where the location
  filter is server-side, and keeps the documented `--all` semantics (size
  names matched regardless of `restrictions`); contract §1 records the
  shape and the reason the old `az vm list-skus` wording was replaced.
  In the same pass the four independent read-only pre-check probes
  (permission, location, sizes, allowance) run in parallel — wall time
  only: same answers, same refusals, same order of evaluation.
- **T027 — permission pre-check uses Azure's inherited listing instead of
  matching management-group scope strings.** The T024 check accepted any
  `…/managementGroups/*` scope without proving the management group
  contains the subscription. The `az role assignment list` call now carries
  `--include-inherited`, so Azure itself returns only assignments effective
  at the current subscription (its scope, root, and its real parent
  management groups); an unrelated management group never appears. Covered
  offline by the `rbac-mg-ancestor` / `rbac-mg-unrelated` scenarios
  (contract §1/§2).

## Complexity Tracking

> Fill ONLY if a constitution rule is broken and needs an excuse

Nothing to write — no rule is broken.
