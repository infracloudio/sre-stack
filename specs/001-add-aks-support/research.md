# Phase 0 Research: Azure AKS Cluster Support

## Executive Summary

AKS cluster provisioning can be implemented using Azure CLI (`az aks create`, `az aks nodepool add`) within bash scripts, matching the existing Makefile-driven pattern. Node pools require explicit taint and label setup via `az aks nodepool add` flags or post-creation via `kubectl`. Storage class aliasing is achieved by deploying a custom StorageClass manifest post-cluster-creation. All findings align with the spec's idempotency and security requirements.

---

## Resolved Clarifications

### Q1: Infrastructure Provisioning Tool

**Decision**: Azure CLI (bash) + kubectl, no Terraform or ARM templates.

**Rationale**:
- Existing sre-stack uses Makefile + bash scripts for EKS provisioning (eksctl, no Terraform)
- Azure CLI is lightweight, works in CI/CD, and aligns with kubectl-based node inspection
- Spec requires all config in `.env`; inline CLI flags + `.env` values work well
- Idempotency handled in bash logic (check before create/delete)
- Azure CLI v2.87.0+ supports all required node pool and tainting operations

**Alternatives Considered**:
- ARM templates: overkill for a single cluster; would require separate template files outside `.env`
- Terraform: introduces new language/state; EKS path doesn't use it

**Implementation**: `infra/aks/cluster.sh` (creates cluster), `infra/aks/node-pools.sh` (creates four node pools with labels/taints), `infra/aks/storage-class.sh` (deploys gp2 alias), `infra/aks/cleanup.sh` (idempotent teardown).

---

### Q2: Node Pool Instance Type Mapping (EKS → Azure)

**EKS Current Configuration** (from `infra/eksctl.yaml`):

| Node Pool | EKS Type | vCPU | Memory | Spot | Taint |
|-----------|----------|------|--------|------|-------|
| app-ng | c6a.large | 2 | 4 GB | yes | (none) |
| persistent-ng | t3.xlarge | 4 | 16 GB | yes | persistent |
| observability-ng (o11y) | t3.xlarge | 4 | 16 GB | yes | o11y |
| loadgen-ng | c5.xlarge | 4 | 8 GB | yes | loadgen |

**Decision**: Map to Azure general-purpose SKUs using Spot VMs

**Azure VM Selection** (meets or exceeds vCPU/memory per FR-005):

| Node Pool | EKS Type | Azure SKU | vCPU | Memory | Spot | Notes |
|-----------|----------|-----------|------|--------|------|-------|
| app | c6a.large (2 vCPU, 4 GB) | Standard_D2s_v5 | 2 | 8 GB | yes | Cost-optimized; meets vCPU, exceeds memory |
| persistent | t3.xlarge (4 vCPU, 16 GB) | Standard_D4s_v5 | 4 | 16 GB | yes | Exact match |
| o11y | t3.xlarge (4 vCPU, 16 GB) | Standard_D4s_v5 | 4 | 16 GB | yes | Exact match |
| loadgen | c5.xlarge (4 vCPU, 8 GB) | Standard_D4s_v5 | 4 | 16 GB | yes | Meets vCPU; exceeds memory for headroom |

**Rationale for Dv5 series**:
- Modern general-purpose line (supports Gen 2, Trusted Launch)
- Widely available in Azure regions
- Spot pricing available
- Sustainable choice (not Av1 retired, not B-series discouraged for system pools)
- v5 more cost-efficient than v3

**Alternatives Considered**:
- Bs-series: Microsoft docs warn against for system/managed workloads; insufficient vCPU floor
- Dalsv6/v7: AMD-based, slightly cheaper but less common; v5 offers better regional availability

---

### Q3: Storage Class Configuration for `gp2` Alias

**Decision**: Deploy a custom StorageClass manifest post-cluster-creation that creates a Kubernetes StorageClass named `gp2`.

**Implementation**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: disk.csi.azure.com
parameters:
  type: Premium_LRS  # or StandardSSD_LRS for cost
  cachingmode: ReadOnly
reclaimPolicy: Delete
allowVolumeExpansion: true
```

**Rationale**:
- AKS CSI driver (disk.csi.azure.com) is installed by default
- Premium_LRS offers performance comparable to EKS gp3 (older EKS clusters often used gp2)
- Existing application manifests reference `gp2` StorageClass; aliasing preserves compatibility
- Can be created via `kubectl apply` in the provisioning script

**Alternatives Considered**:
- StandardSSD_LRS: cheaper, acceptable for non-critical workloads; chosen Premium_LRS for parity
- Managed_LRS: older CSI driver; gp2 pattern uses managed disks anyway

---

### Q4: Azure Cluster Networking & Resource Scoping

**Decision**: Minimal networking scope; cluster owns its resources via dedicated resource group.

**Configuration**:
- **Resource Group**: Dedicated per cluster (named in `.env`); contains cluster, node pools, managed resources
- **Virtual Network (VNet)**: AKS-managed (default); Makefile provisioning does not create explicit VNet
- **Subnet**: AKS-managed within VNet
- **Taints**: Applied per node pool at creation time via `az aks nodepool add --taints`
- **Workload Labels**: Applied per node pool at creation time via `az aks nodepool add --labels`

**Rationale**:
- Spec requirement: teardown must leave nothing behind; AKS-managed VNet/subnet is cleaned by resource group deletion
- Simplifies idempotency: resource group deletion is atomic
- Reduces script complexity; no separate VNet/NSG management

**Alternatives Considered**:
- Custom VNet + NSG: unnecessary for empty cluster; adds complexity without benefit for this story

---

### Q5: Kubernetes Version Alignment

**Decision**: Capture AKS Kubernetes version in `.env` as `AZURE_KUBERNETES_VERSION`; default to closest match to EKS version.

**Current EKS Version**: 1.27 (from `infra/eksctl.yaml`)

**AKS Target**: 1.27 or closest available in the selected region

**Rationale**:
- Constitution Principle II (Pinned Versions): K8s version must be explicit in `.env`
- Closest version available at implementation time; captured in `.env` for reproducibility
- `az aks create` command accepts `--kubernetes-version` flag

---

### Q6: Azure CLI Authentication & Credentials

**Decision**: Rely on existing authenticated `az` CLI session; no credential storage in `.env` or scripts.

**Flow**:
1. Scripts assume `az login` has been run or CI supplies `AZURE_*` env vars (managed identity, service principal)
2. Scripts check Azure auth status early; fail fast with clear error if not authenticated
3. `.env` holds only non-secret subscription, tenant, resource group, region values

**Rationale**:
- Spec FR-014: "MUST rely on authentication already established outside `.env`"
- Aligns with Constitution Principle IV (No Secrets in Git)
- Matches EKS pattern: AWS credentials from `~/.aws/` or `AWS_*` env vars, not `.env`

**Verification**: Provisioning script runs `az account show` as first step; errors if unauthenticated.

---

## Technical Dependencies

### Required Tools

| Tool | Version | Availability | Rationale |
|------|---------|--------------|-----------|
| azure-cli | ≥2.87.0 | Widely available; installed in CI | Node pool taints, labels, provisioning |
| kubectl | ≥1.27 | Already required for k3d path | Post-cluster verification, storage class |
| bash | ≥4.0 | Standard on Linux/macOS | Script execution (existing pattern) |

### Azure Quotas & Limits

- **vCPU quotas**: User must have sufficient quota for 4 D4s_v5 + 2 D2s_v5 in target region
- **Regional availability**: Dv5 series generally available; verify with `az vm list-skus --location <region>`
- **Spot availability**: Spot VM availability varies by region; fallback to on-demand in scripts if needed

---

## Design Decisions Summary

| Decision | Choice | Why | Risk/Mitigation |
|----------|--------|-----|-----------------|
| Provisioning tool | Azure CLI + bash | Lightweight, idempotent, aligns with Makefile pattern | Script complexity; mitigated by phased checks |
| VM SKU mapping | Standard_Dv5 series | Modern, widely available, Spot-capable, cost-effective | Regional availability; check at provisioning time |
| Storage aliasing | Custom StorageClass named `gp2` | Preserves manifest compatibility | K8s StorageClass names are global; collision possible with user-created classes (mitigate via docs) |
| Auth model | Pre-authenticated CLI session | Secure, no credentials in code | CI/CD must set up auth before provisioning script runs |
| Resource scoping | Dedicated resource group per cluster | Atomic deletion, idempotent cleanup | Non-granular access control; acceptable for demo/test clusters |

---

## No Further Clarifications Needed

All spec requirements resolved. Technical decisions align with Constitution principles. Ready for Phase 1 design.
