# Architectural Decisions

*Decisions made in this repository that others (and our future selves) will
need to read again. One entry per decision, newest at the bottom. Entries
span stories and specs — a decision made for one setup often applies to
every cluster target. Simple language on purpose; each entry answers: what
we chose, why, and what we gave up.*

## AD-001 — Keep the `gp2` storage-class alias on Azure

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: review of
`specs/001-azure-aks-setup/plan.md:38` (PR 98, comment thread on the gp2
storage setting)

### What was proposed

Drop the `gp2` StorageClass from the Azure setup, and split the application
helm charts so each cloud (AWS and Azure) carries its own copies. On Azure
the charts would then point straight at AKS's built-in disk classes (for
example `managed-csi`), so no alias with the AWS-style name would be needed.

### Why we didn't

Three reasons, in the order a reviewer should weigh them:

1. **Removing it breaks the workload contract, not just one file.** Every
   workload asks for a storage class named `gp2` — `app/robot-shop/helm/
   values.yaml` (mysql, redis), `templates/rabbitmq-deployment.yaml`, and
   `monitoring/grafana-postgres/statefulset.yaml`. No class of that name on
   an Azure cluster means every PVC lands `Pending` and the apps never come
   up. The alias is a 4-line manifest; the "removal" PR would have to touch
   charts, hardcoded templates, and the workload contract to get the same
   job done. Fewer files is not less work here.
2. **It drifts from this story's spec.** The accepted spec (US1) describes
   an *empty cluster* that mirrors Amazon's shape precisely so that the
   existing application and observability manifests deploy unchanged.
   Splitting the charts per cloud reopens the workload contract — a
   different work item, not a plan tweak inside a cluster-setup story.
3. **It breaks the constitution.** Principle V ("Workload Placement
   Contract") requires every new cluster target to reproduce the `gp2`
   storage-class alias so manifests deploy unchanged. Skipping it on Azure
   needs a constitution amendment approved in its own PR — with its own
   evidence — not a side effect of this story.

### The chart-split part

Separate charts per cloud remain a good idea, but this story has no
running AWS environment to regress against, so chart changes here cannot
prove "nothing on Amazon broke". That belongs to its own story: split the
charts, point Azure at AKS's built-in `managed-csi`, retire the `gp2` alias
target by target, and amend constitution V in the same PR.

### Keep-alive caveat for that future story

`app/robot-shop/helm/templates/rabbitmq-deployment.yaml:35` hardcodes
`storageClassName: gp2` and ignores its own values key. Any chart-split
story must fix that template — it is latent AWS drift already.

## AD-002 — Cost-first pool mode: prefer spot, fall back on-demand, refuse if neither fits

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: review of
`specs/001-azure-aks-setup/plan.md:64` (PR 98: "cost minimization as
guiding light", "use spot unless blocked").

### Decision

Before anything is created, the shared helper (`infra/scripts/cluster/
azure-common.sh`) reads the region's machine allowance (`az vm list-usage`)
and picks a deployment mode for the four workload pools:

1. **Spot preferred**: if the subscription's spot vCPU allowance in the
   chosen location fits the whole designed shape (26 spot vCPU at minimum
   counts — app 6, persistent 8, o11y 8, loadgen 4), all four workload
   pools are created as spot machines. All-or-nothing: no mixed pools.
2. **On-demand fallback**: if spot does not fit, the helper checks the
   regular vCPU allowances per machine family (DSv5 needs 22, FSv2 needs 4).
   If every family fits, the pools are created as regular machines.
3. **Refuse**: if neither fits, the start command stops before creating
   anything, and the message names the short allowance and how to fix it
   (raise the quota, free machines, or pick a different location). Nothing
   is half-created by a quota problem — that is the FR-005/FR-011 rule.

The system pool is always regular: Azure requires the first pool on a
cluster to be a non-spot system pool regardless of allowance.

### Why this shape

- Spot is the cheaper option whenever the region's spot allowance allows
  it, which answers the review's cost guidance without changing the
  designed cluster shape (sizes, counts, labels, taints stay in the
  data-model §3 table).
- All-or-nothing per mode keeps verification simple: the check report can
  state one mode and compare every pool against it.
- The fallback (not a hard error) keeps the cluster creation-able for
  people whose subscription has no spot room — a smaller bill was the
  goal, never a blocked deployment.
- The choice is made once, before creation, from a documented command
  shape — the same check-rather-than-guess pattern every other pre-check
  in the helper uses.
