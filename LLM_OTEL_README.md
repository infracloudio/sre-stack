# LLM Observability + OTel Migration

Three stages, each runnable independently via `make`.

## Stage 1 — Base stack (already exists, unchanged)

```bash
make setup-local
```

No changes made here. This is the repo's own existing target
(cluster → Istio → o11y stack → robot-shop → gateway).

## Stage 2 — Two-tier OTel Collector migration

```bash
make migrate-to-otel
```

Replaces the single-collector setup with an **agent** (DaemonSet, one per
node — tails pod logs, scrapes host/kubelet metrics) and a **gateway**
(Deployment — cluster-wide metrics/events/log export). Also:

- Patches the existing Prometheus to accept remote-write (no new metrics
  backend)
- Installs a modern Loki (existing `loki.yaml`'s Loki 2.6.1 has no OTLP
  support — see `LOKI-DECISION.md`) — also retires the crashing Promtail
  (issue #79)
- Adds a `zipkin` receiver to the existing Tempo config, closing a gap
  where Istio's tracing had nothing to actually talk to
- Enables Tempo persistence (previously had no writable volume at all —
  pre-existing gap, not introduced here) and corrects its readiness/
  liveness probe port to match where Tempo actually listens (3200, not
  the 3100 the existing config set)

Runs as: `setup-otel-patch-prometheus` → `setup-otel-loki` →
`setup-otel-tempo` → `setup-otel-gateway` → `setup-otel-agent`.

## Stage 3 — LLM observability demo

```bash
make setup-llm-observability
```

Deploys a demo chatbot app → LiteLLM Proxy → local Ollama model, fully
instrumented (tokens, cost, traces) via OpenTelemetry into the stack
Stage 2 just built. Zero code changes needed in any app that adopts this
pattern — LiteLLM does the instrumentation.

Runs as: `setup-llm-secrets` → `setup-llm-image` → `setup-llm-ollama` →
`setup-llm-litellm` → `setup-llm-app` → `setup-llm-dashboard`.

Then generate traffic and test resilience/security scenarios:

```bash
make run-llm-scenarios
```

**Known flaky behavior under heavy load:** the prompt-injection scenario
queries Tempo ~2 seconds after sending the request. On a laptop running
the full stack simultaneously (robot-shop + Istio + Prometheus + Grafana
+ Loki + Tempo + two OTel tiers + the LLM demo), model responses can take
several minutes under contention, and the trace may not be indexed yet
when the script checks. The underlying mechanism is proven correct (a
manual re-query after waiting longer reliably finds it) — this is a
timing/resource artifact of concurrent load, not a functional bug.

## Order matters

Stage 2 must run before Stage 3 (Stage 3 needs `svc/otel-gateway` to
exist). Stage 1 must already be up before Stage 2.

## Decisions recorded explicitly

- `LOKI-DECISION.md` — why the existing `loki.yaml` was left unchanged
  rather than fixed in place
- `YACE-DECISION.md` — why YACE is untouched (EKS-only, not relevant here)

## Everything here has been run end-to-end against a real k3d cluster

Every command in every target was proven working live, including several
real bugs found and fixed along the way: wrong OTel component names,
missing RBAC, a missing node toleration, the Loki OTLP gap, a missing
traces pipeline that silently dropped spans, Tempo having no writable
volume and a mismatched probe port, and a stale-vs-current secret value
mismatch between LiteLLM and the demo app after a mid-session secret
regeneration. Full details in each target's own comment in the `makefile`
and in each values file's header.
