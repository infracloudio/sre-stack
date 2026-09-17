# Data Model: Istio Gateway on AKS

## Entities & Configurations

### 1. Istio Control Plane (Namespace & Helm Release)

| Field | Value | Notes |
|-------|-------|-------|
| **Helm Release Name** | istio-base | Helm release for cluster-scoped resources |
| **Helm Release Name** | istiod | Helm release for control plane |
| **Namespace** | istio-system | Matches EKS/local |
| **Chart Version** | 1.17.2 | Pinned, matches EKS/local |
| **Install Method** | helm upgrade --install | Idempotent (Principle I) |
| **Pod Placement** | workload=o11y label + o11y=true:NoSchedule taint toleration | Per Constitution V & R10 recommendation |
| **Resource Tags** | project=sre-stack, environment=aks | Per R5 |
| **Tracing Address** | zipkin.monitoring:9411 | From current setup-istio |
| **Pilot Trace Sampling** | 100% | From current setup-istio |

**Relationships**: 
- istio-base provides CRD definitions for istiod
- istiod watches Gateway and VirtualService CRDs deployed in other namespaces
- istiod controls ingress-gateway Deployment via label selectors

**State**: Control plane is "Ready" when istiod pod reaches Running state with all containers ready

---

### 2. Istio Ingress Gateway (LoadBalancer Service & Deployment)

| Field | Value | Notes |
|-------|-------|-------|
| **Helm Release Name** | istio-ingressgateway | Helm release for gateway |
| **Namespace** | istio-system | Same as control plane |
| **Chart Version** | 1.17.2 | Pinned, matches EKS/local |
| **Service Type** | LoadBalancer | Acquires external IP from Azure LB |
| **Pod Placement** | workload=app label, no taint | Per Constitution V & R10 recommendation |
| **Resource Tags** | project=sre-stack, environment=aks | Per R5 |
| **External IP** | Assigned by Azure | Format: 52.xxx.xxx.xxx (captured in LB_ENDPOINT env var) |
| **Ports** | 80:HTTP, 443:HTTPS | HTTP only for current spec |

**Relationships**:
- Service uses label selector `istio: ingressgateway` to route traffic to gateway Deployment
- istiod wires VirtualServices → Gateway → Service routing

**State**: Gateway is "Ready" when Service acquires external IP (accessible via `kubectl get svc`)

---

### 3. Gateway & VirtualService Resources (Istio CRDs)

| Field | Value | Notes |
|-------|-------|-------|
| **Resource Type** | networking.istio.io/v1alpha3/Gateway | Istio networking CRD |
| **Resource Type** | networking.istio.io/v1alpha3/VirtualService | Istio routing CRD |
| **Namespace** | robot-shop (or app namespace per APP_NS) | Deployed by app/robot-shop/Istio/gateway.yaml |
| **Gateway Name** | robotshop-gateway | From gateway.yaml |
| **Gateway Selector** | istio: ingressgateway | Binds to ingress-gateway pods |
| **Port** | 80 (HTTP) | From gateway.yaml |
| **Routing Rule** | Host: *, Path: / → web service | Current pattern (robot-shop only) |
| **Future Routes** | /grafana → grafana service (story #101), /kiali → kiali service | Spec scope includes routing but Kiali deployment is separate story |

**Relationships**:
- VirtualService references Gateway by name and gateways list
- istiod translates to Envoy config on ingress-gateway pods

**State**: Routes are "Ready" when Gateway and VirtualService CRDs are applied and istiod reports them as synced

---

### 4. Resource Tagging & Governance

**Applied to all resources (pods, services, deployments)**:
- `project=sre-stack`: Identifies this project's infrastructure
- `environment=aks`: Cloud target identifier
- These labels enable resource queries: `kubectl get all -l project=sre-stack,environment=aks`

---

## Validation Rules

- **Idempotency (R6)**: Running setup-istio or setup-gateway twice must exit 0 with no "Creating" output on second run. Validated via `helm status` check.
- **Resource Cleanup (R7)**: After cleanup-gateway and cleanup-istio, `kubectl get all -n istio-system` must not include user-created resources; system pods may remain.
- **External IP Assignment (R4, S2)**: LoadBalancer Service must acquire external IP within 2 minutes of creation.
- **Pod Readiness (S1)**: All istiod and ingress-gateway pods must reach Running state within 5 minutes.
- **Cross-cloud Consistency (R1, R2, R8)**: Helm values and Makefile targets for AKS must match EKS/local byte-for-byte (except cloud-specific labels).
