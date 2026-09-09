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
| Am I signed in? | `az account show` | Fails → print "not signed in; run az login first" and stop (exit ≠ 0). |
| Who am I? | `az account show --query user.name --output tsv` | Value feeds the resource-group name. Empty → fall back to `$USER`. |
| Which bill? | `az account set --subscription "$AZURE_SUBSCRIPTION_ID"` | Only when the setting is non-empty. Fails → "subscription not found" and stop. |
| Is the location real? | `az account list-locations --query "[].name" --output tsv` | Chosen (or fallback `eastus2`) location must appear in the list; else "location not available" and stop. |
| Are the machine sizes offered there? | `az vm list-skus --location <location> --all --query "[].name" --output tsv` | Every size in the pool table (`Standard_D2s_v5`, `Standard_D4s_v5`, `Standard_F4s_v2`) must appear; else name the first missing size ("machine size X is not offered in Y; pick a location that offers it") and stop. No silent swap, no auto-fallback. `--all` includes sizes blocked for this subscription so the message can be precise. |
| Does the group already exist? | `az group exists --name <generated>` | `true` → skip only the `az group create` step (per-resource idempotency, FR-003/FR-011). |
| Does the cluster already exist? | `az aks show --resource-group <rg> --name <cluster>` | Succeeds → skip `az aks create` (cluster and its system pool already exist). |
| Does a node pool already exist? | `az aks nodepool show --resource-group <rg> --cluster-name <cluster> --name <pool>` | Succeeds → skip that pool's `az aks nodepool add`. Checked per pool, before each add. |
| Does the storage setting already exist? | `kubectl get storageclass gp2` | Succeeds → skip `kubectl apply -f infra/azure/gp2-storageclass.yaml`. |

### Creating (setup)

| Purpose | Command shape |
|---|---|
| Make the group | `az group create --name <generated-rg> --location <location>` |
| Make the cluster + system pool | `az aks create --resource-group <rg> --name <generated-cluster> --location <location> --kubernetes-version <pinned> --node-count 1 --node-vm-size Standard_D2s_v5 --generate-ssh-keys --no-wait` then wait for completion. (No `--mode` argument exists on `az aks create` — the initial pool is System by default; confirmed in the manual try-out.) |
| Add each workload pool | `az aks nodepool add --resource-group <rg> --cluster-name <cluster> --name <pool> --node-count <n> --node-vm-size <size> --labels workload=<value> --node-taints <taint-or-omitted> --enable-cluster-autoscaler --min-count <min> --max-count <max>`. Workload pools are **regular** (on-demand) per data-model §3 — no spot flags. If the §3 table ever says `Spot` again, the spot flags live in research.md §3 and this contract must be re-synced in the same commit. |
| Get kubectl access | `az aks get-credentials --resource-group <rg> --name <cluster> --overwrite-existing` |
| Add the storage setting | `kubectl apply -f infra/azure/gp2-storageclass.yaml` |

### Checking (verify — read only, always)

| Purpose | Command | Fields read |
|---|---|---|
| Is the control plane ready? | `az aks show --resource-group <rg> --name <cluster>` | `provisioningState` = `Succeeded`, `powerState.code` = `Running` |
| Does each pool match? | `az aks nodepool list --resource-group <rg> --cluster-name <cluster>` | per pool: `name`, `count`, `vmSize`, `nodeLabels`, `nodeTaints`, `minCount`, `maxCount`, `scaleSetPriority`, `provisioningState` |

The verify script prints one plain line per pool, e.g.
`✓ app: 3 nodes, Standard_D2s_v5, label workload=app — matches Amazon`
or `✗ o11y: expected taint o11y=true:NoSchedule, found none`.
With the current table all five pools are regular, so `scaleSetPriority`
is `null` (or `Regular`) on every pool; the line never says "spot" unless
the §3 table in data-model.md says so again.

### Deleting (cleanup)

| Purpose | Command | Guard |
|---|---|---|
| Is there anything to remove? | `az group exists --name <generated>` | `false` → "nothing to clean" and exit 0 (FR-004 case 2). |
| Remove it all | `az group delete --name <generated> --yes` | Name must equal the generated name; a mismatch never deletes. |
| Confirm the automatic second folder is gone | `az group show --name MC_<generated-rg>_<generated-cluster>_<location>` | The node resource group's name is fully predictable — `MC_<our-rg>_<our-cluster>_<location>` — so the script checks **only that exact name**, never a broad `MC_*` search. The subscription may be shared by several people, each with their own `MC_` groups; those belong to them and must never be touched or even reported by us. If the exact group still exists after the delete finishes, print a plain warning naming it and how to remove it (`az group delete --name <that-exact-group> --yes`), and exit non-zero. Never delete an `MC_` group by hand unless the cluster is already gone. |

## 2. What the pretend `az` must imitate (offline tests, FR-013)

The stand-in is a small script placed first on `PATH`. Rules:

1. **Record every call** — append the full argument list to a log file,
   one line per call, in order.
2. **Answer from a scenario file** — fixed JSON that has the same shape as
   the real `az` output shown in §1. Required scenarios:
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
   - `missing-vm-size`: location real, but `az vm list-skus` omits
     `Standard_F4s_v2` → refusal message naming that size, nothing created,
     no `group create` recorded.
   - `bad-provider`: `STACK_MODE=nonsense` → refusal message naming the three
     valid values.
   - `mc-lingers`: after `az group delete`, `az group show --name
     MC_<expected-exact-name>` still succeeds → plain warning naming that
     one group and the removal command, exit non-zero, and **no** second
     delete call recorded. The stand-in also proves isolation: other `MC_`
     groups (other people's) exist in the scenario, and the script must
     never call a list/search over `MC_*`.
   - `partial`: group + cluster succeeded, `app` pool created, `persistent`
     add failed → the script stops, prints the plain report (group name,
     cluster name, pools that reached `running`), records **no** delete call.
   - `cleanup-full`: group exists → one `az group delete --yes` call recorded.
   - `cleanup-empty`: group doesn't exist → zero delete calls, exit 0.
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
Setup stopped partway. Created so far:
  - resource group rijo-aks-4f2c9a
  - cluster sre-stack-4f2c9a
  - node pool system (running)
  - node pool app (running)
Not created: persistent, o11y, loadgen, gp2 storage setting.
Nothing was deleted. Options:
  - run 'make setup-cluster' again to continue, or
  - run 'make cleanup-cluster' to remove everything and start fresh.
```
