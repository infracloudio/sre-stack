# Makefile Interface Contract: Istio & Gateway Setup

## Public Targets

### setup-istio
**Description**: Deploy Istio control plane (istio-base, istiod) AND the ingress gateway (istio/gateway chart) to AKS — three Helm installs in sequence, matching EKS exactly. On EKS, all three charts are installed by this same target (verified: `sed -n '74,90p' makefile`); the gateway is not a separate concern from `setup-istio`, it's part of the same Helm sequence.
**Precondition**: AKS cluster must exist with node pools (per R10, no taint tolerance needed since the system pool is untainted; placement itself is enforced by an explicit `nodeSelector` in `setup-istio-aks.sh`, not by default scheduling — see kubernetes-resources.md's Pod Placement Contract)
**Postcondition**: istiod and gateway Deployments Running in istio-system namespace; `istio-ingressgateway` Service has (or is acquiring) an external IP
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 on second run with no resource creation
**Timeout**: Completes in under 5 minutes (per S1, which now covers the gateway's LoadBalancer acquisition too — see spec.md S2)
**Depends On**: STACK_MODE=aks, kubectl access to cluster
**Used By**: the real `setup-istio` target has no `STACK_MODE` guard today (verified: `sed -n '74,90p' makefile`) — it runs the same 1.17.2 Helm installs regardless of `STACK_MODE`. This story adds the first `STACK_MODE` branching this target has ever had. It is not wired into the top-level `setup` target on AKS (verified: `sed -n '48,63p' makefile`: `STACK_MODE=aks`'s `setup:` only calls `setup-cluster`); `setup-istio` is invoked directly. Not gated on story #101 — this story's setup-istio has no dependency on Grafana, since it creates no routes to it (see spec.md R3).

### setup-gateway
**Description**: On EKS, applies an app-specific Gateway/VirtualService (`app/robot-shop/Istio/gateway.yaml`, makefile:152-154) — no Helm work, no LoadBalancer creation (that's `setup-istio`'s job, see above). On AKS for this story, a no-op: Robot Shop is out of scope (story #102), so there's nothing app-specific to apply yet. This is a standalone target fix, invoked directly, matching how `setup-istio` is also extended standalone.
**Precondition**: setup-istio must have completed successfully (so the gateway pods setup-gateway would route through, if it did anything, already exist)
**Postcondition**: On AKS (this story): none — no resources created. On EKS (unchanged): robot-shop namespace and its Gateway/VirtualService exist.
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 with no resource creation (trivially true for a no-op)
**Timeout**: Under a few seconds on AKS (no-op); not applicable to S1/S2 timing budgets, which are both covered by `setup-istio` (see spec.md S2)
**Depends On**: STACK_MODE=aks
**Used By**: not wired into the top-level `setup` target on AKS (verified: `sed -n '53,57p' makefile`: `STACK_MODE=aks`'s `setup:` only calls `setup-cluster`); `setup-gateway` is invoked directly/standalone. It does not feed `get-service-endpoints` on AKS (that reads the Service `setup-istio` created directly).
**Output**: Nothing on AKS for this story; logs a placeholder message noting story #102 will give this target real work

### destroy-istio-gateway (existing, EKS/local)
**Description**: The real target (makefile:196-201) only runs `helm uninstall istio-ingressgateway -n istio-system`, guarded by a check for whether the release exists. It removes the Helm release (which takes the Deployment and Service with it, since Helm owns them), but it does not separately touch any Gateway/VirtualService route CRDs — those are managed by `setup-gateway`'s `kubectl apply`, not by this target, and this target doesn't reverse that apply.
**Verified**: exists today at makefile:196; wired into the real top-level `cleanup` target at makefile:226 (`cleanup: destroy-istio-gateway destroy-db-rds-mysql cleanup-cluster`, EKS path)
**Precondition**: None (safe to run even if gateway not deployed)
**Postcondition**: istio-ingressgateway Helm release uninstalled; no LoadBalancer service in istio-system
**Exit Code**: 0 on success or if gateway doesn't exist, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=eks (or local), helm CLI access
**Used By**: `cleanup` target (EKS/local path only, unchanged by this story)

### cleanup-istio, cleanup-gateway (new, AKS)
**Description**: `cleanup-istio` mirrors what `setup-istio` actually installs — all three Helm releases (istio-ingressgateway, istiod, istio-base), since `setup-istio` is what owns the LoadBalancer on AKS for this story. `cleanup-gateway` mirrors `setup-gateway`'s no-op: there is nothing for it to remove. Both are AKS-only; for non-AKS `STACK_MODE`, EKS/local continue using the existing `destroy-istio-gateway` target unchanged — these new targets don't define a non-AKS behavior because they aren't called on other platforms.
**Open question, not yet resolved**: whether `destroy-istio-gateway` (EKS/local) and `cleanup-istio`/`cleanup-gateway` (AKS) should eventually be unified under one name across all three platforms. This story takes the narrower path — new AKS-only targets, `destroy-istio-gateway` untouched — since R8 requires the EKS/local target to stay byte-identical. Flagging this as a naming inconsistency worth a follow-up story, not solving it here.
**Precondition**: None (safe to run even if not deployed)
**Postcondition**: `cleanup-istio`: no istio-ingressgateway/istiod/istio-base Helm releases; no LoadBalancer Service; istio-system namespace exists but empty (no user-created pods, no system-managed pods either — nothing runs in `istio-system` besides what this story installs). `cleanup-gateway`: no-op, nothing to remove.
**Exit Code**: 0 on success or if not deployed, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=aks, helm CLI access (cleanup-istio only; cleanup-gateway needs neither, being a no-op)
**Used By**: not the top-level `cleanup` target. Verified (`sed -n '221,227p' makefile`): `STACK_MODE=aks`'s `cleanup:` only calls `cleanup-cluster`, with its own comment stating Azure cleanup is "the cluster lifecycle only (FR-004): no gateway, RDS, or other Amazon-only teardown steps run before it." `cleanup-istio`/`cleanup-gateway` are standalone targets, invoked directly. This story does not propose changing the composite `cleanup:` target's AKS branch.

### get-service-endpoints
**Description**: Print reachable load-balancer address and service URLs for the stack
**Precondition**: `setup-istio` must have completed (it creates the `istio-ingressgateway` Service) and that Service must have an external IP assigned. `setup-gateway` does nothing this target needs.
**Postcondition**: `get-service-endpoints` never prints `LB_ENDPOINT=...` in `NAME=value` form anywhere. Verified (`sed -n '169,190p' makefile`): `LB_ENDPOINT` is a make variable, computed once near the top of the makefile (makefile:43/45) as a bare IP/hostname with no scheme or port. The target interpolates it into full `http://$(LB_ENDPOINT)` URLs inside `@echo` lines (e.g. `Visit Robot shop http://$(LB_ENDPOINT)`) — it never echoes the variable by name.
**Exit Code**: 0 on success
**Idempotency**: Safe to run multiple times
**Depends On**: STACK_MODE=aks, kubectl access
**Environment Variables**:
  - **Reads**: APP_STACK (drives which URLs it echoes — `get-service-endpoints` itself branches only on `APP_STACK`; `STACK_MODE` only affects the separate file-scope `LB_ENDPOINT` assignment above it in the makefile, not this target directly), LB_ENDPOINT (computed from LoadBalancer Service external IP)
  - **Sets**: nothing. `LB_ENDPOINT` is set at makefile:43/45 (file scope, evaluated before any target runs), not by this target.
**Used By**: Top-level setup flow. The target branches on `APP_STACK`, not `STACK_MODE`. With `.env`'s default `APP_STACK=robot-shop`, it unconditionally echoes three lines — Robot Shop, `/grafana`, and `/kiali` URLs — regardless of which stories have actually deployed those routes. This story does not make `/grafana` or `/kiali` functional on AKS (see spec.md R3), so on a fresh AKS cluster with only this story's changes, two of those three printed URLs will not resolve to anything real yet. This is existing EKS/local behavior too (untouched, per R8) and is flagged here as a known UX gap, not something this story's scope covers fixing.

---

## Makefile Variables (Inputs)

| Variable | Scope | Used By | Example |
|----------|-------|---------|---------|
| STACK_MODE | global | `setup`, `cleanup` branch on it today. `setup-istio` and `setup-gateway` don't yet — see their own "Used By" entries above (no `STACK_MODE` guard exists on them until this story adds one) | `aks` (others: `eks`, `local`) |
| MONITORING_NS | global | The istiod tracing address (`zipkin.monitoring:9411`, makefile:77) is a hardcoded string, not `$(MONITORING_NS)` — the variable isn't actually referenced there, it just happens to match the default namespace name. Listed here only because a MONITORING_NS/zipkin address mismatch would be a real bug if the namespace were ever renamed. | `monitoring` |
| APP_NS | global | gateway.yaml application, VirtualService routes | `robot-shop` |
| CLUSTER_NAME | global | cluster metadata (future resource tags) | `sre-stack` |

---

## Shell Environment (Outputs)

| Variable | Set By | Used By | Format | Example |
|----------|--------|---------|--------|---------|
| LB_ENDPOINT | makefile top-level assignment (makefile:43/45, from `kubectl get svc`), evaluated on every `make` invocation regardless of target — not `get-service-endpoints` | `get-service-endpoints`'s `@echo` lines (which build `http://` URLs from it); manual curl | bare IP or hostname, no scheme, no port | `52.123.45.67` (AKS/local) or an ELB hostname (EKS) |

---

## Verification (make lint)

- No new lint errors in Makefile targets
- Targets are atomic and shell-safe (no unsafe variable expansion)
