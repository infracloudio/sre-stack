# Quickstart: try Azure by hand, then check the scripts

*Two parts. Part A is the manual try-out the story owner asked for: run the
Azure commands one at a time, prove the approach, write down what you learn.
Part B is how anyone later checks the finished scripts, including with no
cloud at all. Read plan.md first for the big picture.*

---

## Part A — the manual try-out (do this BEFORE writing scripts)

**Why first**: every script copies these exact commands. Proving them by hand
turns "should work" into "does work", and fills in the three facts we cannot
know from documentation alone (Kubernetes versions offered today, machine
sizes available in your region, real output fields).

### What you need

- An Azure account that may create clusters (Contributor role or higher is
  the usual need for resource groups and AKS).
- The Azure command-line tool installed: `az --version` (2.87.0 or newer).
- `kubectl` installed (you likely have it already for the Amazon setup).

### Step-by-step

Set these once in your shell (change to your values):

```bash
LOCATION=westus2            # or any region close to you
SUBSCRIPTION_ID=<your-subscription-id>
RG=<yourname>-aks-manual    # manual pass folder; delete at the end
CLUSTER=sre-stack-manual
```

**A1. Sign in and pick the bill.**

```bash
az login
az account set --subscription "$SUBSCRIPTION_ID"
az account show --query user.name -o tsv     # who am I (feeds the name recipe)
```

Expect: your user name prints. Record it in research.md → "Manual pass findings".

**A2. Is the location real?**

```bash
az account list-locations --query "[].name" -o tsv | grep -x "$LOCATION"
```

Expect: the location name prints. If not, pick a listed one.

**A2b. Are all four machine sizes offered there?**

```bash
az vm list-skus --location "$LOCATION" --all --output table | grep -E "Standard_(D2s_v5|D4s_v5|F4s_v2)"
```

Expect: all three sizes print (the table uses three sizes across five pools).
If one is missing, pick a location that offers all of them — the final
script will stop with an error naming the missing size rather than swap it
silently. Record which sizes you confirmed in research.md.

**A3. Make and remove a folder (cheap rehearsal).**

```bash
az group create --name "$RG" --location "$LOCATION"
az group show --name "$RG"          # look at it
az group delete --name "$RG" --yes  # nothing inside yet, so this is quick
```

Expect: `"provisioningState": "Succeeded"`, then gone. Record the real
output fields you see.

**A4. Ask which Kubernetes versions are offered today.**

```bash
az aks get-versions --location "$LOCATION" -o table
```

Expect: a list. Pick a supported version and **write it in research.md** —
it becomes the pinned `AKS_KUBERNETES_VERSION` in `.env`.

**A5. Make the cluster with its housekeeping pool.**

```bash
az group create --name "$RG" --location "$LOCATION"
az aks create \
  --resource-group "$RG" --name "$CLUSTER" \
  --location "$LOCATION" \
  --kubernetes-version <version-from-A4> \
  --node-count 1 --node-vm-size Standard_D2s_v5 \
  --mode System --generate-ssh-keys
```

Expect: takes several minutes; ends with JSON where
`provisioningState` is `Succeeded`. (If Standard_D2s_v5 is unavailable in
your region, pick the nearest available D-series and record it.)

**A6. Add one workload pool with label, taint, and spot.**

> Historical note: this step proved the *spot* command shape during the
> try-out (2026-09-09). Current design (FR-014, AD-002): the shared helper
> measures the allowance before creating anything and prefers spot when it
> fits, so this exact command shape is used whenever the check picks spot;
> in regular mode the same command runs without the three spot flags
> (`--priority`, `--eviction-policy`, `--spot-max-price`). The
> authoritative shape is the pool table in data-model.md §3 and plan.md.

```bash
az aks nodepool add \
  --resource-group "$RG" --cluster-name "$CLUSTER" --name persistent \
  --node-count 2 --node-vm-size Standard_D4s_v5 \
  --labels workload=persistent \
  --node-taints "persistent=true:NoSchedule" \
  --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --enable-cluster-autoscaler --min-count 2 --max-count 2
```

Expect: succeeds. If your region lacks capacity, record which VM sizes do
work — that is exactly what research.md is for.

**A7. Look at what exists (this becomes the verify script).**

```bash
az aks show --resource-group "$RG" --name "$CLUSTER" \
  --query "{state:provisioningState, power:powerState.code}"
az aks nodepool list --resource-group "$RG" --cluster-name "$CLUSTER" \
  --query "[].{name:name, count:count, size:vmSize, labels:nodeLabels, taints:nodeTaints, spot:scaleSetPriority}"
```

Expect: `state: Succeeded`, `power: Running`, and both pools listed with the
label, taint, and `spot` you asked for. **Copy the real JSON shapes into
research.md** — the pretend-`az` must imitate these.

**A8. Try the gp2 storage setting.**

```bash
az aks get-credentials --resource-group "$RG" --name "$CLUSTER" --overwrite-existing
kubectl get nodes   # expect 3 nodes: 1 system + 2 persistent
kubectl apply -f infra/local/gp2-storageclass.yaml   # temporary; the real file comes later — edit the provisioner line to disk.csi.azure.com and skuName StandardSSD_LRS first
kubectl get storageclass gp2
```

Expect: a `gp2` storage class exists. Optional but recommended: create a tiny
test PVC and confirm it binds. **Delete that test PVC afterwards.**

**A9. Clean up.**

```bash
az group delete --name "$RG" --yes
az group show --name "MC_${RG}_${CLUSTER}_${LOCATION}" 2>/dev/null && echo "STILL THERE" || echo "gone"
# expect: "gone" — check ONLY this exact name; the subscription may hold
# other people's MC_ groups, which are none of our business
```

While the cluster exists (between A5 and A9), run the `az group show` above
once and record the exact auto-created name you predicted
(`MC_<rg>_<cluster>_<location>`) and what `az` actually created — they should
match; after A9 it must be gone.

**A10. Write it down.** Fill every checkbox in research.md → "Manual pass
findings": working command shapes, the chosen Kubernetes version, VM sizes
confirmed available, the real output fields from A7. Only now does script
writing start.

---

## Part B — checking the finished feature

### B1. Refusals, with no cloud needed

Edit `.env` so `STACK_MODE=aks` and the Azure settings are set, but do not
sign in (`az logout`). Then:

```bash
make setup-cluster
```

Expect: a plain message telling you to run `az login` first, and **nothing
created**. Repeat with a made-up subscription id and a made-up location —
each must refuse clearly before creating anything. Also set
`STACK_MODE=nonsense` — the message must name the three valid values.

### B2. The real run

Sign in (`az login`), put real values in `.env`, then:

```bash
make setup-cluster          # expect: resource group + cluster + 5 pools + gp2
make setup-cluster          # run again — expect: "already exists", nothing new
bash infra/scripts/cluster/verify-cluster-aks.sh
                            # expect: ✓ per pool, matching the table in plan.md
kubectl get namespaces      # expect: only the expected namespaces — the setup
                            # installs nothing beyond the cluster itself (FR-008)
```

That verify report is the acceptance evidence for SC-004. Keep it.

### B3. The no-cloud test (offline stand-in)

```bash
bash agent/tests/azure/run-offline-tests.sh
# runs every scenario from contracts/azure-cli-contract.md §2 and asserts:
#   - the actions taken, in order
#   - a second run creates nothing new
#   - each refusal message appears
#   - the partial-failure report names what was created and deletes nothing
```

Expect one `PASS` line per check and a final summary line, currently:

```text
offline tests: 85 checks, 0 failed
```

(The check count grows as checks are added; the gate is `0 failed`.)

### B4. Teardown and leave-nothing check

```bash
make cleanup-cluster        # expect: the generated folder deleted
make cleanup-cluster        # again — expect: "nothing to clean", exit 0
az group show --name "MC_<your-rg>_<your-cluster>_<location>" 2>/dev/null \
  && echo "STILL THERE" || echo "gone"   # expect: "gone" for OUR name only —
                                         # other people's MC_ groups must be left alone
```

### B5. Amazon untouched

`git diff` the branch: no file under `infra/eksctl.yaml`, eks/local scripts,
or `app/`/`monitoring`/`scenarios` may change. A person with Amazon access
runs `make setup` and `make cleanup` once and confirms behaviour is as before.

---

## Done when

- [x] Part A complete; research.md "Manual pass findings" filled in.
- [x] B1 refusals, B2 second-run no-op + verify report, B3 offline tests,
      B4 double cleanup all pass.
- [x] B5 diff shows zero Amazon/local file changes.
