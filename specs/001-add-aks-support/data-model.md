# Phase 1 Design: Data Model & Entities

## Entities & Data Structures

### 1. Cloud Provider Configuration

**Entity**: `CloudProvider`

**Fields**:
- `provider` (enum): `eks` | `local` | `aks`
- `region` (string): Cloud region or "local" for k3d
- `clusterName` (string): Cluster identifier
- `kubernetesVersion` (string): Pinned Kubernetes version

**In `.env` representation**:
```bash
# Provider selection
CLOUD_PROVIDER=eks|local|aks

# AWS / EKS
AWS_REGION=us-west-2
CLUSTER_NAME=sre-stack

# Azure / AKS
AZURE_SUBSCRIPTION_ID=<subscription-id>
AZURE_TENANT_ID=<tenant-id>
AZURE_RESOURCE_GROUP=sre-stack-aks
AZURE_REGION=eastus
AZURE_CLUSTER_NAME=sre-stack
AZURE_KUBERNETES_VERSION=1.27

# Local / k3d
LOCAL_NODES=5
```

**Validation Rules**:
- `CLOUD_PROVIDER` must be one of: `eks`, `local`, `aks`
- If `CLOUD_PROVIDER=aks`, all `AZURE_*` fields must be non-empty
- If `CLOUD_PROVIDER=eks`, all `AWS_*` fields must be non-empty
- If `CLOUD_PROVIDER=local`, `LOCAL_NODES` must be a positive integer
- `kubernetesVersion` must be a valid semantic version (e.g., "1.27", "1.28")

---

### 2. Kubernetes Node Pool

**Entity**: `NodePool`

**Fields**:
- `name` (string): Node pool identifier (e.g., "app", "persistent", "o11y", "loadgen")
- `instanceType` (string): Cloud provider VM/instance type (e.g., "c6a.large", "Standard_D4s_v5")
- `minSize` (integer): Minimum number of nodes
- `maxSize` (integer): Maximum number of nodes (for autoscaling)
- `workloadLabel` (string): Value for `workload=<label>` selector (e.g., "app", "persistent", "o11y", "loadgen")
- `taintKey` (string): Taint key (e.g., "app", "persistent", "o11y", "loadgen")
- `taintValue` (string): Taint value (typically "true" or node pool name)
- `taintEffect` (enum): `NoSchedule` | `PreferNoSchedule` | `NoExecute`
- `computeCapacity` (object): Normalized specs for comparison
  - `vCPU` (integer): Virtual CPU count
  - `memoryGB` (integer): RAM in gigabytes

**Example Instances**:

| Pool | name | workloadLabel | taintKey | taintValue | minSize | maxSize | EKS Type | Azure SKU |
|------|------|---------------|----------|-----------|---------|---------|----------|-----------|
| App | app | app | (none) | (none) | 3 | 6 | c6a.large | Standard_D2s_v5 |
| Persistent | persistent | persistent | persistent | true | 2 | 2 | t3.xlarge | Standard_D4s_v5 |
| Observability | observability | o11y | o11y | true | 2 | 3 | t3.xlarge | Standard_D4s_v5 |
| LoadGen | loadgen | loadgen | loadgen | true | 1 | 1 | c5.xlarge | Standard_D4s_v5 |

**Validation Rules**:
- `name` must be unique per cluster
- `workloadLabel` must match exactly: `app`, `persistent`, `o11y`, or `loadgen`
- `taintKey` must match `workloadLabel` (or empty if no taint)
- `minSize ≤ maxSize`
- `computeCapacity.vCPU` ≥ 2 for user pools, ≥ 2 for system pools
- `computeCapacity.memoryGB` ≥ 4 for user pools, ≥ 4 for system pools

---

### 3. Kubernetes Cluster

**Entity**: `KubernetesCluster`

**Fields**:
- `cloudProvider` (CloudProvider): Provider configuration
- `nodePools` (array of NodePool): Collection of node pools (always 4 for this story: app, persistent, o11y, loadgen)
- `storageClass` (string): Default storage class name; must be "gp2" for workload contract compliance
- `status` (enum): `not-provisioned` | `provisioning` | `ready` | `teardown-in-progress` | `error`

**State Transitions**:
- `not-provisioned` → `provisioning` (on `make start-cluster`)
- `provisioning` → `ready` (on successful cluster creation + node pool setup)
- `ready` → `teardown-in-progress` (on `make cleanup`)
- `teardown-in-progress` → `not-provisioned` (on successful resource deletion)
- Any state → `error` (on provisioning/teardown failure)

**Idempotency Rules**:
- Provisioning script must check cluster state before creating; if cluster exists with all four node pools, no action needed
- Teardown script must check resource existence before deletion; if no resource exists, exit cleanly
- Re-running provisioning after partial failure must complete without duplicating existing resources

---

### 4. Workload Placement Contract

**Entity**: `WorkloadPlacementContract`

**Fields**:
- `label` (string): Kubernetes node selector label (key=`workload`, value=one of: `app`, `persistent`, `o11y`, `loadgen`)
- `taint` (object): Kubernetes node taint (matching label)
  - `key` (string): Matches workload value
  - `value` (string): "true"
  - `effect` (string): "NoSchedule"
- `storageClassAlias` (string): "gp2" (ensures manifests written against EKS remain unchanged)

**Requirement**: Every AKS node pool MUST carry identical labeling, tainting, and storage class alias as the corresponding EKS node group, so that Kubernetes manifests (Pods, StatefulSets, PersistentVolumeClaims) deploy unchanged across providers.

**Validation**: `kubectl get nodes -L workload` and `kubectl get nodes --show-labels` must show workload label; `kubectl describe node <node>` must show matching taint; `kubectl get storageclass` must include `gp2`.

---

## Relationships & Dependencies

```
CloudProvider (provider selection)
    ↓
KubernetesCluster
    ├─ 4 × NodePool (app, persistent, o11y, loadgen)
    ├─ storageClass: "gp2"
    └─ Workload manifests depend on workload label + taint + storage class

WorkloadPlacementContract
    ├─ Read by application/observability/scenario manifests
    └─ Must be identical across EKS, k3d, AKS for manifest portability
```

---

## Scalability & Future Extensions

Current design is fixed for 4 node pools. Future enhancements (out of scope for this story):
- Parameterized node pool count
- Auto-scaling policies per pool
- Multiple clusters per region
- Azure Key Vault integration (separate story)
- Managed databases (separate story)

## Completeness Checklist

- [x] Cloud provider enum and configuration entity
- [x] Node pool entity with workload label, taint, compute specs
- [x] Cluster entity aggregating provider + pools + storage class
- [x] Workload placement contract for manifest portability
- [x] Validation rules for all entities
- [x] Idempotency rules for cluster state transitions
- [x] Storage class aliasing mechanism
