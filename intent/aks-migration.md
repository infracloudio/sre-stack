# Intent: Support dual-cloud deployment (AWS/EKS + Azure/AKS) for sre-stack

Author: Rijo John (AI platform engineer). Status: draft.

## Problem

The organization is standardizing on Azure, and this repository currently
provisions its entire stack only on AWS. The Kubernetes cluster is created with
eksctl on EKS, the MySQL database runs on RDS outside the cluster, CloudWatch
metrics are imported via YACE, and the supporting shell scripts, IAM policies,
and `.env` configuration all speak AWS CLI. To align with the platform
direction and support SRE practitioners testing on both cloud platforms, the
repo needs to support Azure/AKS as a first-class deployment option alongside
AWS.

Because this is a demo/lab project with no persisted data or production
workload, adding parallel cloud paths is feasible. The goal is stability and
repeatability for scenarios across both platforms, not production parity.

## Proposed outcome

The repository provisions the demo environment on both AWS/EKS and Azure/AKS:

- `make setup` / `make cleanup` work end-to-end with both clouds via a
  `CLOUD_PROVIDER` environment variable (aws | azure), keeping the documented
  lifecycle and target names unchanged.
- AWS path: EKS (eksctl), RDS MySQL, CloudWatch/YACE integration keep their
  current behavior and stay production-ready; the underlying scripts are
  reorganized (moved into `infra/aws/`, cluster scripts refactored to branch
  on `CLOUD_PROVIDER`) but no functional change is intended.
- Azure path: AKS (az CLI), Azure Database for MySQL Flexible Server, and
  Azure Monitor/Prometheus integration added alongside AWS.
- Both paths use the same check-then-create bash script pattern for databases,
  same workload-separation model (app / persistent / observability / loadgen
  node pools), and same `.env` configuration surface (with cloud-specific vars
  isolated).
- All four fault-injection scenarios (01–04) remain runnable on both clouds,
  including scenario-02 (RDS/Azure MySQL parameter changes) and scenario-03
  (multi-AZ node groups).
- The local k3d mode remains unchanged — it is cloud-neutral and serves as
  the fast feedback loop for both paths.
- When finished, both AWS and Azure code paths are active, tested, and stable
  for demo use. No code is deleted; AWS path is preserved.

## Affected users and systems

Users: SRE practitioners who run scenarios on AWS or Azure; the platform team
that maintains cloud provisioning scripts; contributors following the README
lifecycle.

Systems changed:
- `infra/` — New `azure/` subdirectory with AKS cluster config, Azure MySQL
  policies, and auto-scaling equivalents; AWS subdirectory `aws/` created for
  existing EKS/RDS/YACE config (refactored, not deleted).
- `infra/scripts/cluster/` — Refactored to branch on `$CLOUD_PROVIDER`; existing
  eksctl logic isolated, new `az` CLI logic for AKS added.
- `infra/scripts/dbs/` — New `mysql-azure/` scripts for Azure Database for MySQL
  alongside existing `rds/` scripts; both follow the same check-then-create pattern.
- `makefile` — Enhanced to accept `CLOUD_PROVIDER` flag; `setup-cluster`,
  `cleanup-cluster`, `setup-db`, `setup-monitoring`, and `get-service-endpoints`
  dispatch to cloud-specific targets (the existing hostname-vs-IP fork in
  `get-service-endpoints` gains an Azure branch alongside the AWS one).
- `.env` — Extended with cloud-specific variables (AWS_REGION, AZURE_SUBSCRIPTION,
  AZURE_RESOURCE_GROUP, etc.); shared vars (CLUSTER_NAME, MYSQL_PASSWORD)
  remain single-source-of-truth.
- `infra/chart-values/` — New `azure/` subdirectory with AKS-specific values
  (StorageClass names, node pool configs); AWS values unchanged.
- `scenarios/scenario-02/` — Enhanced to support both RDS and Azure MySQL
  parameter-group changes.
- CI/CD pipeline (new or extended) — needed to validate both cloud paths
  before merge; see open Question 15 below on scope and cost of this.

Systems unchanged: robot-shop Helm chart (core), Istio, hotrod, KEDA, load
generators, local k3d path, and all scenario inject/detect/RCA logic.

Systems pending decision: observability dashboards (the `rds` dashboard and
any others fed by RDS/CloudWatch metrics) depend on how Azure metrics reach
Prometheus/Grafana — see open Question 4. Until that's decided, whether these
dashboards stay unchanged, get re-pointed, or get retired for the Azure path
is unresolved.

## Constraints

- Timeline is weeks — one focused push to add Azure alongside AWS, not phased
  over months. Both paths must reach stable demo-ready state before completion.
  This estimate assumes CI validation is scoped to lint/plan checks rather than
  full dual-cloud provisioning on every run; see open Question 15.
- The README lifecycle contract (`make setup`, `make cleanup`, `make
  setup-local`, `get-service-endpoints`) keeps working unchanged; `CLOUD_PROVIDER`
  is the only new required variable.
- Version-pinning discipline is maintained: every Helm install and tool stays
  pinned across both clouds. Azure components follow the same values-file
  pattern as the existing `chart-values/`.
- `.env` remains the single configuration surface for all clouds. Cloud-specific
  variables (e.g., AZURE_SUBSCRIPTION) are clearly marked and isolated in
  documentation so local dev and CI can inject only what is needed.
- No new secrets in git. Credentials and passwords (both clouds) live in `.env`,
  never hardcoded. The existing `.env` pattern for AWS is extended to Azure;
  demo-quality passwords are acceptable but must be centralized.
- Workload-separation model is preserved on both clouds: app / persistent /
  observability / loadgen node pools on AKS; same isolation on EKS.
  On AKS, achieve separation via taints/tolerations and pod affinity; equivalent
  to EKS node selectors and labels.
- Dual-cloud maintenance is a first-class concern: scripts and configs must
  make branching on `CLOUD_PROVIDER` obvious and testable (e.g., explicit
  `if [ "$CLOUD_PROVIDER" = azure ]; then ... fi` blocks, not implicit fallback).

## Open questions

### Blocking (must decide before design)

1. **IaC tooling for AKS**: Plain `az` CLI bash scripts (matching existing repo
   style), or Terraform/Bicep? Decision affects script structure, CI/CD
   validation, and version-pinning discipline.

2. **Authentication and credential strategy**: How will Azure credentials (service
   principal secrets, subscription ID) be supplied to local scripts, CI/CD, and
   runtime workloads? Will `.env` hold service principal keys in plaintext
   (demo-acceptable), or will we use Managed Identity / Workload Identity?
   How does this integrate with the `make setup` target?

3. **Networking architecture for AKS**: Will the cluster and database be in the
   same vnet or require peering? Will Azure Database for MySQL use private
   endpoints or public IP + NSG rules? Does this affect KEDA scaling or load
   generator access? How does this compare to current EKS setup?

4. **Observability stack for Azure**: How will metrics from Azure Database for
   MySQL and AKS clusters reach Prometheus and Grafana? Will Azure Database
   expose Prometheus metrics directly, or will we use Azure Monitor Agent +
   custom exporter? Does Azure Monitor replace YACE or complement it?

5. **Workload-separation model details**: On AKS, how are the four node pools
   (app / persistent / observability / loadgen) defined? What taints/tolerations,
   pod affinity rules, and resource requests enforce separation? Should pools
   span multiple availability zones (multi-AZ for scenario-03 fault injection)?

### High priority (should close before implementation)

6. **Container registry strategy**: Will images come from Docker Hub, Azure
   Container Registry (ACR), or elsewhere? If ACR, does local dev and CI need
   identity-based pull access? Does this affect image availability or cost?

7. **AKS Kubernetes version target**: EKS is pinned at 1.27, which is no longer
   supported on AKS. What is the minimum supported version on AKS? Do Helm
   charts (robot-shop, KEDA, Istio, hotrod) require specific API versions?

8. **Node sizing for Azure cost parity**: Map c6a.large (app pool), t3.xlarge
   (observability pool), and c5.xlarge (loadgen pool) to Azure D/E/F-series VMs
   for similar hourly cost and performance. What is the cost baseline for EKS
   nodes, and should Azure match it?

9. **Spot instances on Azure**: EKS uses spot VMs for cost optimization. Should
   AKS also use Azure spot VMs (Standard_Dxs_v4 with spot billing), or on-demand
   for demo stability? How do spot VM interruptions affect scenario repeatability?

10. **Dashboard and metric enumeration**: List all Grafana dashboards used in
    demos (e.g., `rds`, `kubernetes-cluster`, `robot-shop-app`, others). For
    each, enumerate required metrics (names, cardinality, retention). This
    drives the observability and YACE-replacement decision.

### Secondary (can defer, but flag for design)

11. **StorageClass naming**: Charts reference `gp2` (EKS default); AKS provides
    `managed-csi`. Rename all references to `managed-csi`, or create a
    StorageClass alias so chart values stay unchanged?

12. **Scenario-02 success criteria**: Define what "parameter-group change" means
    for both RDS and Azure MySQL (e.g., deadlock injection, I/O throttle). How
    is the fault injected? How do logs/metrics prove it worked? What is the
    expected observable effect on load generators or app metrics?

13. **DocumentDB (AWS Mongo)**: The repo has create/destroy scripts for
    DocumentDB, but it is not wired into the makefile and robot-shop uses
    in-cluster MongoDB. Port to Cosmos DB for Mongo, or drop entirely?

14. **Team review and approval**: Who is on the review set for this intent, and
    is a merged PR the recorded approval?

15. **CI scope for dual-cloud validation**: Success criteria calls for both
    paths tested in CI before merge, which implies provisioning full EKS+AKS
    clusters and RDS+Azure MySQL instances per run. Is that the actual bar, or
    is CI limited to lint/plan/dry-run checks with full end-to-end runs done
    manually before merge? This materially affects the "weeks, not months"
    timeline and should be scoped explicitly rather than assumed.

## Decisions

Filled in as reviewers answer the open questions on PR #XX, across all three
tiers (blocking, high-priority, secondary). Each row is settled in the PR
thread, then consolidated here so this artifact carries decisions into the
Design stage (`spec.md` is written from this table, not from discussion
threads).

**Blocking decisions (must close before design):**

| # | Question | Decision | Decided by | Date |
|---|----------|----------|------------|------|
| 1 | IaC tooling: `az` CLI scripts vs Terraform/Bicep? | open | | |
| 2 | Authentication strategy: service principal creds in `.env`? | open | | |
| 3 | Networking: vnet/peering/private endpoints for Azure MySQL? | open | | |
| 4 | Observability: Azure Monitor integration, Prometheus export strategy? | open | | |
| 5 | Workload-separation model: node pools, taints, multi-AZ strategy? | open | | |

**High-priority decisions (before implementation):**

| # | Question | Decision | Decided by | Date |
|---|----------|----------|------------|------|
| 6 | Container registry: Docker Hub, ACR, or other? | open | | |
| 7 | AKS Kubernetes version (1.27 not supported, minimum?) | open | | |
| 8 | Node sizing: D/E/F-series mapping for cost parity with EKS? | open | | |
| 9 | Spot VMs on Azure or on-demand for demo stability? | open | | |
| 10 | Dashboard/metric enumeration: list all dashboards and their metrics | open | | |

**Secondary decisions (can defer to design phase):**

| # | Question | Decision | Decided by | Date |
|---|----------|----------|------------|------|
| 11 | StorageClass: rename to `managed-csi` or create alias? | open | | |
| 12 | Scenario-02 success criteria: fault injection method + observable effects? | open | | |
| 13 | DocumentDB: port to Cosmos DB or drop entirely? | open | | |
| 14 | Team review set + approval recording method? | open | | |
| 15 | CI scope: full-provision runs vs. lint/plan checks only? | open | | |

## What success looks like

### AWS Path (existing, must remain stable)
- A machine with AWS CLI, eksctl, and kubectl configured:
  `make setup CLOUD_PROVIDER=aws` completes successfully
  - EKS cluster created with four node pools, CloudWatch metrics flowing via YACE
  - RDS MySQL instance created, accessible to cluster
  - robot-shop Helm chart deployed, all endpoints responding
  - All Grafana dashboards (rds, kubernetes-cluster, robot-shop-app) display live data
  - All scenarios 01–04 inject → detect → RCA → mitigate successfully
  - `make cleanup CLOUD_PROVIDER=aws` removes all AWS resources without leftovers
  - Logs show no errors or warnings during setup/cleanup

### Azure Path (new, must reach stability)
- A machine with Azure CLI, kubectl, and the prerequisites installed:
  `make setup CLOUD_PROVIDER=azure` completes successfully
  - AKS cluster created with four node pools, matching workload separation
  - Azure Database for MySQL instance created, accessible to cluster
  - robot-shop Helm chart deployed, all endpoints responding
  - All Grafana dashboards display live data, pending Question 4's resolution —
    dashboards fed by RDS/CloudWatch metrics either display equivalent Azure
    data, or are explicitly re-pointed/retired per the Q4 decision
  - All scenarios 01–04 inject → detect → RCA → mitigate successfully on Azure
  - `make cleanup CLOUD_PROVIDER=azure` removes all Azure resources without leftovers
  - Logs show no errors or warnings during setup/cleanup

### Dual-Cloud Requirements
- `make setup-local` works unchanged (k3d mode, cloud-agnostic)
- `get-service-endpoints` returns correct hostnames/IPs for the chosen cloud
- `.env` contains both AWS and Azure variables; scripts branch on `CLOUD_PROVIDER`
  without silent fallbacks
- No hardcoded cloud assumptions in scripts or charts (except intentional cloud-specific
  logic that is clearly marked)
- Both paths validated before merge (CI scope — lint/plan checks vs. full
  `make setup`/scenario provisioning — is Question 15, still open)
- Repo state on main branch: both AWS and Azure code paths active and passing tests
