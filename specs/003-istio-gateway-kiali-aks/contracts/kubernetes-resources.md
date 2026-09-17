# Kubernetes Resource Contract: Istio on AKS

## Namespaces

**istio-system**: Created by Helm (--create-namespace); holds control plane and gateway

## Helm Releases

| Release | Chart | Version | Namespace | Selector Labels | Purpose |
|---------|-------|---------|-----------|-----------------|---------|
| istio-base | istio/base | 1.17.2 | istio-system | N/A (cluster-scoped CRDs) | Cluster resource definitions |
| istiod | istio/istiod | 1.17.2 | istio-system | workload=o11y | Control plane pods |
| istio-ingressgateway | istio/gateway | 1.17.2 | istio-system | workload=app | Gateway pods (receives external traffic) |

## Pod Placement Contract (Constitution V)

**istiod pods**:
- Must tolerate taint: `o11y=true:NoSchedule`
- Must select node label: `workload=o11y`
- Rationale: Observability workloads scheduled on dedicated o11y node pool

**istio-ingressgateway pods**:
- Must tolerate no taints (or app workload taint if defined)
- Must select node label: `workload=app`
- Rationale: Ingress gateway is application-facing, shares app node pool

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
- Labels: project=sre-stack, environment=aks
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
- No Gateway or VirtualService CRDs in robot-shop namespace
- No project=sre-stack pods in istio-system

Query: `kubectl get all -n istio-system -l project=sre-stack` → empty result
