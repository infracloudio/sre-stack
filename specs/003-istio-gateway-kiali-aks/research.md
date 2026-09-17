# Research: Istio Gateway on AKS

**Status**: Blocked on AKS cluster deployment (story #97 prerequisite)

## Finding 1: Chart Availability & Basic Verification

**Decision**: Istio 1.17.2 charts (base, istiod, gateway) are available in the istio Helm repository and all three required charts exist at the pinned version.

### What was verified

- `helm search repo istio/base --version 1.17.2` → returns chart 1.17.2 ✓
- `helm search repo istio/istiod --version 1.17.2` → returns chart 1.17.2 ✓  
- `helm search repo istio/gateway --version 1.17.2` → returns chart 1.17.2 ✓
- Gateway YAML file exists at `/Users/viknesh/sre-stack/app/robot-shop/Istio/gateway.yaml` ✓
- Makefile targets exist: `setup-istio` (line 74), `setup-gateway` (line 152), `destroy-istio-gateway` (line 196) ✓
- `infra/chart-values/` directory exists for placing values files ✓

### Blocker status

The AKS cluster is not currently deployed, so research findings requiring live cluster verification cannot be completed at this time. These will require story #97 (AKS cluster deployment) to be completed first.

**Live cluster verification needed** (gates implementation):
- Pod readiness times (istiod, ingress-gateway reaching Running state in <5 minutes)
- Gateway LoadBalancer IP acquisition time (<2 minutes)
- Resource scheduling to o11y/app node pools (validating Constitution V pod placement)
- Idempotency behavior on re-runs (helm upgrade --install no-op behavior)
- Cleanup completeness (no orphaned resources after delete)

### What this means

We can proceed with plan design using the validated Helm chart versions and existing EKS/local patterns. Live validation of deployment behavior, readiness times, and idempotency must happen when the cluster becomes available (gated as verification step before implementation in story #97 + 1).

---

## Deferred Research (Story #97 prerequisite)

Once the AKS cluster from story #97 is available, the following must be verified:

1. **Control plane readiness** (S1): Measure `make setup-istio` completion and all istiod pods Running state
2. **Gateway external IP assignment** (S2): Measure `make setup-gateway` to LoadBalancer IP acquisition
3. **Pod placement verification** (R10, V): Confirm istiod pods land on o11y nodes, gateway pods on app nodes
4. **Idempotency** (S4, S5): Run setup-istio and setup-gateway twice, measure second-run times
5. **Cleanup idempotency** (S6, S7): Run cleanup-gateway and cleanup-istio twice, verify no errors
