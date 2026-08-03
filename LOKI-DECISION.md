# Loki Upgrade Decision

Recorded explicitly rather than silently decided, same as `YACE-DECISION.md`.

## The situation

`monitoring/chart-values/loki.yaml` (existing, pre-dating this PR) installs
Loki via the deprecated `loki-stack` chart, pinned to Loki 2.6.1. Two real
problems with this, confirmed live against a k3d cluster:

1. **No OTLP log ingestion support at all.** That API was added in Loki
   3.0. A `POST` to `/otlp/v1/logs` returns a plain 404 — this isn't a
   config issue, the endpoint genuinely doesn't exist on that version.
2. **The bundled Promtail crashes on k3d** with `"too many open files"` —
   already tracked as issue #79, open since March 2024.

## The choice

- **Option A**: fix `loki.yaml` in place (upgrade the chart), closing
  issue #79 for the whole project, including the EKS path.
- **Option B**: add a separate `loki-otlp.yaml` + a new `setup-otel-loki`
  target that supersedes the `loki` release only when `migrate-to-otel`
  runs, leaving `loki.yaml`/`setup-loki` untouched.

## Decision: Option B

Chosen specifically because the blast radius of directly changing
`loki.yaml` couldn't be verified — there's no way to confirm from outside
the team whether the EKS path, existing dashboards, or alerting rules
depend on specifics of the current chart's behavior. Option B achieves
the same practical fix for the local/OTel-migrated path with zero risk to
anything else currently depending on `setup-loki`.

## What this means in practice

- `make setup-loki` (called by `setup-local-o11y`) still installs the old
  2.6.1 / Promtail setup, unchanged, exactly as it does today.
- `make migrate-to-otel` (specifically its `setup-otel-loki` target)
  uninstalls that `loki` release and reinstalls it fresh using
  `loki-otlp.yaml` (Loki 3.x, no bundled Promtail, real OTLP ingestion).
- After migration, the `loki` release name is the same, but its
  underlying chart/version has changed. `loki.yaml` itself is left in the
  repo with a header comment pointing here, so a future reader
  understands why it exists but is effectively superseded once migration
  has run.

## When to revisit

If/when someone with full visibility into the EKS path and any dashboards
depending on the current Loki setup confirms it's safe, Option A (a
direct in-place fix, closing issue #79 properly) is the better long-term
answer — this local-only superseding approach is a practical first step,
not the final state anyone should aim to leave this in indefinitely.
