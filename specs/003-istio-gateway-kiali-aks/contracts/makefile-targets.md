# Makefile Interface Contract: Istio & Gateway Setup

## Public Targets

### setup-istio
**Correction, this round**: verified directly against the real makefile (`sed -n '74,90p' makefile`) that on EKS, `setup-istio` installs **all three** Helm charts — `istio-base`, `istiod`, and `istio/gateway` — and it's the third one that creates the `istio-ingressgateway` LoadBalancer Service. The gateway is not a separate concern from "setup-istio"; it's part of the same Helm sequence. Earlier drafts of this contract (and of plan.md/tasks.md) assumed `setup-gateway` created the LoadBalancer — that was never true on EKS and this AKS story now matches EKS correctly instead of inventing a different split.

**Description**: Deploy Istio control plane (istio-base, istiod) AND the ingress gateway (istio/gateway chart) to AKS — three Helm installs in sequence, matching EKS exactly
**Precondition**: AKS cluster must exist with node pools and workload labels/taints
**Postcondition**: istiod and gateway Deployments Running in istio-system namespace; `istio-ingressgateway` Service has (or is acquiring) an external IP
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 on second run with no resource creation
**Timeout**: Completes in under 5 minutes (per S1, which now covers the gateway's LoadBalancer acquisition too — see spec.md S2)
**Depends On**: STACK_MODE=aks, kubectl access to cluster
**Used By**: top-level `setup` target (verified real target exists at makefile:51-63, currently EKS/local-only; this story adds the AKS branch). Not gated on story #101 — this story's setup-istio has no dependency on Grafana, since it creates no routes to it (see spec.md R3).

### setup-gateway
**Description**: On EKS, applies an app-specific Gateway/VirtualService (`app/robot-shop/Istio/gateway.yaml`, makefile:152-154) — no Helm work, no LoadBalancer creation (that's `setup-istio`'s job, see above). On AKS for this story, a **no-op**: Robot Shop is out of scope (story #102), so there's nothing app-specific to apply yet. Correction (independent audit): the composite `setup:` target under STACK_MODE=aks does not call `setup-gateway` at all today (verified: makefile:53-57 shows only `setup-cluster`) — an earlier draft's "so make setup doesn't break" rationale was false. This is a standalone target fix, invoked directly, matching how `setup-istio` is also extended standalone.
**Precondition**: setup-istio must have completed successfully (so the gateway pods setup-gateway would route through, if it did anything, already exist)
**Postcondition**: On AKS (this story): none — no resources created. On EKS (unchanged): robot-shop namespace and its Gateway/VirtualService exist.
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 with no resource creation (trivially true for a no-op)
**Timeout**: Under a few seconds on AKS (no-op); not applicable to S1/S2 timing budgets, which are now both covered by `setup-istio` (see spec.md S1/S2 correction this round)
**Depends On**: STACK_MODE=aks
**Used By**: top-level `setup` target (depends on setup-istio); does not feed `get-service-endpoints` on AKS (that reads the Service `setup-istio` created directly)
**Output**: Nothing on AKS for this story; logs a placeholder message noting story #102 will give this target real work

### destroy-istio-gateway (existing, EKS/local)
**Description**: Correction (independent audit): the real target (makefile:196-201) only runs `helm uninstall istio-ingressgateway -n istio-system`, guarded by a check for whether the release exists. It removes the Helm release (which takes the Deployment and Service with it, since Helm owns them), but it does not separately touch any Gateway/VirtualService route CRDs — those are managed by `setup-gateway`'s `kubectl apply`, not by this target, and this target doesn't reverse that apply.
**Verified**: exists today at makefile:196; wired into the real top-level `cleanup` target at makefile:226 (`cleanup: destroy-istio-gateway destroy-db-rds-mysql cleanup-cluster`, EKS path)
**Precondition**: None (safe to run even if gateway not deployed)
**Postcondition**: istio-ingressgateway Helm release uninstalled; no LoadBalancer service in istio-system
**Exit Code**: 0 on success or if gateway doesn't exist, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=eks (or local), helm CLI access
**Used By**: `cleanup` target (EKS/local path only, unchanged by this story)

### cleanup-istio, cleanup-gateway (new, AKS)
**Description**: `cleanup-istio` mirrors what `setup-istio` actually installs — all three Helm releases (istio-ingressgateway, istiod, istio-base), since `setup-istio` is what owns the LoadBalancer on AKS for this story. `cleanup-gateway` mirrors `setup-gateway`'s no-op: there is nothing for it to remove.
**Open question, not yet resolved**: whether these are AKS-only new targets (leaving `destroy-istio-gateway` as the EKS/local-only path, two different names for the same job on different clouds) or whether the naming should be unified across all three platforms as a larger, separate cleanup. This story takes the narrower path — new AKS-only targets, `destroy-istio-gateway` untouched — since R8 requires the EKS/local target to stay byte-identical. Flagging this as a naming inconsistency worth a follow-up story, not solving it here.
**Precondition**: None (safe to run even if not deployed)
**Postcondition**: `cleanup-istio`: no istio-ingressgateway/istiod/istio-base Helm releases; no LoadBalancer Service; istio-system namespace exists but contains no user-created pods. `cleanup-gateway`: no-op, nothing to remove.
**Exit Code**: 0 on success or if not deployed, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=aks, helm CLI access (cleanup-istio only; cleanup-gateway needs neither, being a no-op)
**Used By**: `cleanup` target, AKS branch (new, added by this story)

### get-service-endpoints
**Description**: Print reachable load-balancer address and service URLs for the stack
**Precondition**: setup-gateway must have completed; LoadBalancer Service has external IP
**Postcondition**: Correction (independent audit): `LB_ENDPOINT` itself is a bare IP/hostname, not `http://...:80` (verified: makefile:43/45). Prints `LB_ENDPOINT=52.xxx.xxx.xxx` internally; the target's own `@echo` lines build full `http://` URLs from it separately.
**Exit Code**: 0 on success
**Idempotency**: Safe to run multiple times
**Depends On**: STACK_MODE=aks, kubectl access
**Environment Variables**:
  - **Reads**: STACK_MODE, APP_STACK, LB_ENDPOINT (computed from LoadBalancer Service external IP)
  - **Sets**: LB_ENDPOINT (for downstream use)
**Used By**: Top-level setup flow. This story does not route to Grafana or Kiali (see spec.md R3) — `get-service-endpoints` prints the gateway address only; what's reachable through it depends on which later stories have run.

---

## Makefile Variables (Inputs)

| Variable | Scope | Used By | Example |
|----------|-------|---------|---------|
| STACK_MODE | global | setup, setup-istio, setup-gateway, cleanup | `aks` (others: `eks`, `local`) |
| MONITORING_NS | global | Correction (independent audit): the istiod tracing address (`zipkin.monitoring:9411`, makefile:77) is a hardcoded string, not `$(MONITORING_NS)` — the variable isn't actually referenced there, it just happens to match the default namespace name. Listed here only because a MONITORING_NS/zipkin address mismatch would be a real bug if the namespace were ever renamed. | `monitoring` |
| APP_NS | global | gateway.yaml application, VirtualService routes | `robot-shop` |
| CLUSTER_NAME | global | cluster metadata (future resource tags) | `sre-stack` |

---

## Shell Environment (Outputs)

| Variable | Set By | Used By | Format | Example |
|----------|--------|---------|--------|---------|
| LB_ENDPOINT | get-service-endpoints (from kubectl get svc) | Manual curl, downstream Grafana/Kiali routing | http://{external-ip}:{port} | http://52.123.45.67:80 |

---

## Verification (make lint)

- No new lint errors in Makefile targets
- Targets are atomic and shell-safe (no unsafe variable expansion)
