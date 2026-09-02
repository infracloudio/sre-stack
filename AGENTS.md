# AGENTS.md — sre-stack agent context

Read this first. Keep it under one page; stale or padded content burns session
context. When an agent makes the same mistake twice, the correction goes here.

## What this repo is

Provisions demo microservice apps (robot-shop, hotrod) plus a full
observability stack (Prometheus/Grafana/Loki/Tempo/Beyla/Caretta) onto AWS EKS
or a local k3d cluster, and provides fault-injection scenarios for SRE
practice. It is glue code: YAML (Helm charts, Kubernetes manifests) plus bash
scripts. There is no application source code here — the apps come from
upstream images (instana/robot-shop, jaegertracing hotrod).

## Layout

- `makefile` — central orchestration; every lifecycle action runs through it
- `.env` — single configuration surface, sourced by makefile and all scripts
- `infra/` — cluster provisioning: eksctl config, IAM policies, k8s manifests,
  `scripts/cluster/` and `scripts/dbs/rds/` (idempotent check-then-create bash)
- `app/robot-shop/helm/` — the app chart (43 templates); `stack_mode`
  (eks|local) switches external RDS vs in-cluster MySQL
- `app/hotrod/` — kustomize-based tracing demo
- `monitoring/` — chart values per tool, dashboards (ConfigMaps labeled
  `grafana_dashboard: "1"`), Beyla manifests, Grafana Postgres backend,
  Istio addons (Kiali)
- `scenarios/` — fault injection: scenario-01 (API/probe faults),
  scenario-02 (RDS connections), scenario-03 (AZ down, doc only),
  scenario-04 (RabbitMQ overload); `load-gen/` baseline traffic
- `etc/` — diagrams, leftover Litmus configs
- `intent/` — SDLC artifact chain starts here (`intent.md` per change)
- `agent/` — policies (source of truth), hooks (deterministic checks),
  `HARNESS-CONFORMANCE.md` + `tests/` (per-harness probe verification)

## Commands

- `make setup` — full EKS deploy; `make setup-local` — full k3d deploy
- `make cleanup` / `make cleanup-local` — teardown
- `make get-service-endpoints` — print app/Grafana/Kiali URLs
- `make lint` — validate the whole repo (secrets scan, protected paths,
  shellcheck, yamllint, helm lint). Run before reporting any task complete.
- `make hooks` — enable the pre-commit git hooks for this clone
- YAML-dominant repo: prefer editing manifests/scripts over adding tooling

## Conventions

- Every Helm install is version-pinned and configured via a values file in
  `*/chart-values/`, never inline `--set` chains (except one-off host wiring)
- Shell scripts follow the check-then-create idempotent pattern: resolve repo
  root, source `.env`, check existence, create only if missing
- Node separation by labels/taints: `workload=app|persistent|o11y|loadgen`;
  new workloads must declare a nodeSelector (and tolerate taints where needed)
- StorageClass is `gp2` today (EBS CSI on EKS, aliased locally on k3d)
- Secrets come from `.env`, never hardcoded in scripts or manifests

## Rules for agents

- Start changes from an `intent/` artifact; don't invent scope
- Azure/AKS facts: query the Microsoft Learn MCP server (`.mcp.json`) rather
  than answering from memory — versions and APIs drift
- Only MCP servers listed in `agent/policies/allowed-mcp-servers.md` are
  approved for use
- Verify your work: `make lint`, and `make setup-local` when the change
  affects charts or manifests. Report output, don't claim success
- Never weaken a check to make a task pass (tests, hooks, lint rules)

## Things agents get wrong

- `makefile` is lowercase, not `Makefile`
- The repo tracks `.env` deliberately (demo config with known demo
  credentials); do not "fix" this by deleting or gitignoring it
- scenario-02 scripts intentionally degrade RDS — do not "repair" them
- `values.yaml` at repo root is a stray file, not referenced by the makefile
