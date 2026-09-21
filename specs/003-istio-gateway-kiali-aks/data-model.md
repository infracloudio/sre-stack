# Data Model: Istio Gateway on AKS

## Entities & Configurations

### 1. Istio Control Plane (Namespace & Helm Release)

| Field | Value | Notes |
|-------|-------|-------|
| **Helm Release Name** | istio-base | Helm release for cluster-scoped resources |
| **Helm Release Name** | istiod | Helm release for control plane |
| **Namespace** | istio-system | Matches EKS/local |
| **Chart Version** | 1.30.4 | Pinned per-platform: AKS uses 1.30.4 (Istio 1.17.2 does not support Kubernetes 1.34, which story #97 pins for AKS — see research.md §1). EKS/local remain on 1.17.2, unchanged. |
| **Install Method** | helm upgrade --install | Idempotent (Principle I) |
| **Pod Placement** | AKS system node pool, via `nodeSelector` | Per R10 — the system pool carries no taint (`specs/001-azure-aks-setup/data-model.md:96`), but so does the app pool, so `setup-istio-aks.sh` sets an explicit `nodeSelector` (`kubernetes.azure.com/mode=system`) on this release; without it, pods were observed landing on the app pool instead |
| **Tracing Address** | zipkin.monitoring:9411 | This is EKS/local's existing value (makefile:77), unchanged there per R8. Open question, not resolved here: whether AKS's new `setup-istio-aks.sh` also passes this flag — see plan.md's Constitution Check, Principle II row. |
| **Pilot Trace Sampling** | 100% | Same open question as Tracing Address above — EKS/local's existing value, not yet decided for AKS |

**Relationships**: 
- istio-base provides CRD definitions for istiod
- istiod watches Gateway and VirtualService CRDs deployed in other namespaces
- istiod controls ingress-gateway Deployment via label selectors

**State**: Control plane is "Ready" when istiod pod reaches Running state with all containers ready

---

### 2. Istio Ingress Gateway (LoadBalancer Service & Deployment)

**Created by**: `setup-istio` (not `setup-gateway`). The `istio-ingressgateway` Helm release (which creates this Service) is installed by `setup-istio`'s third `helm upgrade --install` (makefile:78), not by `setup-gateway` (makefile:152, which only applies an app-specific route and does no Helm work). `get-service-endpoints` reads this Service directly (`kubectl get svc istio-ingressgateway`, makefile:43/45).

| Field | Value | Notes |
|-------|-------|-------|
| **Helm Release Name** | istio-ingressgateway | Helm release for gateway |
| **Namespace** | istio-system | Same as control plane |
| **Chart Version** | 1.30.4 | Same per-platform pin as istio-base/istiod above |
| **Service Type** | LoadBalancer | Acquires external IP from Azure LB |
| **Pod Placement** | AKS system node pool, via `nodeSelector` | Per R10, same reasoning as control plane above |
| **External IP** | Assigned by Azure | Format: 52.xxx.xxx.xxx. `LB_ENDPOINT` is a make variable, assigned at makefile file scope — never exported to the shell environment. |
| **Ports** | 80:HTTP | 443:HTTPS is future work, not part of this story |

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
| **Routing Rule** | Host: *, Path: / → web service | Current pattern (robot-shop only); this story creates no new VirtualServices (see spec.md R3) |
| **Future Routes** | /grafana (owned by story #101, via `monitoring/istio-observability-addons/` and `setup-istio-o11y-addons`), /kiali (owned by the observability story) | Out of scope for this story — listed here only so the reader knows where those routes come from |

**Relationships**:
- VirtualService references Gateway by name and gateways list
- istiod translates to Envoy config on ingress-gateway pods

**State**: Routes are "Ready" when Gateway and VirtualService CRDs are applied and istiod reports them as synced

---

### 4. Resource Tagging & Governance — removed

The `project=sre-stack` / `environment=aks` tagging convention in earlier drafts of this story has been dropped: `grep -rn "project=sre-stack" --include="*.yaml" --include="*.sh" --include="makefile" .` outside `specs/003-*` returns nothing, so there is no existing repo convention this was matching. See spec.md R5 for the current (tagging-free) requirement, based instead on cleanup command coverage.

---

## Validation Rules

- **Idempotency (R6)**: running setup-istio or setup-gateway twice must exit 0, validated via a `helm status`/release-exists check before installing — not by matching specific command-output strings, which don't match documented Helm 3 behavior on an unchanged release.
- **Resource Cleanup (R7)**: no system-managed pods (kube-dns/CoreDNS, etc.) run in `istio-system` — they're in `kube-system`. After `cleanup-gateway` and `cleanup-istio`, `kubectl get all -n istio-system` should return nothing at all (matching spec.md S6 and tasks.md T017).
- **External IP Assignment (R4, S2)**: S2 has no separate 2-minute budget — the LoadBalancer Service's IP acquisition is folded into S1's 5-minute budget for `setup-istio`, since `setup-gateway` does no work on AKS for this story (see spec.md R2).
- **Pod Readiness (S1)**: All istiod and ingress-gateway pods must reach Running state within 5 minutes.
- **Cross-cloud Consistency (R1, R2, R8)**: makefile target names and the check-then-create pattern match EKS/local; the Istio chart version is pinned per-platform (see R1) rather than byte-identical, because 1.17.2 cannot run on AKS's Kubernetes 1.34.
