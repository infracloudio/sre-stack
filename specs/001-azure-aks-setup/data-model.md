# Data Model: Azure Cluster Support

*Every setting, name, and pool this feature creates or reads, written down in
one place. Simple language; nothing here is a surprise to the scripts.*

## 1. Settings (all in `.env`)

| Setting | Values | Meaning |
|---|---|---|
| `STACK_MODE` | `eks` \| `local` \| **`aks`** (new) | Which cloud the start/cleanup commands act on. Existing values unchanged. |
| `AZURE_SUBSCRIPTION_ID` | an Azure subscription id, or empty | Which Azure bill to charge. Empty = whatever the user's sign-in already points at (still checked). |
| `AZURE_LOCATION` | e.g. `westus2`, or empty | Which part of the world the cluster lives in. Empty = documented fallback `eastus2`. The fallback applies **only** when the setting is empty. |
| `AKS_KUBERNETES_VERSION` | e.g. `1.30.x` (pinned) | The exact Kubernetes version to build. Confirmed during the manual try-out. |

**Validation rules** (checked before anything is created; all refusals print
plain-language messages, per FR-005/FR-006):

- `STACK_MODE` must be one of the three values; anything else → refuse and
  name the valid choices.
- With `aks`: user must be signed in (`az account show` succeeds).
- Subscription (if set) must exist and be accessible.
- Location (chosen or fallback) must appear in `az account list-locations`.
- Every machine size in the pool table must be **offered in that location**
  (Resource Skus List read with `az rest` + `Microsoft.Compute/skus`,
  api-version 2021-07-01 — the same names-regardless-of-`restrictions`
  rule the manual try-out proved with `az vm list-skus --all`; contract §1
  records the shape). A missing size stops the run with a plain message
  naming it — no silent swap, and no automatic move to another region (the
  `eastus2` fallback applies only when the setting is empty, never after a
  failed check).
- The **machine allowance must fit the chosen mode** (`az vm list-usage
  --location <loc> --output json`, parsed by field name — object-shaped TSV
  has no ordering guarantee). Needs cover only resources that do not exist
  yet, and the mode already used by existing workload pools is preserved on
  a resume (T050): spot first (whole missing shape), then regular per
  family; neither fits → plain refusal naming the short allowance
  (FR-014, AD-002). This is the newest rule; details live in the spot
  bullet of §3.
- `AKS_KUBERNETES_VERSION` must be non-empty.

## 2. Generated names

Both names are built before anything is created, and the recipe always makes
the same result from the same ingredients:

```text
<name> = signed-in Azure user (az account show --query user.name),
         lowercased, non-alphanumeric replaced with '-'
<code> = first 6 hex characters of SHA-256 over
         "$AZURE_SUBSCRIPTION_ID:$AZURE_LOCATION:$CLUSTER_SHAPE_VERSION"

resource group name = "<name>-aks-<code>"     (e.g. rijo-aks-4f2c9a)
cluster name        = "sre-stack-<code>"      (e.g. sre-stack-4f2c9a)
```

- `CLUSTER_SHAPE_VERSION` is a short constant inside the script (bumped only
  if the pool table itself changes), so the code reflects the settings that
  matter, not the script's revision number.
- Rerun rule: the setup script checks each resource by its exact name —
  group, cluster, each node pool, the gp2 StorageClass — and creates only
  what is missing (FR-003). A rerun after a complete run creates nothing
  new; a rerun after a partial run continues where it stopped (FR-011).
  The allowance check reserves room only for what is missing, so a
  complete cluster reruns (and verifies) even when it already consumes the
  full allowance, and a partly built cluster continues in the machine mode
  its existing workload pools already use — never a mixed one (T050).
  If the reused cluster's live `kubernetesVersion` differs from the `.env`
  pin, the setup prints a plain warning naming both versions and the
  deliberate change path (`make cleanup-cluster`, then `make setup-cluster`)
  — it never upgrades the cluster in place.
- Deletion guard: cleanup deletes **only** a group whose name matches the
  pattern `*-aks-*` and equals the generated name — never an unrelated group.
- The second, automatic folder: when the cluster is created, Azure quietly
  makes a **node resource group** named
  `MC_<resource-group>_<cluster>_<location>`. It holds the real machines
  (virtual machine scale sets), disks, and networking for the cluster.
  AKS deletes this group by itself whenever the cluster is deleted, and
  deleting our main group deletes the cluster — so `az group delete` of the
  main group takes the `MC_` group with it. Cleanup verifies this by checking
  **the one exact predicted name** (built from our generated group, cluster,
  and location) — a subscription shared by several people contains other
  people's `MC_` groups too, so the script never searches by the `MC_`
  prefix. If the exact group still exists after deletion, it warns with the
  removal command (never deletes it blindly). The same check runs when the
  main group is already absent, so a retry catches an orphaned node group;
  a failed existence read is never treated as "nothing to clean" (T051).

## 3. The cluster shape (what "mirror the Amazon cluster" means)

One row per node pool. This table is the single source of truth; the setup
script builds from it, the verify script checks against it, and the offline
stand-in answers with it.

| Pool name | Machine size | Count (min–max) | Label | Taint | Spot-capable? | Pool kind |
|---|---|---|---|---|---|---|
| system | Standard_D2s_v5 | 1–1 | — | — | no | System |
| app | Standard_D2s_v5 | 3–6 | `workload=app` | — | yes | User |
| persistent | Standard_D4s_v5 | 2–2 | `workload=persistent` | `persistent=true:NoSchedule` | yes | User |
| o11y | Standard_D4s_v5 | 2–3 | `workload=o11y` | `o11y=true:NoSchedule` | yes | User |
| loadgen | Standard_F4s_v2 | 1–1 | `workload=loadgen` | `loadgen=true:NoSchedule` | yes | User |

Notes:

- `system` is Azure's own housekeeping pool. Azure requires the first pool to
  be a non-spot system pool; it is not one of the four Amazon node groups and
  exists purely because AKS needs it.
- **"Spot-capable?" and the mode actually used are different things.** Spot
  capability marks which pools *may* run on cheaper spot machines (here:
  all four workload pools). Which mode the setup actually uses is decided
  at run time by the helper's allowance check (`az vm list-usage`),
  **before anything is created** (FR-014, AD-002). The needs count only the
  pools that do not exist yet, and when workload pools already exist their
  mode is kept (T050), so a resume never mixes modes and a complete rerun
  needs no fresh capacity:
    1. spot allowance in the location ≥ 26 vCPU for the **missing** workload
       pools (full shape: app 6 + persistent 8 + o11y 8 + loadgen 4) **and**
       regular DSv5 room ≥ 2 vCPU for the always-regular system pool (1×
       `Standard_D2s_v5`) when the cluster is also missing → every
       spot-capable pool is created with the spot flags from §3/​research.md
       (`--priority Spot --eviction-policy Delete ...`);
    2. else regular per-family allowances fit for the missing pools (full
       shape: DSv5 family 24 — 22 workload + 2 for the system pool; FSv2
       family 4 — both at the minimum counts, like the spot case)
       → same pools without spot flags;
    3. else the setup refuses with a plain message naming the short
       allowance, before creating anything. A resume with existing spot
       pools whose remaining spot room cannot cover the missing pools is
       refused the same way — never flipped to regular.
  All-or-nothing per mode; the `system` pool is always regular because
  Azure requires the first pool on a cluster to be a non-spot system pool.
  The allowance is judged against the documented **minimum counts** only;
  when a pool grows automatically later, Azure simply stops granting
  machines beyond the allowance — nothing in the scripts dodges or works
  around that.
- **When spot mode is on**, every workload manifest that targets these
  pools needs one extra toleration for Azure's auto-taint
  `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` (AWS/eksctl adds
  no such taint). Manifests are not part of this story — this is recorded
  for the workload-installation stories (data-model change from the 1.0
  "flip recipe": the mode is now chosen by the check, not folded into the
  table).
- State transitions (pool lifecycle): **absent → creating → running**.
  A pool that stops partway stays as-is; the script reports what reached
  `running` and what did not, and never deletes anything on its own (FR-011).
- Cluster-level state read by the verify script: `provisioningState`
  (`Succeeded` wanted) and `powerState` (`Running` wanted).

## 4. Storage

One object: a StorageClass (a storage "setting" pods ask for by name).

| Field | Value |
|---|---|
| Name | `gp2` |
| Provisioner | `disk.csi.azure.com` (Azure's disk driver) |
| Backing disk | Standard SSD (`StandardSSD_LRS`) |
| Binding | `WaitForFirstConsumer` (make the disk only when a pod actually needs it, in that pod's zone) |
| Reclaim | `Delete` (throw the disk away with the volume claim) |
| Expansion | allowed (grow a disk without replacing it) |

Same fields as the k3d alias in `infra/local/gp2-storageclass.yaml`, pointed
at Azure's driver instead of the laptop driver. Lives at
`infra/azure/gp2-storageclass.yaml`.

## 5. Things that must not change

- Every `.env` key that exists today keeps its meaning.
- `make setup` / `make cleanup-cluster` keep their names and behaviour for
  `eks` and `local`.
- Nothing under `app/`, `monitoring/`, `scenarios/` changes.

## 6. Relationships in one picture

```text
.env settings ──► name recipe ──► resource group ──contains──► AKS cluster
                                                                     │
                                          ┌───────────┬───────────┬──┴───────┐
                                       system pool  app pool  persistent  o11y / loadgen
                                                                        pools
cluster ──has──► gp2 StorageClass (applied by kubectl after pools are up)
verify script ──reads──► cluster + pools ──compares──► §3 table ──prints──► plain report
```
