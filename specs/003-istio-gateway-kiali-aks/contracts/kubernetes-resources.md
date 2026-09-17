# Kubernetes Resource Contract: Istio on AKS

## Namespaces

**istio-system**: Created by Helm (--create-namespace); holds control plane and gateway

## Helm Releases

| Release | Chart | Version | Namespace | Selector Labels | Purpose |
|---------|-------|---------|-----------|-----------------|---------|
| istio-base | istio/base | 1.30.4 | istio-system | N/A (cluster-scoped CRDs) | Cluster resource definitions |
| istiod | istio/istiod | 1.30.4 | istio-system | none (system pool default) | Control plane pods |
| istio-ingressgateway | istio/gateway | 1.30.4 | istio-system | none (system pool default) | Gateway pods (receives external traffic) |

Version note: pinned to 1.30.4 rather than EKS/local's 1.17.2, because 1.17.2 does not support Kubernetes 1.34 (AKS's pinned version per story #97). See research.md §1 — 1.31.x may also be a valid choice pending Helm chart verification, unconfirmed as of this writing.

## Pod Placement Contract (per R10 / Constitution V)

**istiod pods**:
- Scheduled on the AKS system node pool (default scheduling; no toleration needed)
- Rationale: `specs/001-azure-aks-setup/data-model.md:99` shows the system pool carries no taint, unlike the four workload pools (app/persistent/o11y/loadgen). No custom Helm values required.

**istio-ingressgateway pods**:
- Same placement as istiod: AKS system node pool, no toleration needed

## CRDs & Validation

**CRD Versions**: All Istio resources use `networking.istio.io/v1alpha3`

**Gateway CRD** (app-deployed):
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: robotshop-gateway
  namespace: robot-shop  # APP_NS
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

**VirtualService CRD** (app-deployed):
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: robotshop
  namespace: robot-shop  # APP_NS
spec:
  hosts:
  - "*"
  gateways:
  - robotshop-gateway
  http:
  - route:
    - destination:
        host: web.robot-shop.svc.cluster.local
        port:
          number: 8080
```

## Service Contract

**LoadBalancer Service** (`istio-ingressgateway`):
- Type: LoadBalancer
- Namespace: istio-system
- Ports: 80:HTTP (443:HTTPS future)
- External IP: Assigned by Azure; becomes LB_ENDPOINT

**Query**:
```bash
kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Cleanup Expectations

After `cleanup-gateway` and `cleanup-istio`:
- istio-system namespace still exists (may contain system-managed pods)
- No Helm releases named istio-base, istiod, istio-ingressgateway
- No Gateway or VirtualService CRDs created by this story remain (this story creates none — see spec.md R3)

Query: `kubectl get all -n istio-system` → only pre-existing system-managed pods remain, if any
