# Intent: Add an Azure/AKS path alongside AWS/EKS in sre-stack

Author: Rijo John (AI platform engineer). Status: draft (revised 2026-09-03:
scope changed from *migrate* to *port* — see below).

## Problem

The organization is standardizing on Azure, and this repository currently
provisions its entire stack on AWS. The Kubernetes cluster is created with
eksctl on EKS, the MySQL database runs on RDS outside the cluster, CloudWatch
metrics are imported via YACE, and the supporting shell scripts, IAM policies,
and `.env` configuration all speak AWS CLI.

**Scope revision (2026-09-03):** the direction is no longer a clean cutover —
both AWS and AKS paths are being kept. The repo becomes a portable artifact
with *two* provisioned targets (EKS and AKS) plus the existing cloud-neutral
k3d local mode. Consequences that shaped this revision:

- Nothing is deleted. The EKS path, RDS scripts, and YACE integration stay as
  the reference implementation; the AKS path is a sibling, not a replacement.
- `stack_mode` grows from `eks | local` to `eks | aks | local`.
- New risks that did not exist under "migrate": double running cost (both
  stacks provisioned at once), config drift between the two paths, and
  version skew (EKS pinned at 1.27 vs a modern AKS version). Parity between
  paths becomes an acceptance criterion of its own.
- The upside: the same app + same observability stack provisioned on EKS,
  AKS, or k3d is a stronger SRE-training artifact than either alone, and it
  validates the claim that the repo's substance is cloud-neutral glue.

## Proposed outcome

The repository provisions the demo environment on both clouds:

- `make setup` / `make cleanup` keep working end to end with the same target
  names and the same ordering, so the documented lifecycle is unchanged; the
  cloud is selected the way `stack_mode` selects `eks`/`local` today.
- An AKS path is added as a sibling of the EKS path (cluster creation, node
  pools, storage, identity), following the same check-then-create bash script
  pattern as `infra/scripts/cluster/`.
- The AKS path uses Azure Database for MySQL Flexible Server, managed by a
  sibling of the RDS scripts, wired through the same
  `MYSQL_HOST` / `setup-db-rds-mysql` flow.
- An Azure Monitor metrics exporter (the YACE equivalent) feeds the same
  Grafana instance; the `rds` dashboard panels are re-pointed per cloud (see
  open question 6 findings).
- All four fault-injection scenarios remain runnable on each path, including
  scenario-02 (RDS parameter-group change on EKS; an equivalent against Azure
  MySQL on AKS) and scenario-03 (multi-AZ node groups on both clouds).
- Secrets move to Azure Key Vault for the AKS path, fetched at provision time
  with `az` CLI — see open question 9 for the identity model.
- The local k3d mode is untouched — it is already cloud-neutral and serves as
  the fast feedback loop.
- The EKS path keeps working exactly as it does today; the repo does *not*
  become AWS-free. Parity checks (both paths lintable, both deployable)
  replace the old "no active code path references AWS" success criterion.

## Affected users and systems

Users: SRE practitioners who run the scenarios; the platform team that
maintains the provisioning scripts; contributors following the README
lifecycle.

Systems changed:
- `infra/scripts/cluster/` — gains an `azure/` sibling (EKS files stay)
- `infra/scripts/dbs/rds/` — gains an Azure MySQL sibling (RDS files stay)
- `makefile` — cloud selection, `MYSQL_HOST` lookup, AKS setup/cleanup, the
  LB endpoint hostname-vs-IP fork, a new `make secrets` target
- `.env` — Azure non-secret config added; secret values become placeholders
  fetched from Key Vault (see open question 9); AWS entries unchanged
- `infra/chart-values/`, `infra/keda-policy/`, scenario-02 scripts — touched where
  they reference RDS or AWS-specific settings

Systems unchanged: the entire EKS path (`infra/eksctl.yaml`,
`asg-policy.json`, `yace-cloudwatch-policy.json`, `cluster-autoscale.yaml`,
RDS scripts), robot-shop Helm chart (except MySQL host and StorageClass
references), the full observability stack, Istio, hotrod, KEDA autoscaling,
load generators, the local k3d path, and all scenario logic outside
scenario-02's RDS scripts.

## Constraints

- Timeline is weeks, not months — a single focused push, not a phased
  rollout.
- The README lifecycle contract (`make setup`, `make cleanup`, `make
  setup-local`, `get-service-endpoints`) must keep working as documented.
- Version-pinning discipline is maintained on *both* paths: every Helm install
  and tool stays pinned, Azure components follow the same values-file pattern
  as the existing `chart-values/`, and per-cloud pins (K8s version, VM SKU,
  exporter versions) are recorded.
- `.env` remains the single configuration surface for the makefile and scripts.
- No new secrets in git: the existing plaintext RDS credentials in `.env` and
  the hardcoded password in `scenarios/scenario-02/scripts/kill-sleep-processes.sh`
  should not be carried into the Azure scripts as-is (demo-quality passwords
  are tolerated, but they should come from `.env`, not be hardcoded twice).
  On the AKS path the bar is higher — secrets come from Key Vault at
  provision time and `.env` holds only non-secret config (open question 9).
- Keep the workload-separation model (app / persistent / observability /
  loadgen node pools) that the EKS config, the k3d local setup, and now the
  AKS config all encode.
- Both provisioned paths stay deployable from one repo checkout; drift
  between them is caught by the parity checks, not by a demo failing live.

## Open questions

1. DocumentDB: the Mongo-compatible AWS database has create/destroy scripts
   but is not wired into the makefile (robot-shop uses in-cluster MongoDB —
   the `MONGO_URL` env vars in catalogue/user deployments are commented out,
   and nothing depends on DocumentDB). Dropping it costs nothing functionally;
   porting to Cosmos DB for MongoDB would only buy a "managed Mongo" demo
   angle that RDS has for MySQL. Keep both-cloud parity simple: drop?
2. IaC tooling for AKS: plain `az` CLI bash scripts (matching the existing
   repo style — eksctl config + check-then-create scripts port directly), or
   Terraform/Bicep (new tool, and would mean rewriting the EKS side too for
   parity)?
3. AKS Kubernetes version target: EKS is pinned at 1.27, which is no longer
   supported on AKS. With both paths kept, either bump EKS to match a modern
   AKS version or accept version skew. What version do we standardize on?
4. Spot instances: EKS node groups use spot VMs; do we use Azure spot VMs
   (same SKUs, ~60–70% off, 30-second eviction) for the same cost profile, or
   on-demand for stability in a demo?
5. StorageClass naming: the charts reference `gp2` (MySQL 1Gi from values,
   Redis 1Gi from values, RabbitMQ 2Gi **hardcoded in the template** — a
   bug-in-waiting). All three are RWO block storage → `managed-csi` on AKS;
   nothing needs Azure Files/Blob classes. With both clouds kept, the alias
   StorageClass strategy (define a class named `gp2` with
   `provisioner: disk.csi.azure.com`, as k3d local already does with
   `local-path`) is effectively required so one chart provisions on all three.
   Also: RabbitMQ's hardcoded `gp2` should move to values regardless.
6. YACE replacement decision — researched 2026-09-03: the `rds` dashboard is
   a thin veneer over YACE metric names (`aws_rds_*_average{dimension_...
   }`, 11 panels, YACE pulls 27 RDS metrics from CloudWatch on a 5-min cycle
   with tag-based discovery). Azure MySQL Flexible Server exposes a near-1:1
   metric set via Azure Monitor (`cpu_percent`, `memory_percent`,
   `total_connections`, `storage_io_*`, `cpu_credits_*`, plus MySQL-level
   extras like `slow_queries`). So: **re-point, don't retire** — add an
   Azure metrics exporter + new values file, and rewrite the panel queries.
   One functional loss: Azure gives `storage_io_percent`/counts, not
   per-read/write IOPS and seconds-latency like CloudWatch — the Read/Write
   IOPS and Latency panels need redesign, not rename.
7. Node sizing — researched 2026-09-03, cost-comparable mapping
   (list prices approximate, verify in Azure calculator):

   | Pool | AWS | Spec | Azure pick | Spec | ~$/hr (AWS → AZ) |
   |---|---|---|---|---|---|
   | app-ng | c6a.large | 2/4 AMD | `Standard_D2as_v5` | 2/8 AMD | $0.077 → $0.088 |
   | persistent-ng | t3.xlarge | 4/16 | `Standard_D4as_v5` | 4/16 AMD | $0.166 → $0.173 |
   | observability-ng | t3.xlarge | 4/16 | `Standard_D4as_v5` | 4/16 AMD | $0.166 → $0.173 |
   | loadgen-ng | c5.xlarge | 4/8 | `Standard_F4s_v2` | 4/8 Intel | $0.170 → $0.169 |

   Series logic: F ≈ c5/c6 (1:2), D ≈ t3 (1:4, AKS default), E ≈ r5 (1:8,
   only if o11y needs memory headroom). B4ms is the true t3 burstable analog
   but weakest disk/network — D4as_v5 safer. Recommendation: standardize on
   DAs_v5 family + F4s_v2. Decide: accept these, or re-pick?
8. Team review: who is on the review set for this intent, and is a PR on this
   file the recorded approval?
9. Secrets & identity on the AKS path (proposed 2026-09-03):
   - Storage: one Key Vault (RBAC authorization, not access policies);
     `.env` keeps only non-secret config (region, resource group, vault
     name); a new idempotent `make secrets` target fetches values with
     `az keyvault secret show` at provision time — real secrets never touch
     git. This lets `.env` stop carrying real secrets entirely (today it is
     tracked deliberately with demo creds).
   - Identity, by caller location: humans → `az login` (Entra user + RBAC);
     CI (GitHub Actions) → workload identity federation (OIDC, four
     non-secrets in repo settings, no client secret); AKS pods → Workload
     Identity (the AKS twin of YACE's IAM-role pattern, e.g. the MySQL
     password delivered to the pod via Secrets Store CSI driver); classic
     registered service principal with client secret is fallback only.
   - Entra-only ambition: full Entra-only is achievable for the whole
     *control plane* (provisioning, vault, AKS admin via
     `disableLocalAccounts: true` + Azure RBAC for Kubernetes, Grafana
     OAuth). The blocker is the fixed upstream robot-shop images: catalogue/
     user connect to MySQL with `user:password` and can't do the Entra token
     flow without forking the app. So app DB logins stay password-based but
     vault-stored and injected via workload identity.
10. Dual-cloud parity acceptance criteria: who verifies the AKS path
    end-to-end (all four scenarios, `make cleanup` with no leftovers), and
    what is the drift-prevention mechanism (CI helm-template matrix for both
    `stack_mode` values? a parity checklist in the PR template?).
11. Cost/drift discipline with two live stacks: is running both EKS and AKS
    simultaneously ever intended (side-by-side demo), or always one at a
    time? This decides whether the makefile needs "which cloud is live"
    awareness and teardown discipline.

## Decisions

Filled in as reviewers answer the open questions on PR #93. Each row is
settled in the PR thread that discusses it, then consolidated here so the
artifact carries the decisions into the Design stage (`spec.md` is written
from this file, not from the discussion).

| # | Question | Decision | Decided by | Date |
|---|----------|----------|------------|------|
| 1 | DocumentDB: port to Cosmos DB or drop? | open | | |
| 2 | IaC tooling: az CLI scripts vs Terraform/Bicep? | open | | |
| 3 | AKS Kubernetes version target (vs EKS 1.27) | open | | |
| 4 | Spot VMs vs on-demand for node pools | open | | |
| 5 | StorageClass: `gp2` alias + un-hardcode RabbitMQ | open | | |
| 6 | YACE replacement vs retire the `rds` dashboard | open | | |
| 7 | Azure node-size mapping (D2as_v5 / D4as_v5 / F4s_v2) | open | | |
| 8 | Review set + approval recording | open | | |
| 9 | Key Vault + Entra identity model | open | | |
| 10 | Dual-cloud parity acceptance criteria | open | | |
| 11 | Both stacks live simultaneously or one at a time? | open | | |

## What success looks like

A fresh Azure subscription and a machine with the prerequisites installed:
`make setup` completes on the AKS path, the robot-shop endpoints and all
dashboards come up, scenarios 01 through 04 run their inject → detect → RCA
→ mitigate loop, and `make cleanup` removes everything without leftovers.
The EKS path still works exactly as it does today, and the local k3d mode is
unchanged. Parity between the EKS and AKS paths is explicit: both lint in
CI, and any scenario runnable on one is runnable (or explicitly tagged
cloud-only) on the other.
