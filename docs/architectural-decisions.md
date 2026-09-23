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

## AD-003 — Workload manifests need a toleration for Azure's spot auto-taint

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: T010 review
discussion (`specs/001-azure-aks-setup/tasks.md`, Phase 3; grounding in
`specs/001-azure-aks-setup/data-model.md` §3 and research.md fact 5).

### Decision

Any workload manifest that targets the four workload pools **when they run
in spot mode** (`AZURE_POOL_MODE=spot`, AD-002) must carry one extra
toleration for the taint Azure automatically adds to every spot node:

```yaml
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
```

AWS (eksctl) adds no such taint, so this is Azure-only glue: a spot pool on
Azure is UnSchedulable for pods without it, exactly like the designed
taints (`persistent=true:NoSchedule` etc.) already are. The verified
cluster keeps the taint; the verify script excludes this one taint from
its per-pool comparison and flags any other unexpected taint.

### Why

- The taint is Azure's own mechanic for reclaiming spot machines, not a
  cluster-design decision. Blocking creation of spot pools to dodge it
  (or un-tainting spot nodes, which Azure does not support) would give up
  the cost benefit AD-002 was built for.
- The data-model pools already run with NoSchedule taints and every
  workload manifest is written to tolerate those one-per-pool; adding one
  Azure-only toleration keeps that pattern ("taint + matching toleration")
  instead of a special case.

### What we gave up / consequences

- **Workload manifests stop being 100% provider-agnostic in spot mode.**
  A manifest without the toleration deploys fine on eks/local and on a
  *regular-mode* aks cluster, but cannot schedule on a *spot-mode* aks
  cluster. Cost-first mode therefore quietly requires this manifest
  change; no script can fix it for the workload.
- **On-demand-mode escape hatch documented**: today's subscription has
  3/26 spot vCPU, so the helper picks `regular`, no auto-taint exists, and
  manifests need nothing extra. The flip to spot (quota raised, new
  cluster shape version) is the moment every workload story must check
  this toleration — it is recorded in data-model §3 so the next stories
  inherit the requirement rather than rediscovering the failure as
  `Pending` pods on the nodes.

## AD-004 — Amazon non-regression is proven by diff and lint, not a live AWS run

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: story-owner
review of Phase 5 (`specs/001-azure-aks-setup/tasks.md`, T019).

### Decision

The Azure story's non-regression promise (`spec.md`, User Story 3) is proven
by two checks that need no cloud account:

1. The untouched-files guard (T017): the branch diff against its merge-base
   shows no change under `infra/eksctl.yaml`, the eks/local script paths,
   `app/`, `monitoring/`, `scenarios/`, or `infra/local/`, beyond the two
   documented dispatch edits in `setup-cluster.sh` and `cleanup-cluster.sh`.
2. `make lint` (T018) passing unchanged: hooks, secrets, protected paths,
   shell/YAML lint, Spec Kit version, loom drift.

The intended live confirmation — a person with Amazon access running
`make setup` and `make cleanup` with `STACK_MODE=eks` — is dropped because
no such person is available to this story.

### Why

- A live run nobody can perform is not evidence; it is a task that keeps the
  story open forever.
- The Azure work touches no Amazon/local behaviour except the two dispatch
  edits, and the diff guard checks exactly that, file by file.
- The lint gate, the pre-commit hooks, and CI already run on every change,
  so a silent regression would have to survive all of them first.

### What we gave up

- No live end-to-end proof from *this* branch that the Amazon path still
  creates and deletes. The exposure is small — the eks/local bodies are
  byte-identical and the dispatch change only routes `STACK_MODE` — but it
  is real. The next person who touches the eks path should run
  `make setup` and `make cleanup` once on a real account and report back.

## AD-005 — Host-based `VirtualService` routing, not per-app gateways or path rewriting

**Date**: 2026-09-23 · **Status**: Accepted · **Raised by**: architect
review of `specs/004-deploy-demo-apps-aks/spec.md` (added FR-011: Robot
Shop and HotROD must both be externally reachable and must not interfere
with each other).

### Decision

Robot Shop and HotROD share the one Istio ingress gateway
(`istio-ingressgateway` in `istio-system`) already installed for the
cluster. They are told apart by `VirtualService` host matching, not by
separate infrastructure:

- Robot Shop's existing `Gateway`/`VirtualService`
  (`app/robot-shop/Istio/gateway.yaml`) keeps `hosts: "*"` — reachable at
  the ingress IP directly, no header needed.
- HotROD gets a new `Gateway`/`VirtualService`
  (`app/hotrod/istio-gateway.yaml`), scoped to `hosts: "hotrod.demo.local"`
  — reachable only with a matching `Host` header
  (`curl -H "Host: hotrod.demo.local" http://<ingress-IP>/`).

Both bind the same `Gateway` selector (`istio: ingressgateway`), so no new
`LoadBalancer` Service or ingress class is created.

### Alternatives considered and rejected

1. **A second dedicated ingress gateway/LoadBalancer for HotROD.** Rejected:
   doubles the number of cloud LoadBalancer Services (and their cost) for a
   demo stack that has no scaling or isolation requirement between the two
   apps — nothing in spec.md's user stories asks for that separation.
2. **Path-prefix rewriting on one wildcard host** (e.g. `/hotrod` routed to
   HotROD, `/` to Robot Shop). Rejected: untested against HotROD's own
   frontend, which likely assumes it is served from root path `/` for its
   static asset links; rewriting risks breaking the UI in a way that would
   only surface after deploying, with no fallback if it did.
3. **Two wildcard `hosts: "*"` `VirtualService` entries on the same
   gateway.** Rejected outright, not just deprioritized: both would match
   every request with no way for Istio to disambiguate, so one app would
   silently swallow the other's traffic depending on config-apply order —
   verified live during this story's research (`research.md` §7) before
   settling on the host-scoped approach.

### Why this shape

- Host-based matching is a supported, first-class Istio routing mechanism
  purpose-built for exactly this — multiple backends behind one gateway —
  so it needs no new manifests beyond one more `Gateway`/`VirtualService`
  pair.
- No rewriting means no risk to HotROD's internal links; the app is served
  exactly as its own manifests expect.
- Verified live: `curl http://<ingress-IP>/` reaches Robot Shop and
  `curl -H "Host: hotrod.demo.local" http://<ingress-IP>/` reaches HotROD,
  both `200 OK`, with no observed interference either direction.

### What we gave up

- HotROD is only reachable with the `Host` header set (via `curl -H`,
  `/etc/hosts` entry, or a browser extension) since `hotrod.demo.local`
  resolves nowhere by default — there is no public DNS record for it. This
  is acceptable for an internal demo/POC stack; a real external hostname
  would need its own DNS entry, which is out of scope for this story.

