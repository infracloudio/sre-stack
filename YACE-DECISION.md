# YACE Migration Decision

Your scope explicitly calls this out as a decision to make, not something to
silently pick -- so it's recorded here rather than baked silently into a
config file.

## The choice

- **Keep YACE** (yet-another-cloudwatch-exporter) as-is, OR
- **Replace it** with the collector's own `awscloudwatchreceiver`

## Recommendation: keep YACE

**Reasoning:**

1. **YACE is EKS-only in the upstream repo.** Looking at the actual
   makefile, `setup-yace` is only ever called from the EKS path
   (`setup: ... setup-yace ...` under `APP_STACK=robot-shop`/`all`), and is
   NOT part of `setup-local-o11y`. On a local/k3d cluster -- which is what
   scripts 01-03 in this migration target -- YACE isn't deployed at all,
   so there's nothing to migrate away from in this environment.

2. **When it IS relevant (EKS), YACE is simpler.** It's a single,
   purpose-built exporter with a small, well-understood config surface
   (one YAML listing which CloudWatch metrics to pull, per AWS service).
   `awscloudwatchreceiver` inside the collector is more "unified" -- one
   less moving part in the overall pipeline -- but its config is
   meaningfully heavier, and CloudWatch API rate limits/costs apply
   identically either way, so the unification doesn't reduce actual AWS
   API load.

3. **Migrating it isn't free.** YACE already emits standard Prometheus
   metrics that the existing Grafana dashboards likely reference by name.
   Switching receivers risks subtly different metric names/labels,
   silently breaking existing dashboards -- a real cost for a
   "unification" benefit that's mostly aesthetic (one collector instead
   of two exporters).

## When to revisit this

If/when this stack actually runs on EKS (not just local/k3d) and YACE
becomes relevant, revisit this decision then, with real EKS metrics and
dashboards to test the migration against -- don't decide it in the
abstract on a laptop.

## What this means for scripts 01-03

None of them touch YACE. If EKS mode is ever exercised
(`STACK_MODE=eks` in the upstream repo's `.env`), YACE continues to be
installed exactly as `setup-yace` already does today, unmodified.
