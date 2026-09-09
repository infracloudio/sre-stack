# Research: Azure Cluster Support

*This file records what we decided about Azure and why. Everything below was
checked against Microsoft's official documentation (learn.microsoft.com), not
guessed from memory.*

## The questions we had to answer

1. Which one setting picks the cloud provider?
2. How do you create the cluster, its machine groups, and the "keep out"
   signs on them, using Azure's command-line tool?
3. How do you make the machines cheap ones Azure can take back (spot)?
4. How does the `gp2` storage setting work on Azure?
5. How do we know who is signed in, which bill to charge, and whether the
   chosen part of the world is real?
6. How do we name things so the same settings always make the same names?
7. Which Kubernetes version do we pin?
8. How do we delete everything at the end?
9. How do we check the finished cluster without changing anything?

## Decisions

### 1. Which setting picks the provider

**Decision**: `STACK_MODE` in `.env` gains a third allowed value: `aks`
(today it allows `eks` and `local`).

**Rationale**: `STACK_MODE` already means "which kind of cluster am I
building"; every script that needs to know already reads it. Adding a value
keeps one settings file for everything (constitution III) and changes nothing
for people using `eks` or `local`.

**Alternatives considered**: a separate `CLOUD_PROVIDER` variable — rejected:
two settings could disagree with each other (`STACK_MODE=eks` +
`CLOUD_PROVIDER=azure`), which is exactly the confusion one file is meant to
prevent.

### 2. Creating the cluster and its node pools

**Decision**: use `az aks create` for the cluster plus its first pool, then
`az aks nodepool add` for each of the other four pools. Node pool names keep
the Amazon names minus the `-ng` tail (AKS limits pool names to 12 lowercase
characters): `app`, `persistent`, `o11y`, `loadgen`.

**Grounding** (Microsoft Learn):
- `az aks nodepool add` supports `--name`, `--node-count`, `--node-vm-size`,
  `--labels`, `--node-taints`, `--min-count`, `--max-count`,
  `--enable-cluster-autoscaler`, `--mode` — everything the Amazon setup sets
  (learn.microsoft.com/cli/azure/aks/nodepool).
- Labels and taints apply to every machine in the pool
  (learn.microsoft.com/azure/aks/create-node-pools).
- The first pool made by `az aks create` is a system pool; later pools are
  user pools by default (learn.microsoft.com/azure/aks/use-system-pools).

**Rationale**: the CLI is the tool the story names; `az aks create` +
`nodepool add` is the documented path to multi-pool clusters.

**Alternatives considered**: Terraform/Bicep/ARM — rejected: this repo is
bash glue; introducing an infrastructure tool would break the pattern of
every other script. Azure portal — rejected: not repeatable.

### 3. Cheap, take-back-able machines (spot) — deferred

**Decision** (updated 2026-09-09 by the story owner): the four workload pools
start as **regular** on-demand pools — `az aks nodepool add --node-count <n>
--node-vm-size <size> --labels ... --node-taints ... --enable-cluster-autoscaler
--min-count <min> --max-count <max>` with no spot flags. One small **regular**
system pool (Standard_D2s_v5, 1 machine) is created first, because Azure
requires a non-spot system pool.

**Why spot was deferred**: the subscription's regional spot vCPU quota
(`lowPriorityCores`) is 3 vCPU, and the designed shape needs 26 spot vCPU at
minimum counts (see "Manual pass findings" below) — every spot pool add fails
with `ErrCode_InsufficientVCPUQuota` until the quota is raised. Clusters here
are short-lived, so the flip later costs almost nothing: change the `Spot?`
column in data-model.md §3 back to `yes`, bump `CLUSTER_SHAPE_VERSION` (fresh
names, fresh cluster), rerun, and add one toleration per workload manifest for
the Azure-only auto-taint `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`.

**The spot recipe, kept for the flip** (proven in the manual try-out):
`--priority Spot --eviction-policy Delete --spot-max-price -1`, with
`--enable-cluster-autoscaler` and the min/max counts from the Amazon setup.
Grounding: learn.microsoft.com/azure/aks/spot-node-pool — "A Spot node pool
can't be a default node pool, it can only be used as a secondary pool";
`-1` for max price means "never evict on price, only on capacity"; and
"You can't change `ScaleSetPriority` or `SpotMaxPrice` after creation", which
is why the flip means new pools/a new cluster rather than an in-place change.

**Alternatives considered**: making `app` the system pool to avoid the extra
pool — rejected: the app pool must stay malleable and spot pools can't be the
first pool. No system pool at all — not possible: AKS requires at least one
system pool. Waiting for the quota before writing any script — rejected: the
scripts are table-driven either way, so blocking the story on a subscription
setting buys nothing.

### 4. The gp2 storage setting

**Decision**: ship `infra/azure/gp2-storageclass.yaml`, a StorageClass named
`gp2` with provisioner `disk.csi.azure.com` (Azure's disk driver), standard
SSD storage, `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy:
Delete`, `allowVolumeExpansion: true`, applied by `kubectl` after the cluster
is ready.

**Grounding**: learn.microsoft.com/azure/aks/create-volume-azure-disk shows
custom StorageClasses with this provisioner; learn.microsoft.com/azure/architecture/aws-professional/eks-to-aks/storage
confirms AKS only reconciles its own built-in class names, so a class named
`gp2` stays ours; this is the same pattern as `infra/local/gp2-storageclass.yaml`.

**Rationale**: every workload in this repo asks for storage class `gp2`
(constitution V). Giving the name the same meaning on Azure keeps the app
files untouched.

**Alternatives considered**: ask users to rewrite manifests to `managed-csi`
— rejected: the manifests are the product; providers must stay swappable.

### 5. Sign-in, subscription, location checks

**Decision**: before doing anything, the shared helper runs, in order:
1. `az account show` — fails if not signed in → stop with a plain message.
2. `az account set --subscription $AZURE_SUBSCRIPTION_ID` (when set) — fails
   if the subscription is unknown → stop.
3. `az account list-locations` — fail if `AZURE_LOCATION` (or the fallback)
   is not a real location for this account → stop.
4. `az vm list-skus --location <location> --all` — fail if any machine size
   from the pool table is not offered in that location → stop, naming the
   first missing size.

**Grounding**: learn.microsoft.com/cli/azure/account (az account show,
az account set), learn.microsoft.com/cli/azure/group (locations come from
`az account list-locations`), learn.microsoft.com/azure/azure-resource-manager/troubleshooting/error-sku-not-available
(`az vm list-skus --location ... --all` is the documented way to see which
sizes a region offers, including sizes blocked for your subscription),
learn.microsoft.com/azure/aks/aks-virtual-machine-sizes.

**Fallback rule**: the fallback location is `eastus2`, and it applies **only
when `AZURE_LOCATION` is empty** (FR-010). Once a location is chosen — by the
user or by fallback — the machine-size check runs against it; a failed check
stops the run with an error and never silently moves the cluster elsewhere.

**Rationale**: the spec (FR-005) demands clear refusals before anything is
created, and an unusable location includes one that lacks the machine sizes.
Checks-first is also constitution I.

**Alternatives considered**: let `az` fail mid-way with its own error —
rejected: messages arrive after partial creation and are not plain-language.

### 6. Names that repeat themselves

**Decision**:
- resource group: `<name>-aks-<code>`; cluster: `sre-stack-<code>`
- `<name>` = signed-in user from `az account show --query user.name`
  (fallback: `$USER`), lowercased, stripped of characters Azure disallows.
- `<code>` = first 6 characters of a hash (SHA-256) of
  `subscription-id + location + cluster-shape-version`.
- Recorded in a script-local lookup, and discoverable again because the same
  inputs always rebuild the same code.

**Rationale**: FR-009 requires name-from-user + suffix-from-settings, and
FR-003 requires reruns to find what exists. A settings-derived hash is
deterministic: same settings → same names → rerun is a no-op.

**Alternatives considered**: random suffix — rejected: a second run would
build a second cluster. Suffix from `$RANDOM`-style values — same flaw.
Name in `.env` — rejected: spec clarification says names are generated, and
two developers sharing settings would collide.

### 7. Kubernetes version

**Decision**: pin `AKS_KUBERNETES_VERSION` in `.env`. The concrete number is
filled in during the **manual try-out** by asking
`az aks get-versions --location <location>` which versions are supported
today. The Amazon pin (1.27) is past end-of-life and cannot be requested.

**Rationale**: constitution II requires explicit pins; the manual pass is the
grounded way to pick a supported one.

### 8. Deleting everything

**Decision**: `az group delete --name <resource-group> --yes` once the
group exists check passes; delete the group only if its name matches the
generated pattern (so we never delete someone else's folder). Nothing else
needs deleting because everything lives in the group — **including the
second, automatic group Azure creates**.

**The second group, checked** (Microsoft Learn): every AKS cluster spans two
resource groups. Ours holds the cluster; Azure's resource provider quietly
creates a second one, the *node resource group*, named
`MC_<resourcegroup>_<cluster>_<location>`. It holds the actual virtual
machine scale sets, the VMs, disks, virtual network, and storage
(learn.microsoft.com/azure/aks/faq#why-are-two-resource-groups-created-with-aks-).
Deleting the main group deletes the cluster resource, and AKS then deletes
the node resource group by itself:
- learn.microsoft.com/azure/aks/delete-cluster — "When you delete a cluster…
  The node resource group and its resources, including the virtual machine
  scale sets and VMs, the virtual network and its subnets, and the storage."
- learn.microsoft.com/azure/aks/use-system-pools ("Clean up resources") —
  "When you delete the AKS cluster's resource group, all the cluster
  resources and the related node resource group (MC_) are deleted."

So one `az group delete` cascades to everything. As a belt-and-braces check
(per the story owner's request), the cleanup script afterwards checks for the
node resource group **by its one exact predicted name** —
`MC_<our-generated-rg>_<our-generated-cluster>_<location>` — and, if that
exact group still exists (e.g. an in-flight delete), prints a plain warning
naming it and the exact removal command. It never deletes an `MC_` group
blindly, since modifying resources under an AKS-managed node group is
unsupported while the cluster lives.

**Shared-subscription rule**: the subscription may be used by several people,
each with their own AKS clusters and their own `MC_` groups. The script must
therefore never search by the `MC_` prefix (`az group list | grep MC_`) —
that would surface, and risk confusing into action, other people's groups.
Only the exact name built from our own generated names is ever checked.

**Grounding**: learn.microsoft.com/cli/azure/group (az group delete; the
group is a container whose contents go with it).

**Rationale**: FR-004 demands "nothing left behind"; group deletion is the
documented all-at-once removal, and the MC_ follow-up check turns documented
behaviour into observed evidence. The name-pattern guard stops the script
from deleting an unrelated group it didn't create.

### 9. Read-only verification

**Decision**: `verify-cluster-aks.sh` runs only read commands —
`az aks show` (is the control plane ready?) and
`az aks nodepool list` (count, machine size, labels, taints, spot) — and
compares each pool against the table in plan.md, printing a plain-language
✓/✗ line per pool. It never calls create, update, or delete.

**Grounding**: learn.microsoft.com/azure/aks/use-system-pools and
learn.microsoft.com/azure/aks/spot-node-pool both use `az aks nodepool show`
/ `list` output (`count`, `vmSize`, `nodeLabels`, `nodeTaints`,
`scaleSetPriority`, `provisioningState`) as the verification fields.

### 10. Testing without a cloud

**Decision**: the offline test puts a pretend `az` first on PATH. It appends
every call to a log file and returns fixed answers (JSON shaped like the real
`az` output). The tests then assert: what was called, that a second run calls
nothing new, that refusal messages appear for the four bad-input cases, and
that the partial-failure report names what was already created. Contract in
[contracts/azure-cli-contract.md](./contracts/azure-cli-contract.md).

**Rationale**: FR-013. The stand-in keeps the checks honest without an
account or cost.

## Manual pass findings

> Filled in during the manual try-out (2026-09-09, eastus2, subscription
> `Pune - Sandbox (TPM)` — `674579f0-b52a-4352-9913-f81135cc01e0`, Azure CLI
> 2.90.0) before any script was written. Raw command outputs from the session
> were recorded and the numbers below are transcribed from them.

- [x] Sign-in check works (`az account show`)
      — user `rijo.john@improving.com`
- [x] Subscription set works (`az account set --subscription`)
      — `674579f0-b52a-4352-9913-f81135cc01e0` "Pune - Sandbox (TPM)"
- [x] Location list shows the chosen location
      — `eastus2` exact match (109 locations; Azure has no `eastus-2`)
- [x] Machine sizes offered in the chosen location confirmed
      (`az vm list-skus --location <loc> --all` — need Standard_D2s_v5,
      Standard_D4s_v5, Standard_F4s_v2)
      — all three offered in eastus2 with **zero restrictions**
- [x] `az group create` / `az group delete` shapes confirmed
      — create/show return `properties.provisioningState: "Succeeded"`;
        delete exits 0; the rehearsal group was gone immediately after
- [x] Exact auto-created node resource group name recorded and matched
      against the prediction `MC_<rg>_<cluster>_<location>` while the
      cluster exists
      — created exactly `MC_rijo-aks-manual_sre-stack-manual_eastus2`;
        also returned by `az aks show` as the `nodeResourceGroup` field
- [x] After `az group delete`, OUR `MC_` group observed gone (checked by its
      exact name only — no prefix searches)
      — main group took ~6 minutes to disappear with the cluster inside;
        the exact-name `MC_` check then said "gone"; zero leftover groups
- [x] Supported Kubernetes versions recorded (from `az aks get-versions`)
      — eastus2 offers 1.31–1.36; CLI default 1.34; **pinned 1.34**
- [x] VM sizes confirmed available in the chosen region
- [x] `az aks create` + `az aks nodepool add` with labels/taints/spot confirmed
      — with two deviations; see "Observed facts" below
- [x] `az aks show` / `az aks nodepool list` output fields confirmed
      — shapes recorded below (they feed the offline stand-in)
- [x] gp2 StorageClass apply + a test PVC bound (optional but recommended)
      — SC applied with the data-model §4 shape; a 1Gi PVC with a busybox
        pod (nodeSelector `workload=persistent`, tolerating both taints)
        went `Bound` and `Running` on the spot node; test resources deleted
- [x] Clean deletion leaves nothing behind (checked in the Azure portal)
      — story owner confirmed the group in the portal while it existed;
        after deletion both groups absent

### Observed facts (manual try-out, eastus2, 2026-09-09)

**Command-shape corrections** (differ from quickstart Part A as written):

1. `az aks create` has **no `--mode` parameter** (unrecognized argument on
   CLI 2.90.0; confirmed against learn.microsoft.com/azure/aks/use-system-pools:
   "the initial node pool defaults to a mode of type `System`"). The quickstart
   A5 `--mode System` must be dropped, and the later setup script must not
   pass it. The initial pool came out as `mode: System`, `spot: null`.
2. Azure names the initial system pool itself: it came out as **`nodepool1`**,
   not `system`. Any verify logic that expects a pool literally named
   `system` must instead match the pool whose `mode` is `System`.

**Spot quota wall (needs a subscription-level fix before full-shape runs)**:

3. The regional **spot vCPU quota** (`az vm list-usage --location eastus2`,
   quota name `lowPriorityCores`, "Total Regional Low-priority vCPUs") is
   **limit 3, used 0** in eastus2 — and the same 3/0 was observed in eastus,
   centralindia, and southcentralus. Spot vCPU quota is enforced per
   subscription per region across all VM families
   (learn.microsoft.com/azure/quotas/spot-quota); it has nothing to do with
   clusters, and AKS spot pools draw from the same bucket. `az aks nodepool
   add` for the data-model §3 `persistent` pool (2× Standard_D4s_v5 = 8 spot
   vCPU) failed with `ErrCode_InsufficientVCPUQuota … left regional spot
   vcpu quota 3, requested quota 8`. The full §3 table needs 26 spot vCPU
   at min counts, so the full shape is impossible until the owner raises
   "Total Spot vCPUs" via Portal → Quotas → Compute → search "spot"
   (recommended ≥32; eastus2 and every region used). Standard (non-spot)
   quota is not the problem: `cores` 2/50, `standardDSv5Family` 2/50.
4. Because of (3), the try-out proved the spot/label/taint/autoscaler shape
   with a reduced pool: `persistent` = 1× Standard_D2s_v5, autoscaler 1–1.
   Everything else about the pool matched §3 (label, both taints, spot
   priority, eviction policy, max price −1, `mode: User`).

**Azure-only behaviours the scripts must account for**:

5. AKS **auto-adds** `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`
   to every spot pool, on top of the requested taint (AWS/eksctl adds no
   such taint). Pods landing on spot pools must tolerate it.
6. Spot pool creation is slow and the cluster reads
   `provisioningState: "Updating"` for a few minutes after `nodepool add`
   returns, then settles to `Succeeded` — verify logic must tolerate
   `Updating` right after a change.

**Real output shapes (A7), for the offline stand-in**:

`az aks show` (queried fields):
```json
{"state": "Succeeded", "power": "Running"}
```
Full `az aks create` output carried: `provisioningState`, `powerState.code`,
`kubernetesVersion`, `fqdn`, `nodeResourceGroup`, and `agentPoolProfiles[]`
with `name`, `count`, `vmSize`, `mode`, `scaleSetPriority`.

`az aks nodepool list` (queried fields) — verbatim:
```json
[
  {
    "count": 1,
    "labels": null,
    "name": "nodepool1",
    "size": "Standard_D2s_v5",
    "spot": null,
    "taints": null
  },
  {
    "count": 1,
    "labels": {
      "kubernetes.azure.com/scalesetpriority": "spot",
      "workload": "persistent"
    },
    "name": "persistent",
    "size": "Standard_D2s_v5",
    "spot": "Spot",
    "taints": [
      "persistent=true:NoSchedule",
      "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
    ]
  }
]
```

**Timing observed**: `az aks create` ~10 min; `az aks nodepool add` ~4 min
(+ a few minutes of cluster `Updating`); `az group delete` with a live
cluster inside ~6 min; resource-group create/delete rehearsal: seconds.

**Story-owner decision (2026-09-09), recorded after the try-out**: workload
pools start **regular** (spot deferred) because of the spot quota wall in
fact 3. Consequences: the setup script must not pass the spot flags; the
verify script must expect `scaleSetPriority: null` (or `Regular`) for all
five pools; the offline stand-in answers with the regular-pool shapes above
(the `nodepool1` entry shows the regular shape). The flip back to spot is
specified in data-model.md §3 and research.md §3.

### Full-shape redeploy (manual, eastus2, 2026-09-09)

End-to-end rehearsal of the data-model §3 shape with **all pools regular**,
run by hand (no scripts exist yet) after the story-owner's decision, before
`azure-common.sh` was written. Names from quickstart Part A:
`rijo-aks-manual` / `sre-stack-manual`.

- Pre-checks live: CLI 2.90.0; regional vCPU 0/50, DSv5 0/50, FSv2 0/50
  (full shape needs 28 vCPU at min counts); all three sizes unrestricted.
- `az group create` → `provisioningState: Succeeded`.
- `az aks create` (no `--mode`, k8s 1.34, 1×Standard_D2s_v5) → `Succeeded` /
  `Running`; initial pool `nodepool1`, `mode: System`, `spot: null` —
  consistent with findings 1–2 above.
- Four `az aks nodepool add` (app 3×D2s_v5 3–6, persistent 2×D4s_v5 2–2,
  o11y 2×D4s_v5 2–3, loadgen 1×F4s_v2 1–1, labels/taints/autoscaler per §3,
  **no spot flags**) → each `Succeeded`; `az aks nodepool list` read-back
  matched the §3 table field for field, `scaleSetPriority: null` on all five.
- `kubectl get nodes`: 9/9 `Ready`, v1.34.10 (1+3+2+2+1).
- gp2 StorageClass applied from a temporary manifest with the data-model §4
  fields (`disk.csi.azure.com`, `StandardSSD_LRS`, `WaitForFirstConsumer`,
  `Delete`, expansion `true`) → applied; namespaces stayed kube-default only
  (FR-008).
- `nodeResourceGroup` returned by `az aks show` and the live group name both
  equalled the prediction `MC_rijo-aks-manual_sre-stack-manual_eastus2`
  exactly (finding: §2 MC_ naming prediction holds for the full shape).
- Teardown ran on the story owner's explicit go (irreversible):
  `az group delete --name rijo-aks-manual --yes --no-wait`; the main group
  took ~7 minutes to disappear with the full-shape cluster inside, the
  exact-name `MC_` check then said "gone", and no `rijo*` group was left
  (delete cascades per §8).
- Note: `az aks get-credentials --overwrite-existing` set context
  `sre-stack-manual` as current in the developer's kubeconfig; other
  contexts were untouched.

## Source list (Microsoft Learn)

- `learn.microsoft.com/cli/azure/aks/nodepool` — nodepool add parameters
- `learn.microsoft.com/azure/aks/create-node-pools` — labels/taints per pool
- `learn.microsoft.com/azure/aks/use-system-pools` — system vs user pools
- `learn.microsoft.com/azure/aks/spot-node-pool` — spot rules and limits
- `learn.microsoft.com/azure/aks/create-volume-azure-disk` — custom StorageClass
- `learn.microsoft.com/azure/architecture/aws-professional/eks-to-aks/storage` — class reconciliation
- `learn.microsoft.com/cli/azure/account` — sign-in and subscription commands
- `learn.microsoft.com/cli/azure/group` — group create/delete, locations
- `learn.microsoft.com/azure/aks/faq#why-are-two-resource-groups-created-with-aks-` — the two groups, MC_ naming, auto-delete
- `learn.microsoft.com/azure/aks/delete-cluster` — what cluster deletion removes
- `learn.microsoft.com/azure/azure-resource-manager/troubleshooting/error-sku-not-available` — `az vm list-skus` availability check
- `learn.microsoft.com/azure/aks/aks-virtual-machine-sizes` — why sizes are missing; system-pool minimums (no B-series)
