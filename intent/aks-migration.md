# Intent: Migrate sre-stack from AWS/EKS to Azure/AKS

Author: Rijo John (AI platform engineer). Status: draft.

## Problem

The organization is standardizing on Azure, and this repository currently
provisions its entire stack on AWS. The Kubernetes cluster is created with
eksctl on EKS, the MySQL database runs on RDS outside the cluster, CloudWatch
metrics are imported via YACE, and the supporting shell scripts, IAM policies,
and `.env` configuration all speak AWS CLI. Continuing to maintain this repo
on AWS puts it out of step with the platform direction, and every new piece of
work has to bridge two clouds.

Because this is a demo/lab project, there is no persisted data or production
workload on AWS today, which makes a clean cutover possible: nothing needs to
be migrated in place, only rebuilt on the target platform.

## Proposed outcome

The repository provisions the identical demo environment on Azure AKS:

- `make setup` / `make cleanup` keep working end to end with the same target
  names and the same ordering, so the documented lifecycle is unchanged.
- The EKS path is replaced by an AKS path (cluster creation, node groups,
  storage, identity), replacing `infra/eksctl.yaml` and the eksctl-based
  scripts rather than adding a third mode alongside them.
- RDS MySQL is replaced by Azure Database for MySQL Flexible Server, managed
  by the same check-then-create bash script pattern, wired through the same
  `MYSQL_HOST` / `setup-db-rds-mysql` flow.
- The YACE/CloudWatch integration is replaced by an Azure Monitor equivalent
  (or dropped if the managed database exposes what the dashboards need), and
  the `rds` dashboard is re-pointed or retired accordingly.
- All four fault-injection scenarios remain runnable, including scenario-02,
  which needs an equivalent of the RDS parameter-group change on Azure MySQL,
  and scenario-03, which needs a multi-AZ node group on AKS.
- The local k3d mode is untouched — it is already cloud-neutral and serves as
  the fast feedback loop during the migration.
- When finished, no active code path in the repo references AWS
  (`grep -ri aws` returns hits only in git history and notes).

## Affected users and systems

Users: SRE practitioners who run the scenarios; the platform team that
maintains the provisioning scripts; contributors following the README
lifecycle.

Systems changed:
- `infra/eksctl.yaml`, `infra/asg-policy.json`, `infra/yace-cloudwatch-policy.json`,
  `infra/cluster-autoscale.yaml` — replaced with AKS equivalents
- `infra/scripts/cluster/` and `infra/scripts/dbs/rds/` — rewritten for az CLI
  and Azure Database for MySQL
- `makefile` — `MYSQL_HOST` lookup, `setup-yace`, `setup-db-rds-mysql`,
  `setup-cluster`/`cleanup-cluster`, and the LB endpoint hostname-vs-IP fork
- `.env` — AWS region/credentials/instance sizing replaced with Azure equivalents
- `infra/chart-values/`, `infra/keda-policy/`, scenario-02 scripts — touched where
  they reference RDS or AWS-specific settings

Systems unchanged: robot-shop Helm chart (except MySQL host and StorageClass
references), the full observability stack, Istio, hotrod, KEDA autoscaling,
load generators, the local k3d path, and all scenario logic outside
scenario-02's RDS scripts.

## Constraints

- Timeline is weeks, not months — a single focused migration push, not a
  phased dual-cloud period.
- The README lifecycle contract (`make setup`, `make cleanup`, `make
  setup-local`, `get-service-endpoints`) must keep working as documented.
- Version-pinning discipline is maintained: every Helm install and tool stays
  pinned, Azure components follow the same values-file pattern as the
  existing `chart-values/`.
- `.env` remains the single configuration surface for the makefile and scripts.
- No new secrets in git: the existing plaintext RDS credentials in `.env` and
  the hardcoded password in `scenarios/scenario-02/scripts/kill-sleep-processes.sh`
  should not be carried into the Azure scripts as-is (demo-quality passwords
  are tolerated, but they should come from `.env`, not be hardcoded twice).
- Keep the workload-separation model (app / persistent / observability /
  loadgen node pools) that both the EKS config and the k3d local setup encode.

## Open questions

1. DocumentDB: the Mongo-compatible AWS database has create/destroy scripts
   but is not wired into the makefile (robot-shop uses in-cluster MongoDB).
   Port to Cosmos DB for Mongo, or drop it from the repo entirely?
2. IaC tooling for AKS: plain `az` CLI bash scripts (matching the existing
   repo style), or Terraform/Bicep?
3. AKS Kubernetes version target: EKS is pinned at 1.27, which is no longer
   supported on AKS — what version do we standardize on?
4. Spot instances: EKS node groups use spot VMs; do we use Azure spot VMs for
   the same cost profile, or on-demand for stability in a demo?
5. StorageClass naming: the charts reference `gp2`; AKS provides
   `managed-csi`. Rename references, or create an alias StorageClass so chart
   values stay unchanged?
6. YACE replacement decision: does Azure Database for MySQL expose metrics in
   a form the `rds` dashboard can consume, or do we re-point/retire that
   dashboard?
7. Node sizing: Azure equivalents for c6a.large / t3.xlarge / c5.xlarge (likely
   D-series / E-series / F-series) — what is the cost-comparable mapping?
8. Team review: who is on the review set for this intent, and is a PR on this
   file the recorded approval?

## What success looks like

A fresh Azure subscription and a machine with the prerequisites installed:
`make setup` completes, the robot-shop endpoints and all dashboards come up,
scenarios 01 through 04 run their inject → detect → RCA → mitigate loop, and
`make cleanup` removes everything without leftovers. The repo references
Azure only, and the local k3d mode still works exactly as before.
