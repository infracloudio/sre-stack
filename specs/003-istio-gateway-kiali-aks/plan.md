# Implementation Plan: Istio Gateway on AKS

**Branch**: `003-istio-gateway-kiali-aks` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-istio-gateway-kiali-aks/spec.md`

## Summary

Deploy Istio on AKS using the same self-hosted, open-source pattern as EKS/local (not AKS-managed mesh). Install Istio control plane via Helm 1.17.2 to the o11y node pool, deploy ingress gateway to app pool, and expose a single LoadBalancer endpoint for `/grafana`, `/kiali`, and app routes via path-based VirtualServices. This restores consistency between clouds and unblocks Kiali deployment on AKS. Depends on story #97 (AKS cluster) and story #101 (Grafana).

## Technical Context

**Language/Version**: Bash/Makefile with Helm CLI (same as current `setup-istio` pattern)

**Primary Dependencies**:
- Helm 3.x
- kubectl (to apply gateway YAML and check readiness)
- Istio Helm charts (istio/base, istio/istiod, istio/gateway) at version 1.17.2 (matching current EKS/local)
- Azure CLI (for environment variable resolution, already in setup-cluster-aks.sh)

**Storage**: N/A (no persistent storage — Istio is control plane only)

**Testing**: kubectl readiness checks (`kubectl wait --for=condition=ready pod`)

**Target Platform**: Azure Kubernetes Service (AKS) — must match existing EKS/local behavior exactly

**Project Type**: Infrastructure/Kubernetes provisioning (make targets + deployment scripts)

**Performance Goals**: Control plane readiness in under 5 minutes (per S1); gateway LB address acquired in under 2 minutes (per S2)

**Constraints**: 
- Istio deployment must use Helm with pinned chart version (per Constitution II)
- All resources tagged `project=sre-stack` and `environment=aks` (per R5)
- Scripts must be re-runnable with idempotent behavior (per R6, Constitution I)
- No changes to EKS/local Istio/gateway configuration (byte-identical, per R8)

**Scale/Scope**: Single Istio control plane + one ingress gateway LoadBalancer service per AKS cluster

## Constitution Check

*GATE: Passed with documented pre-existing violations and R10 clarification*

**Principle II (Pinned Versions)**: ✓ No violation. Spec R1 requires "same chart version as EKS/local" (1.17.2), which is explicitly pinned.

**Principle I (Re-runnable)**: ✓ No violation. Current Makefile uses `helm upgrade --install`, which is idempotent.

**Principle III (One Configuration Surface)**: ⚠️ **Pre-existing issue, out of scope**. Istio version 1.17.2 is currently hardcoded in the Makefile (line 76-78), not in `.env`. However, R8 requires "EKS/local Istio/gateway setups remain byte-identical to main", so moving the version would violate R8. This violation is documented and remains in place.

**Principle II (Chart Values Files)**: ⚠️ **Pre-existing issue, out of scope**. Current setup uses inline `--set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100` instead of chart-values files. This is pre-existing in EKS/local and out of scope per R8 (byte-identical requirement).

**Principle V (Workload Placement)**: ✓ Clarified. R10 recommendation: Istio control plane (istiod) goes to o11y pool; ingress gateway goes to app pool (per Constitution V workload placement contract).

## Phase 0: Research

**Status**: Blocked on AKS cluster deployment (story #97 prerequisite)

**Findings**: See [research.md](research.md)

One finding completed (chart availability verified). Live cluster verification (pod readiness times, gateway IP assignment, resource scheduling, idempotency) deferred until story #97 completes and cluster is available.

## Phase 1: Design

**Completed Artifacts**:
- [data-model.md](data-model.md) — Istio control plane, ingress gateway, CRD configurations, pod placement rules
- [contracts/makefile-targets.md](contracts/makefile-targets.md) — Public Makefile interface (setup-istio, setup-gateway, cleanup targets)
- [contracts/kubernetes-resources.md](contracts/kubernetes-resources.md) — Kubernetes resource specs (namespaces, Helm releases, CRDs, pod placement)
- [quickstart.md](quickstart.md) — End-to-end validation scenarios for all success criteria (S1-S9)

## Project Structure

### Documentation (this feature)

```text
specs/003-istio-gateway-kiali-aks/
├── plan.md                          # This file
├── spec.md                          # Feature specification
├── research.md                      # Phase 0 findings (charts verified, cluster access blocked)
├── data-model.md                    # Phase 1: Istio entities, relationships, validation rules
├── quickstart.md                    # Phase 1: End-to-end validation scenarios
├── contracts/
│   ├── makefile-targets.md         # Phase 1: Makefile target signatures & dependencies
│   └── kubernetes-resources.md      # Phase 1: Kubernetes resource specs & placement
└── tasks.md                         # Phase 2 output (/speckit-tasks command - NOT yet created)
```

### Source Code (repository root)

**Makefile changes** (existing targets, AKS-specific branching to add):
- `setup-istio` — Extend conditional branching for STACK_MODE=aks
- `setup-gateway` — Extend conditional branching for STACK_MODE=aks
- `cleanup` — Extend to include AKS Istio/gateway cleanup
- `get-service-endpoints` — Extend to return LB_ENDPOINT for AKS

**No new source code files created.** This story extends existing Makefile targets and reuses:
- `app/robot-shop/Istio/gateway.yaml` — existing Gateway/VirtualService CRDs
- Istio Helm charts (istio/base, istio/istiod, istio/gateway) — no custom values files created per R8 byte-identical requirement

## Complexity Tracking

> **No Constitution violations requiring justification**

Pre-existing violations documented in Constitution Check are out of scope per R8 (byte-identical EKS/local requirement).
