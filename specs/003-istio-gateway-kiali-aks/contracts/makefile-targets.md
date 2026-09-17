# Makefile Interface Contract: Istio & Gateway Setup

## Public Targets

### setup-istio
**Description**: Deploy Istio control plane (istiod) and cluster resources (base) to AKS
**Precondition**: AKS cluster must exist with node pools and workload labels/taints
**Postcondition**: istiod Deployment is Running in istio-system namespace; all pods ready
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 on second run with no resource creation
**Timeout**: Completes in under 5 minutes (per S1)
**Depends On**: STACK_MODE=aks, kubectl access to cluster
**Used By**: top-level `setup` target (verified real target exists at makefile:51-63, currently EKS/local-only; this story adds the AKS branch). Not gated on story #101 — this story's setup-istio has no dependency on Grafana, since it creates no routes to it (see spec.md R3).

### setup-gateway
**Description**: Deploy Istio ingress gateway and route rules (Gateway + VirtualService CRDs)
**Precondition**: setup-istio must have completed successfully
**Postcondition**: istio-ingressgateway Service acquires external LoadBalancer IP. This story applies no VirtualServices (see spec.md R3) — routes are added by later stories.
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 with no resource creation
**Timeout**: Completes in under 2 minutes (per S2); external IP assigned within this window
**Depends On**: STACK_MODE=aks, istio control plane running
**Used By**: top-level `setup` target (depends on setup-istio), `get-service-endpoints`
**Output**: Prints kubectl apply output; external IP is captured by `get-service-endpoints`

### destroy-istio-gateway (existing, EKS/local)
**Description**: Remove ingress gateway Deployment, Service, and route CRDs on EKS/local
**Verified**: exists today at makefile:196; wired into the real top-level `cleanup` target at makefile:226 (`cleanup: destroy-istio-gateway destroy-db-rds-mysql cleanup-cluster`, EKS path)
**Precondition**: None (safe to run even if gateway not deployed)
**Postcondition**: istio-ingressgateway Helm release uninstalled; no LoadBalancer service in istio-system
**Exit Code**: 0 on success or if gateway doesn't exist, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=eks (or local), helm CLI access
**Used By**: `cleanup` target (EKS/local path only, unchanged by this story)

### cleanup-istio, cleanup-gateway (new, AKS)
**Description**: AKS equivalents of `destroy-istio-gateway` — remove the Istio control plane and gateway respectively on AKS
**Open question, not yet resolved**: whether these are AKS-only new targets (leaving `destroy-istio-gateway` as the EKS/local-only path, two different names for the same job on different clouds) or whether the naming should be unified across all three platforms as a larger, separate cleanup. This story takes the narrower path — new AKS-only targets, `destroy-istio-gateway` untouched — since R8 requires the EKS/local target to stay byte-identical. Flagging this as a naming inconsistency worth a follow-up story, not solving it here.
**Precondition**: None (safe to run even if not deployed)
**Postcondition**: `cleanup-gateway`: no istio-ingressgateway Helm release or LoadBalancer Service. `cleanup-istio`: istio-system namespace exists but contains no istiod/istio-base pods.
**Exit Code**: 0 on success or if not deployed, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=aks, helm CLI access
**Used By**: `cleanup` target, AKS branch (new, added by this story)

### get-service-endpoints
**Description**: Print reachable load-balancer address and service URLs for the stack
**Precondition**: setup-gateway must have completed; LoadBalancer Service has external IP
**Postcondition**: Prints `LB_ENDPOINT=http://52.xxx.xxx.xxx:80` and service URLs
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
| MONITORING_NS | global | istiod Helm values (tracing zipkin address) | `monitoring` |
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
