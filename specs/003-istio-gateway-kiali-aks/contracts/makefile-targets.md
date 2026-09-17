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
**Used By**: top-level `setup` target (when STACK_MODE=aks and story #101 Grafana is deployed)

### setup-gateway
**Description**: Deploy Istio ingress gateway and route rules (Gateway + VirtualService CRDs)
**Precondition**: setup-istio must have completed successfully
**Postcondition**: istio-ingressgateway Service acquires external LoadBalancer IP; VirtualServices are applied
**Exit Code**: 0 on success, 1 on failure
**Idempotency**: Running twice must exit 0 with no resource creation
**Timeout**: Completes in under 2 minutes (per S2); external IP assigned within this window
**Depends On**: STACK_MODE=aks, istio control plane running, APP_NS namespace exists
**Used By**: top-level `setup` target (depends on setup-istio), `get-service-endpoints`
**Output**: Prints kubectl apply output; external IP is captured by `get-service-endpoints`

### destroy-istio-gateway
**Description**: Remove ingress gateway Deployment, Service, and route CRDs
**Precondition**: None (safe to run even if gateway not deployed)
**Postcondition**: istio-ingressgateway Helm release uninstalled; no LoadBalancer service in istio-system
**Exit Code**: 0 on success or if gateway doesn't exist, 1 on error
**Idempotency**: Running twice must exit 0 without error messages (per R7)
**Depends On**: STACK_MODE=aks, helm CLI access
**Used By**: `cleanup` target (when STACK_MODE != aks)

### cleanup-istio (implicit, future)
**Description**: Remove Istio control plane (istiod, base) from AKS
**Precondition**: destroy-istio-gateway must have completed (no gateway pods)
**Postcondition**: istio-system namespace exists but contains no user-created pods
**Exit Code**: 0 on success or if Istio not deployed, 1 on error
**Idempotency**: Running twice must exit 0 (per R7)
**Depends On**: STACK_MODE=aks
**Used By**: `cleanup` target (when STACK_MODE=aks, future story)

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
**Used By**: Top-level setup flow, manual access to services (Grafana, Kiali, apps)

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
