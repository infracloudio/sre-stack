# Provider Interface Contract

## Overview

Each cloud provider backend (EKS, k3d, AKS) MUST implement a common interface for cluster provisioning and teardown. This contract ensures that Makefile-level commands (`make start-cluster`, `make cleanup`) work identically across providers, and that application/observability manifests remain portable.

---

## Provider Implementation Interface

Every provider MUST be backed by:

1. **Cluster provisioning script**: `infra/<provider>/cluster.sh`
2. **Node pool provisioning script**: `infra/<provider>/node-pools.sh`
3. **Storage class provisioning script**: `infra/<provider>/storage-class.sh` (AKS/EKS only; k3d is pre-configured)
4. **Cleanup script**: `infra/<provider>/cleanup.sh`

---

## Input Contract: `.env` Configuration

Each provider reads configuration exclusively from `.env` variables scoped to its provider. Makefile resolves `CLOUD_PROVIDER` and delegates to the appropriate provider scripts.

### EKS Provider

**Required `.env` Variables**:
```bash
AWS_REGION                         # AWS region (e.g., us-west-2)
CLUSTER_NAME                       # EKS cluster name (e.g., sre-stack)
```

**Optional/Derived**:
- IAM roles, VPC settings, security groups (managed by eksctl from `infra/eksctl.yaml`)
- Kubernetes version (from `infra/eksctl.yaml`)

---

### Local (k3d) Provider

**Required `.env` Variables**:
```bash
LOCAL_NODES                        # Number of k3d nodes (e.g., 5)
LOCAL_APP_SETUP_TIMEOUT            # Timeout for app setup (e.g., 10m0s)
INOTIFY_MAX_USER_INSTANCES         # Linux inotify limit
INOTIFY_MAX_USER_WATCHES           # Linux inotify watch limit
```

**Notes**:
- k3d is single-region; no region configuration needed
- StorageClass: k3d comes with `local-path` provisioner pre-configured
- Taints/labels: Applied via k3d cluster config at creation time

---

### AKS Provider

**Required `.env` Variables**:
```bash
AZURE_SUBSCRIPTION_ID              # Azure subscription ID
AZURE_TENANT_ID                    # Azure tenant/directory ID
AZURE_RESOURCE_GROUP               # Resource group for cluster (e.g., sre-stack-aks)
AZURE_REGION                       # Azure region (e.g., eastus)
AZURE_CLUSTER_NAME                 # AKS cluster name (e.g., sre-stack)
AZURE_KUBERNETES_VERSION           # K8s version (e.g., 1.27)
```

**Authentication**:
- Scripts assume `az login` has been run or CI supplies managed identity/service principal via `AZURE_*` env vars
- Scripts MUST check `az account show` early and fail with clear error if not authenticated

---

## Output Contract: Cluster State & Kubeconfig

All providers MUST produce:

1. **Accessible kubeconfig**: Kubectl configured to access the cluster (via context or `.kube/config`)
2. **Four node pools** with fixed names and configuration:
   - `app` (or driver-specific equivalent)
   - `persistent` (or driver-specific equivalent)
   - `observability` (or driver-specific equivalent)
   - `loadgen` (or driver-specific equivalent)
3. **Node labels** (validated via `kubectl get nodes -L workload`):
   - `workload=app`
   - `workload=persistent`
   - `workload=o11y` (canonical abbreviation for observability)
   - `workload=loadgen`
4. **Node taints** (validated via `kubectl describe node <name>` → `Taints:` section):
   - app pool: no taint (or empty)
   - persistent pool: `persistent=true:NoSchedule`
   - observability pool: `o11y=true:NoSchedule`
   - loadgen pool: `loadgen=true:NoSchedule`
5. **StorageClass named `gp2`** (validated via `kubectl get storageclass | grep gp2`):
   - Provisioner: Cloud-specific (EBS CSI, k3d local-path via alias, Azure Disk CSI)
   - Reclaim policy: Delete
   - Can be marked as default or not (depends on provider; existing manifests use explicit `storageClassName: gp2`)

---

## Node Pool Specifications

All four node pools exist on every provider; compute sizing is normalized by vCPU/memory:

| Pool Name | Workload Label | Taint | Min Nodes | Max Nodes | Target Capacity (vCPU/Memory) |
|-----------|----------------|-------|-----------|-----------|-------------------------------|
| app | app | (none) | 3 | 6 | 2 vCPU / 4+ GB |
| persistent | persistent | persistent=true:NoSchedule | 2 | 2 | 4 vCPU / 16 GB |
| observability | o11y | o11y=true:NoSchedule | 2 | 3 | 4 vCPU / 16 GB |
| loadgen | loadgen | loadgen=true:NoSchedule | 1 | 1 | 4 vCPU / 8+ GB |

**Provider-Specific Instance Types** (all normalized to above capacities):

| Pool | EKS | k3d | AKS |
|------|-----|-----|-----|
| app | c6a.large (2 vCPU, 4 GB) | single worker | Standard_D2s_v5 (2 vCPU, 8 GB) |
| persistent | t3.xlarge (4 vCPU, 16 GB) | single worker | Standard_D4s_v5 (4 vCPU, 16 GB) |
| observability | t3.xlarge (4 vCPU, 16 GB) | single worker | Standard_D4s_v5 (4 vCPU, 16 GB) |
| loadgen | c5.xlarge (4 vCPU, 8 GB) | single worker | Standard_D4s_v5 (4 vCPU, 16 GB) |

---

## Idempotency Contract

**Definition**: Running a provisioning script twice in a row MUST produce the same result as running it once (no duplicate resources, no errors).

**Script Behavior**:

### Cluster Provisioning Script (`cluster.sh`)

```bash
# Pseudo-logic:
if cluster exists:
    echo "Cluster $CLUSTER_NAME already exists, skipping creation"
    exit 0
else:
    create cluster
    wait for cluster readiness
    exit 0
```

**Requirements**:
- Check cluster existence before creating
- Wait for cluster to report "ready" status
- Exit 0 on success or "already exists"
- Exit non-zero with clear error message on failure
- Do NOT fail if cluster partially exists

---

### Node Pool Provisioning Script (`node-pools.sh`)

```bash
# Pseudo-logic:
for each nodepool in [app, persistent, observability, loadgen]:
    if nodepool exists on cluster:
        echo "Node pool $nodepool already exists, skipping creation"
    else:
        create nodepool with labels, taints, size
        wait for nodepool readiness
    if nodepool creation failed and nodepool does not exist:
        exit non-zero with error
exit 0
```

**Requirements**:
- Check node pool existence before creating
- Tolerate partial provisioning (e.g., 2 of 4 pools created, then failure)
- Subsequent run MUST complete remaining pools without duplicating existing ones
- Exit 0 on success or "already exists"
- Exit non-zero if any pool fails AND does not exist

---

### Cleanup Script (`cleanup.sh`)

```bash
# Pseudo-logic:
if cluster exists:
    delete cluster (includes node pools, supporting resources)
    wait for deletion
    exit 0
else:
    echo "Cluster $CLUSTER_NAME does not exist, nothing to clean up"
    exit 0
```

**Requirements**:
- Check cluster existence; proceed only if it exists
- Delete cluster and ALL supporting resources scoped to it (node pools, managed disks, etc.)
- Wait for deletion to complete
- Exit 0 on success OR cluster did not exist
- Exit non-zero only if deletion fails on an existing cluster
- MUST leave zero billable resources behind

---

## Workload Portability Contract

Application, observability, and scenario manifests MUST NOT reference provider-specific details. Portable manifest patterns:

### Node Selection
```yaml
# Portable: works on all providers
nodeSelector:
  workload: app  # or: persistent, o11y, loadgen
tolerations:
  - key: persistent
    operator: Equal
    value: "true"
    effect: NoSchedule
```

### Storage
```yaml
# Portable: works on all providers (gp2 StorageClass exists everywhere)
spec:
  storageClassName: gp2
  resources:
    requests:
      storage: 10Gi
```

### Non-Portable (Anti-Pattern)
```yaml
# ❌ Non-portable: EKS-specific resource names
nodeSelector:
  karpenter.sh/provisioner: default
# ❌ Non-portable: AWS-specific storage class
spec:
  storageClassName: ebs-sc
# ❌ Non-portable: Direct cloud API references in pod specs
```

---

## Verification Checklist (for each provider)

After provisioning, the following assertions MUST hold:

```bash
# Cluster is accessible
kubectl cluster-info

# Four node pools exist
kubectl get nodes --show-labels | grep -E "workload=(app|persistent|o11y|loadgen)"

# Each node carries correct workload label
for pool in app persistent o11y loadgen; do
  kubectl get nodes -l workload=$pool | grep -q $pool
done

# Taints are present (except app pool, which has no taint)
kubectl describe node <persistent-node-name> | grep -E "persistent=true:NoSchedule"
kubectl describe node <o11y-node-name> | grep -E "o11y=true:NoSchedule"
kubectl describe node <loadgen-node-name> | grep -E "loadgen=true:NoSchedule"

# StorageClass gp2 exists
kubectl get storageclass | grep gp2

# Node pool sizes match min/max configuration
kubectl get nodes | wc -l  # Should match expected pool count

# Example portable workload deploys successfully
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  nodeSelector:
    workload: app
  containers:
    - name: nginx
      image: nginx:latest
EOF
kubectl wait --for=condition=ready pod/test-pod --timeout=60s
kubectl delete pod/test-pod
```

---

## Non-Scope Items (Out of This Story)

- Azure Key Vault integration
- Managed databases (RDS MySQL, DocumentDB, Azure Database)
- Application workloads (Robot Shop, HotROD)
- Observability deployments (Prometheus, Grafana, Loki, Tempo)
- Fault scenario deployments
- Istio/service mesh

These remain unchanged across providers and are deployed in subsequent Makefile targets (`make setup` → app/observability/scenarios).

---

## Breaking This Contract = Regression

Any change to node pool names, workload labels, taint specifications, or storage class alias MUST be communicated through a new story and requires:
- Coordinated manifest updates across app/, monitoring/, scenarios/
- Migration path for existing deployments
- Documentation update

The contract is the stability guarantee across provider backends.
