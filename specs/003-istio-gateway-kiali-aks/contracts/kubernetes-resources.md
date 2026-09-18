# Kubernetes Resource Contract: Istio on AKS

## Namespaces

**istio-system**: Created by Helm (--create-namespace); holds control plane and gateway

## Helm Releases

| Release | Chart | Version | Namespace | Selector Labels | Purpose |
|---------|-------|---------|-----------|-----------------|---------|
| istio-base | istio/base | 1.30.4 | istio-system | N/A (cluster-scoped CRDs) | Cluster resource definitions |
| istiod | istio/istiod | 1.30.4 | istio-system | none (system pool default) | Control plane pods |
| istio-ingressgateway | istio/gateway | 1.30.4 | istio-system | none (system pool default) | Gateway pods (receives external traffic) |

Version note: pinned to 1.30.4 rather than EKS/local's 1.17.2, because 1.17.2 does not support Kubernetes 1.34 (AKS's pinned version per story #97). Correction (this was stale, fixed now): the 1.31.x question is resolved, not open — the Architect's real `helm search` (research.md §2) confirmed no 1.31.x chart is published yet, so 1.30.4 is the newest installable option, not a runner-up pending confirmation.

## Pod Placement Contract (per R10 / Constitution V)

**istiod pods**:
- Scheduled on the AKS system node pool (default scheduling; no toleration needed)
- Rationale: `specs/001-azure-aks-setup/data-model.md:96` (corrected from a wrong citation of line 99, which is actually the tainted o11y row — caught by independent audit, verified via `sed -n '96,99p'`) shows the system pool carries no taint, unlike the four workload pools (app/persistent/o11y/loadgen). No custom Helm values required.

**istio-ingressgateway pods**:
- Same placement as istiod: AKS system node pool, no toleration needed

## CRDs & Validation

**CRD Versions**: `networking.istio.io/v1alpha3` — confirmed for the existing `app/robot-shop/Istio/gateway.yaml` (verified: `grep -n apiVersion app/robot-shop/Istio/gateway.yaml`, real file, unchanged by this story per R8). Not checked against 1.30.4 specifically: current Istio documentation examples use `networking.istio.io/v1` for new Gateway/VirtualService resources. `v1alpha3` is still served by 1.30.4 as of this writing, so the existing file works, but this story creates no new CRDs (R3) — the question of which API version to use for *new* resources is out of scope here and belongs to whichever story adds routing.

**Gateway CRD** (app-deployed). **Correction (round-5 audit)**: the quoted blocks below previously included a `namespace: robot-shop  # APP_NS` line that does not exist in the real file — verified (`grep -n namespace app/robot-shop/Istio/gateway.yaml` returns no match). The real file has no `metadata.namespace` key at all; the namespace comes from `kubectl apply ... -n $(APP_NS)` at makefile:154, not from the manifest itself. Corrected to match the real file exactly:
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: robotshop-gateway
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

**VirtualService CRD** (app-deployed), same correction — no `namespace` key in the real file (set via `-n $(APP_NS)` at apply time instead):
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: robotshop
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
