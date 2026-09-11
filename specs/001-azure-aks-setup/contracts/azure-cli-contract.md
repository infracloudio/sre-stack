# Contract: the Azure CLI commands this feature depends on

*This document fixes two things:*
1. *Exactly which `az` commands the scripts may use, and what they must check
   from each answer.*
2. *What the pretend `az` (the offline stand-in used by the no-cloud tests)
   must imitate, so tests match reality.*

Any script change that needs a command not listed here must update this
contract in the same commit.

## 1. Commands the real scripts use

### Before anything is created (shared helper `azure-common.sh`, plus per-resource existence checks in the setup script)

| Purpose | Command | What the script does with the answer |
|---|---|---|
| Which CLI is this? | `az version --query azure-cli --output tsv` (fallback `az --version`) | Prints the version; warns plainly when older than the documented minimum 2.87.0; never stops. |
| Am I signed in? | `az account show` | Fails → print "not signed in; run az login first" and stop (exit ≠ 0). |
| Who am I? | `az account show --query user.name --output tsv` | Value feeds the resource-group name and the permission pre-check. Empty → "no usable principal name" and stop. |
| Which subscription is active? | `az account show --query id --output tsv` | Read once after the sign-in/subscription checks: the active subscription id feeds the RBAC scope match (`/subscriptions/<id>`) and the Resource Skus URL. Confirmed by hand in the manual try-out (research.md "Manual pass findings"). |
| May we create anything? | `az role assignment list --assignee <user.name> --include-groups --include-inherited` | The permission check before anything is created: the identity (or its groups) must hold an assignment that covers the subscription — an exact `/subscriptions/<id>` scope, `/`, or a parent `…/managementGroups/*` scope. `--include-inherited` makes Azure return only assignments effective at the current subscription (its own scope, root, and the management-group scopes that actually contain it), so a management-group row is an ancestor by construction — T027 tightened this after T024 accepted any management-group string; an unrelated management group is never returned. Owner or Contributor pass directly; any other role passes only when `az role definition list --query "[?contains(id-list, id)]"` shows its actions include `"*"`, `"*/write"`, or `"Microsoft.ContainerService/*"` ("custom-role-with-create"). A resource-group-only or other-subscription assignment is not enough (the generated group is created new). No covering assignment → refusal and stop. Field order in list output follows the projected keys alphabetically (id, role, scope). |
| Which bill? | `az account set --subscription "$AZURE_SUBSCRIPTION_ID"` | Only when the setting is non-empty. Fails → "subscription not found" and stop. |
| Is the location real? | `az account list-locations --query "[?name=='<location>'].name" --output tsv` | Chosen (or fallback `eastus2`) location must appear in the list; else "location not available" and stop. (2026-09-10 speed pass: narrowed the query; the answer set is the same name list.) |
| Are the machine sizes offered there? | `az rest --method GET --url "https://management.azure.com/subscriptions/<sub>/providers/Microsoft.Compute/skus?api-version=2021-07-01&\$filter=location eq '<location>'"` (2026-09-10 speed pass replacing a plain-CLI `az vm list-skus` call that stalls 90 s–2 min; azure-cli issues #31592/#30389) — parsed locally for the three size names at the location (virtualMachines entries, names checked regardless of restrictions = the old `--all` semantics: `Standard_D2s_v5`, `Standard_D4s_v5`, `Standard_F4s_v2` must appear; else name the first missing size ("machine size X is not offered in Y; pick a location that offers it") and stop. No silent swap, no auto-fallback. |
| Does the group already exist? | `az group exists --name <generated>` | `true` → skip only the `az group create` step (per-resource idempotency, FR-003/FR-011). The answer must be exactly `true`/`false` with exit 0 in both setup and cleanup; any other exit code or output is a failed read — stop with "could not check whether resource group … exists" before creating or deleting anything, never treat as absent (T051/T057). A failed-read resource is reported under "Could not be checked", never under "Not created" (T059). |
| Does the allowance fit the designed shape? | `az vm list-usage --location <location> --output json` | Decides the workload-pool mode before anything is created (FR-014, AD-002). The answer is a bare JSON array of usage items (T058 — not a REST-style `{"value": [...]}` object), parsed **by field name** — object-shaped TSV has no ordering guarantee; Azure alphabetizes projected keys only as a best effort, so `{name, what, cur, lim}` may come back `cur, lim, name, what` (T054). Each item's `name.value` (`lowPriorityCores`, `standardDSv5Family`, `standardFSv2Family`), `currentValue`, and `limit` are read by name; numbers may arrive as ints or numeric strings ("30") and both parse (T058); anything else (non-array, missing fields, non-numeric counts) is malformed — refuse with "machine allowance … could not be read" before anything is created. The system pool is always regular (Azure requires a non-spot first pool), so its 2 DSv5 vCPU count whenever the cluster itself is missing. The needs cover only resources that do not exist yet (T050): the helper first reads the existing workload pools (next row), so a complete-cluster rerun has needs 0 and can never be blocked by its own consumption. Fresh cluster, spot first: the location's spot vCPU item (e.g. `lowPriorityCores` / "Total Regional Low-priority vCPUs"; exact JSON field names confirmed by hand and recorded in research.md) must cover 26 vCPU — the four workload pools at minimum counts (app 6 + persistent 8 + o11y 8 + loadgen 4) — **and** the regular DSv5 room must cover the 2 vCPU of the 1× `Standard_D2s_v5` system pool → `AZURE_POOL_MODE=spot`. Else regular: per-family vCPU limits ("Standard DSv5 Family vCPUs" needs 24 — workload 22 + system 2, "Standard FSv2 Family vCPUs" needs 4) must all fit at the same minimum counts → `AZURE_POOL_MODE=regular`. When workload pools already exist, their mode is preserved (spot resume keeps spot, regular resume keeps regular; a mixed spot/regular cluster is refused) and the room must cover only the missing pools' minimum counts. Else print "not enough machine allowance" naming the short family and its current+limit numbers, and stop — the refusal happens before `az group create`, so nothing is created. Judged at minimum counts; autoscaler growth is capped by the allowance, never dodged. |
| Which workload pools already exist? | `az aks nodepool list --resource-group <rg> --cluster-name <cluster> --query "[].{name: name, mode: mode, priority: scaleSetPriority}" --output json` | Read only when `az aks show` succeeded, parsed by field name. The four expected names and their `scaleSetPriority` (`Spot` vs `null`/`Regular`) decide the preserved mode and subtract already-created pools from the allowance needs (T050). A failed read refuses before anything is created; the cluster is never upgraded or reshaped in place. |
| Does the cluster already exist? | `az aks show --resource-group <rg> --name <cluster>` | Succeeds → skip `az aks create` (cluster and its system pool already exist). Only a NotFound answer (`ResourceNotFound`/`was not found`) means absent; any other non-zero read is a failed read — stop with "could not check whether cluster … exists" before creating, never start a duplicate (T057). The helper also runs it once with `--output none` before the allowance check, because the system pool and every existing pool change what the check needs to reserve (T050); a failed helper read refuses the same way. An accepted `--no-wait` create whose state then cannot be read is reported under "Submitted but not confirmed" together with its system pool — never under "Not created" (T056/T059). |
| Does a node pool already exist? | `az aks nodepool show --resource-group <rg> --cluster-name <cluster> --name <pool>` | Succeeds → skip that pool's `az aks nodepool add`. Checked per pool, before each add. Only a NotFound answer (`AgentPoolNotFound`/`was not found`) means absent; any other failure stops with "could not check whether node pool … exists" before adding (T057) and the pool is listed under "Could not be checked", never as absent (T059). A failed `nodepool add` is reported under "Submitted but not confirmed" — the add may have landed on Azure's side — never as "Not created" (T059). |
| Does the storage setting already exist? | `kubectl get storageclass gp2` | Succeeds → skip `kubectl apply -f infra/azure/gp2-storageclass.yaml`. Only a NotFound answer (`… "gp2" not found`) means absent; any other failure stops with "could not check whether the gp2 storage setting exists" before applying (T057), listed under "Could not be checked" (T059). |

### Creating (setup)

| Purpose | Command shape |
|---|---|
| Make the group | `az group create --name <generated-rg> --location <location>` |
| Make the cluster + system pool | `az aks create --resource-group <rg> --name <generated-cluster> --location <location> --kubernetes-version <pinned> --node-count 1 --node-vm-size Standard_D2s_v5 --generate-ssh-keys --no-wait` then wait for completion. (No `--mode` argument exists on `az aks create` — the initial pool is System by default; confirmed in the manual try-out.) |
| Add each workload pool | `az aks nodepool add --resource-group <rg> --cluster-name <cluster> --name <pool> --node-count <n> --node-vm-size <size> --labels workload=<value> --node-taints <taint-or-omitted> --enable-cluster-autoscaler --min-count <min> --max-count <max>`. The four workload pools are always created with these base flags; counts/sizes/labels/taints come from the data-model §3 table. When the allowance check exported `AZURE_POOL_MODE=spot`, the command **also** carries the spot flags proved in the manual try-out (recorded in research.md §3 — `--priority Spot --eviction-policy Delete` shape); when it exported `regular`, no spot flags are added. All-or-nothing per run (FR-014, AD-002). |
| Get kubectl access | `az aks get-credentials --resource-group <rg> --name <cluster> --overwrite-existing` |
| Add the storage setting | `kubectl apply -f infra/azure/gp2-storageclass.yaml` |

### Checking (verify — read only, always)

| Purpose | Command | Fields read |
|---|---|---|
| Is the control plane ready? | `az aks show --resource-group <rg> --name <cluster>` | `provisioningState` = `Succeeded`, `powerState.code` = `Running` |
| Does each pool match? | `az aks nodepool list --resource-group <rg> --cluster-name <cluster>` | per pool: `name`, `mode` (finds the system pool — Azure names it itself, e.g. `nodepool1`), `count`, `vmSize`, `nodeLabels`, `nodeTaints`, `minCount`, `maxCount`, `scaleSetPriority`. Every workload pool must have `mode: User`; any other mode is a mismatch (T060). The set must be exactly one System pool plus the four workload pools — any extra User pool (even a healthy sixth pool with ten nodes) is a mismatch (T060). The per-pool `provisioningState` was dropped: a pool legitimately reads `Updating` for minutes after a change (research.md fact 6), so verification gates on the cluster-level `az aks show` state plus the live `count`s instead of racing a field that settles on its own. |
| Which cluster do the kubectl reads target? | `kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}'` | Must equal the generated cluster name. A failed read or a different cluster is a mismatch **and the namespace/workload checks are skipped** (T055) — reads against another cluster prove nothing. |
| Is the cluster still empty (namespaces)? | `kubectl get namespaces --output name` | Only `default` and `kube-*` may exist; any other namespace is a mismatch (FR-008). Read-only; a failed or empty read is a mismatch. |
| Is the cluster still empty (workloads)? | `kubectl get deployments,statefulsets,daemonsets,jobs,cronjobs,pods --all-namespaces --output json` | Any workload whose namespace is not `kube-*` is a mismatch (FR-008): housekeeping workloads in kube-* namespaces are legitimate, an application Deployment in `default` is not (T055). Read-only; a failed read is a mismatch. |

The verify script prints one plain line per pool, e.g.
`✓ app: 3 nodes, Standard_D2s_v5, label workload=app, regular — matches Amazon`
or `✗ o11y: expected taint o11y=true:NoSchedule, found none`.
Every workload pool's `scaleSetPriority` is compared against the mode the
allowance check chose (data-model §3): `Spot` when `AZURE_POOL_MODE=spot`,
`null`/`Regular` when `regular`. A pool whose priority does not match the
mode flagged otherwise in the report. The system pool is always checked as
`null`/`Regular`.
**Spot-mode taint exception**: in spot mode Azure auto-adds
`kubernetes.azure.com/scalesetpriority=spot:NoSchedule` to every workload
pool. That one taint is **excluded** from the `nodeTaints` comparison
(healthy spot clusters would otherwise fail as "unexpected taint"); the
data-model §3 taints are still compared on top of it, and any taint other
than the expected ones plus this auto-taint is a mismatch (data-model §3
records why manifests later need a toleration for it).

### Deleting (cleanup)

Cleanup sources the shared helper in cleanup mode (`AZURE_CLEANUP=1`, T014):
sign-in plus the generated names only. The create-time pre-checks at the top
of this section do not run, so teardown is never blocked because quota,
offered sizes, or roles changed since setup.

| Purpose | Command | Guard |
|---|---|---|
| Is there anything to remove? | `az group exists --name <generated>` | Must answer exactly `true` or `false`. `false` = the main group is confirmed absent; the node-group check below still runs (T051). Any other exit code or output is a **failed read**: cleanup stops non-zero with "could not check ...", never "Nothing to clean" on unreadable state (T051). Before any delete the message ends "Nothing was deleted"; after a successful main delete a failed node-group read must not say that — it reports the deleted main group plus the unknown node-group state (T059). |
| Remove it all | `az group delete --name <generated> --yes` | Name must equal the generated name; a mismatch never deletes. On failure, a read-only follow-up `az group exists` names whether the group still exists ("still exists; some resources may remain" — never "nothing else was removed", T059), or that its state could not be checked; exit non-zero with no second delete (T056). |
| Confirm the automatic second folder is gone | `az group exists --name MC_<generated-rg>_<generated-cluster>_<location>` | Same confirmed/read-failed contract as the first row. The node resource group's name is fully predictable — `MC_<our-rg>_<our-cluster>_<location>` — so the script checks **only that exact name**, never a broad `MC_*` search or list. The subscription may be shared by several people, each with their own `MC_` groups; those belong to them and must never be touched or even reported by us. The check runs after a successful delete **and** when the main group was already absent (T051), so a retry after a partial teardown catches an orphaned node group. If the exact group exists, print a plain warning naming it and how to remove it (`az group delete --name <that-exact-group> --yes`), and exit non-zero. Never delete an `MC_` group by hand unless the cluster is already gone. |

## 2. What the pretend `az` must imitate (offline tests, FR-013)

The stand-in is a small script placed first on `PATH`. Rules:

0. **kubectl too** — the setup script also runs `kubectl` (`kubectl get
   storageclass gp2` and `kubectl apply`), so the harness puts a fake
   `kubectl` (`agent/tests/azure/fake-kubectl.sh`) on the same PATH and it
   records into the same log: after the apply is recorded, the `get
   storageclass gp2` check succeeds; a scenario's `PRE_SC=1` knob makes the
   get succeed before any apply. It also answers the verifier's kubectl
   reads: `kubectl config view --minify …` returns `FAKE_CONTEXT` (the
   runner seeds it with the generated cluster name, a scenario overrides it
   to prove the wrong-context mismatch, T055); `kubectl get namespaces
   --output name` returns `FAKE_NAMESPACES` (default the four built-in
   namespaces) and `KUBECTL_NAMESPACES_FAIL=1` makes the read fail;
   `kubectl get deployments,… --all-namespaces --output json` returns the
   `FAKE_WORKLOADS` entries (`namespace/Kind/name`, default none), so the
   workload check and the fail-closed namespace check (T034/T055) are
   exercised offline too.
1. **Record every call** — append the full argument list to a log file,
   one line per call, in order; unknown `az` commands exit non-zero.
   The `vm list-usage` answer is a bare JSON array only when `--output json`
   is asked for (T058 — the real CLI shape, parsed by field name; numeric
   strings also parse; `USAGE_MALFORMED=1` proves a malformed answer refuses
   plainly); the legacy object-projection TSV path returns the real
   alphabetical column order (`cur, lim, name, what`) so an order-dependent
   reader fails loudly offline (T054). `SPOT_CURRENT`/`DSV5_CURRENT`/
   `FSV2_CURRENT` model an existing cluster that already consumes allowance.
   `GROUP_READ_FAIL=1`, `CLUSTER_READ_FAIL=1`, `POOL_READ_FAIL=1|<pool>`,
   `KUBECTL_SC_FAIL=1`, `MC_READ_FAIL=1`, `DELETE_FAIL=1`, and
   `CLUSTER_STATE_FAIL=1` drive the failed-read / failed-delete /
   async-create paths (T051/T056/T057/T059). Absent clusters/pools answer
   with a NotFound error on stderr (`ResourceNotFound`/`AgentPoolNotFound`),
   so only that shape means absent — any other failure is a failed read
   (T057). `USAGE_NUMERIC_STRINGS=1` emits the allowance numbers as strings
   (T058). `EXTRA_POOLS` adds documented-shape extra pools for the verifier
   (T060, `name[:mode[:count[:size]]]`).
2. **Answer from a scenario file** — one file per scenario
   (`agent/tests/azure/scenarios/<name>.sh`), sourced by the stand-in; the
   scenario knobs describe the world in plain shell variables, and the
   stand-in's answers carry JSON shaped like the real `az` output recorded
   in research.md A7/§4 (the nodepool list is rebuilt from the data-model
   §3 table, with `scaleSetPriority: Spot/null` and the spot auto-taint
   following the scenario's pool mode; the `POOL_MUTATIONS` knob perturbs
   single rows for the verify scenarios — `pool.field=value` for
   count/min/max/size/label/taints/spot/mode, or `pool.missing=1` to drop
   the row, where `pool` is a workload name or `system`; an unknown target
   is a loud stand-in error). Required scenarios:
   - `happy`: account exists, nothing exists yet → group create → cluster
     create → four nodepool adds → group exists true afterwards.
   - `already-there`: group, cluster, all five pools, and the gp2 StorageClass
     already exist → setup must record **no** create calls at all.
   - `resume`: group, cluster, and the `app` pool already exist;
     `persistent`, `o11y`, `loadgen`, and the StorageClass are missing →
     setup records **no** `group create`, **no** `az aks create`, and **no**
     `app` nodepool add, and records adds for exactly the three missing
     pools, plus get-credentials and the storageclass apply.
   - `not-signed-in`: `az account show` fails → refusal message, and **no**
     create call recorded after it.
   - `bad-location`: location not in the list → refusal message, nothing created.
    - `missing-vm-size`: location real, but the resource-sku answer omits
      `Standard_F4s_v2` → refusal message naming that size, nothing created,
      no `group create` recorded.
    - `rbac-mg-ancestor`: the create-capable assignment is Contributor on a
      management group that contains the subscription; the stand-in returns
      that parent-scope row only when the call carries `--include-inherited`
      (Azure's own semantics) → setup proceeds and records its create calls.
    - `rbac-mg-unrelated`: the create-capable assignment sits on a management
      group that does not contain the subscription; the stand-in never
      returns it → refusal, and no create call.
   - `spot-fits`: the usage answer covers the whole shape with spot vCPU
     (26+) → every `az aks nodepool add` for the four workload pools is
     recorded **with** the spot flags; the system pool's creation carries
     none.
    - `spot-short`: spot vCPU below 26, regular per-family limits fit →
      the same adds recorded **without** spot flags, and no refusal.
    - `spot-resume`: group, cluster, and two spot workload pools exist
      (their 14 vCPU already count against a 30 spot limit) → the remaining
      two pools are added **with** the spot flags, the existing pools are
      not re-added, and no create call is recorded. The mode follows the
      existing pools, never the free allowance.
    - `spot-resume-short`: the same partial spot cluster but the spot
      allowance is exhausted (14/14) → plain refusal naming the spot
      allowance, exit ≠ 0, **no** adds, and never a silent flip to regular.
    - `regular-full-resume`: a complete regular cluster consumes every
      allowed DSv5 (24) and FSv2 (4) vCPU → the no-op rerun succeeds with
      needs 0, records no adds, no creates, and no deletes (T050).
    - `no-room`: spot short **and** one regular family below its needed
     vCPU (e.g. FSv2 limit 2 < 4) → plain refusal naming that family with
     its current and limit numbers, exit ≠ 0, and **no** `az group create`
     recorded.
   - `system-blocked`: spot vCPU covers the workload pools (30 ≥ 26) but
     the regular DSv5 room is below the 2 vCPU the always-regular system
     pool needs (limit 1) → plain refusal naming DSv5 with its numbers,
     exit ≠ 0, and **no** `az group create` recorded.
     - `mc-lingers`: after `az group delete`, the exact predicted name
      answers `az group exists --name MC_<expected-exact-name>` = `true` →
      plain warning naming that one group and the removal command, exit
      non-zero, and **no** second delete call recorded. The stand-in also
      proves isolation: other `MC_` groups (other people's) exist in the
      scenario, and the script must never call a list/search over `MC_*`.
    - `partial`: group + cluster succeeded, `app` pool created, `persistent`
      add failed → the script stops, prints the plain report (group name,
      cluster name, pools that reached `running`), the failed pool under
      "Submitted but not confirmed" (it may have landed — never "Not
      created", T059), records **no** delete call.
    - `partial-async`: `az aks create` is accepted (`--no-wait`) and every
      subsequent `provisioningState` read fails (`CLUSTER_STATE_FAIL=1`,
      retries forced to 1) → the script stops and reports the cluster and
      its system pool under "Submitted but not confirmed", **never** under
      "Not created", records no delete call (T056/T059).
    - `cleanup-full`: group exists, its exact MC name does not → one
      `az group delete --yes` call recorded and exactly one exact-name
      `az group exists --name MC_…` check.
    - `cleanup-empty`: neither group exists → zero delete calls, exit 0, and
      the exact-name MC check still runs once (T051).
    - `cleanup-read-error`: `az group exists` fails (`GROUP_READ_FAIL=1`) →
      "could not check whether resource group … exists", exit ≠ 0, zero
      deletes, and **never** "Nothing to clean" (T051).
    - `cleanup-orphan-retry`: the main group is confirmed absent but the
      exact predicted MC name answers `true` (`MC_LINGERS=1`) → warning
      naming the orphan plus the removal command, exit ≠ 0, zero deletes
      (T051).
    - `cleanup-delete-fail`: `az group delete` fails (`DELETE_FAIL=1`) → the
      follow-up read confirms the group still exists, exit ≠ 0, exactly one
      delete attempt, no success claim, and never "nothing else was removed"
      — a failed delete may have removed inner resources (T056/T059).
    - `cleanup-mc-read-fail`: the main group deletes cleanly but the exact
      node-group read fails (`MC_READ_FAIL=1`) → "deleted … but could not
      check whether node resource group …", exit ≠ 0, exactly one delete,
      and never "Nothing was deleted" (T059).
   - `verify-ok`: the cluster and all four workload pools match the §3 table
     in regular mode and only the built-in namespaces exist → the verifier
     prints ✓ for the control plane and every pool, reports zero mismatches,
     and exits 0 with **no** create or delete call recorded.
   - `verify-pool-mismatch`: malformed pool rows (app count 99, persistent
     wrong size, o11y's taint dropped, loadgen missing) → the verifier exits
     non-zero with one ✗ per problem and a `report: 4 mismatch(es)` line.
   - `verify-namespace-extra`: pools match but a `team-a` namespace exists →
     the verifier exits non-zero naming that namespace (FR-008), while the
     pool lines still report ✓.
    - `verify-kubectl-fails`: `kubectl get namespaces` fails (bad kubeconfig)
      → the verifier fails closed with a ✗ and a non-zero exit, never an
      empty-cluster pass (T034 regression guard).
    - `verify-ok-full-quota`: the complete regular cluster from
      `regular-full-resume` → the verifier passes with zero mismatches
      without any free capacity for a second cluster (T050).
    - `verify-workload-extra`: pools and namespaces match, but
      `FAKE_WORKLOADS` holds `default/Deployment/robot-shop` → the verifier
      exits non-zero with one ✗ naming that workload while the pool lines
      stay ✓ (T055).
    - `verify-wrong-context`: `FAKE_CONTEXT` names a different cluster → the
      verifier exits non-zero with one ✗ naming the context and trusts no
      kubectl read (no namespace/workload claims, T055).
    - `setup-group-read-error` / `setup-cluster-read-error` /
      `setup-pool-read-error` / `setup-storage-read-error` (T057): the
      group / cluster / pool / storage existence read fails
      (`GROUP_READ_FAIL=1`, `CLUSTER_READ_FAIL=1`, `POOL_READ_FAIL=<pool>`,
      `KUBECTL_SC_FAIL=1`) → plain "could not check … exists" refusal, exit
      ≠ 0, zero creates after it, and the unreadable resource under "Could
      not be checked" — never under "Not created" (T059).
    - `usage-strings` (T058): the allowance array carries numeric strings →
      setup still parses by field name and chooses spot when it fits.
    - `usage-malformed` (T058): the allowance answer is not a usage array →
      "machine allowance … could not be read", exit ≠ 0, no creates.
    - `verify-extra-pool` (T060): five documented pools match plus a sixth
      User pool (`EXTRA_POOLS="extra:User:10"`) → verifier exits non-zero
      with `✗ unexpected pool 'extra'` and `report: 1 mismatch(es)`.
    - `verify-wrong-mode` (T060): `app` runs as `mode: System`
      (`POOL_MUTATIONS="app.mode=System"`) → verifier exits non-zero naming
      the mode mismatch (plus the exactly-one-System count).

   The public entry points are covered too (T053): `make setup` and
   `make cleanup` run with `STACK_MODE=aks` and the fake PATH, and must
   record only the cluster scripts' calls (no Amazon targets); `make
   STACK_MODE=nonsense setup` refuses at make time, names the three valid
   values, and records no call at all — no cloud is touched.

   Cleanup scenarios run the cleanup script in its cleanup mode: the helper
   checks sign-in and computes the generated names, but the create-time probes
   (`az role assignment list`, `az account list-locations`, `az vm list-usage`,
   the resource-sku `az rest` call) never run, so these scenarios do not answer
   them — the runner asserts those calls are absent. The stand-in's
   `MC_LINGERS=1` knob makes `az group show --name MC_…` succeed so the
   lingering-node-group path is exercised.

   Verify scenarios run `infra/scripts/cluster/verify-cluster-aks.sh`
   directly (read-only): the scenario's `PRE_*`/`POOL_*` knobs satisfy its
   `azure-common.sh` pre-checks, and the runner asserts the verifier recorded
   no create or delete call (FR-012).
3. **Never touch the network.**

## 3. Error-message style (all refusal and failure paths)

Every refusal names: what is wrong, what to do, and stops before creating or
deleting anything. Example:

```text
Cannot start: no Azure sign-in found.
Run 'az login' first, then try again. Nothing was created.
```

Partial-failure report example:

```text
Setup stopped partway.
Confirmed created:
  - resource group rijo-aks-4f2c9a
  - cluster sre-stack-4f2c9a
  - node pool system (running)
  - node pool app (running)
Not created: persistent pool, o11y pool, loadgen pool, gp2 storage setting,
 (pool adds that did not run may still be finishing on Azure's side; nothing
 was deleted by us).
Nothing was deleted. Options:
  - run 'make setup-cluster' again to continue, or
  - run 'make cleanup-cluster' to remove everything and start fresh.
```

When the cluster create was accepted (`--no-wait`) but its state could not
be read, or polling timed out, the report gains a middle section instead of
asserting the cluster missing (T056/T059 — the system pool travels with the
cluster, so it is submitted too):

```text
Setup stopped partway.
Confirmed created:
  - resource group rijo-aks-4f2c9a
Submitted but not confirmed (the create was accepted or may have been accepted; re-run 'make setup-cluster' to check):
  - cluster sre-stack-4f2c9a
  - node pool system (running)
Not created: app pool, persistent pool, o11y pool, loadgen pool, kube credentials, gp2 storage setting,
```

A failed pool add is reported the same way — the pool may have landed, so it
is submitted, never "Not created" (T059). A failed existence read is reported
under a fourth section and excluded from "Not created" (T057/T059):

```text
Could not be checked (the read failed; may or may not exist — re-run to check):
  - persistent pool
```
