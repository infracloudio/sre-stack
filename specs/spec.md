# Deploy Istio Ingress Gateway and Kiali to AKS

**Issue:** [#104](https://github.com/infracloudio/sre-stack/issues/104)  
**Depends on:** [#97](https://github.com/infracloudio/sre-stack/issues/97) (AKS cluster), [#101](https://github.com/infracloudio/sre-stack/issues/101) (Grafana on AKS)

## Problem

AKS runs no service mesh today. EKS and local k3d already run self-hosted Istio via Helm with a shared ingress-gateway LoadBalancer that routes `/grafana`, `/kiali`, and app traffic via path-based routing through `setup-istio` and `setup-gateway`. The observability spec ([#101](https://github.com/infracloudio/sre-stack/issues/101)/PR [#103](https://github.com/infracloudio/sre-stack/pull/103)) introduced an AKS-specific alternative—an AKS-managed mesh add-on plus the Kubernetes Gateway API—instead of reusing the existing pattern. This creates cloud inconsistency and blocks Kiali on AKS (Kiali reads telemetry directly from the mesh).

## Outcome

- Install Istio on AKS using the same method as EKS/local: self-hosted, open-source Istio via Helm with `setup-istio`
- Deploy the same shared Istio ingress gateway using `setup-gateway`'s pattern
- Deploy Kiali reading from the mesh
- `make get-service-endpoints` for AKS prints a single reachable load-balancer address with `/grafana` and `/kiali` routes—matching the shape EKS already has
- Kiali renders mesh topology (sparse until app workloads deploy in [#102](https://github.com/infracloudio/sre-stack/issues/102))

## Out of Scope

- AKS-native/managed service mesh add-ons or Kubernetes Gateway API (use self-hosted Istio for consistency)
- Demo application stacks (Robot Shop, HotROD) or their gateway routing ([#102](https://github.com/infracloudio/sre-stack/issues/102))
- Changes to EKS or local k3d Istio/gateway/Kiali setup
- Retroactive edits to [#101](https://github.com/infracloudio/sre-stack/issues/101)'s spec (handled separately as a review fix)

## Must Keep Working

- `make setup-aws` (Istio + gateway + Kiali on EKS) unchanged
- `make setup-local` (Istio + Kiali on local k3d) unchanged
- Existing `LB_ENDPOINT` and `get-service-endpoints` output for EKS/local unaffected

## Implementation

### Changes to Makefile / Setup Scripts

1. Add `setup-istio-aks` target that installs Istio to the AKS cluster using the same Helm pattern as the EKS setup
2. Add `setup-gateway-aks` target that deploys the ingress gateway with ingress rules for `/grafana` (route to Grafana service from [#101](https://github.com/infracloudio/sre-stack/issues/101)) and `/kiali` (route to Kiali)
3. Extend `get-service-endpoints` to detect and output the AKS LoadBalancer endpoint alongside EKS/local endpoints

### Helm Charts / Manifests

- Reuse existing `setup-istio` Helm values/chart for AKS (same versions, namespace, and configs)
- Reuse existing `setup-gateway` ingress-gateway manifests for AKS (same LoadBalancer spec, virtual-service patterns)
- Deploy Kiali as a separate release in the same namespace, pointing to the AKS mesh

### Testing

- Verify Istio control plane and data plane pods are running on AKS
- Verify ingress-gateway LoadBalancer service gets an external IP
- Verify `curl <LB_IP>/grafana` and `curl <LB_IP>/kiali` reach the respective services
- Verify Kiali dashboard loads and displays mesh topology
- Spot-check that `make setup-aws` and `make setup-local` remain unaffected

## Acceptance Criteria

- [ ] Istio installed on AKS cluster via `make setup-istio-aks`
- [ ] Istio ingress gateway deployed on AKS via `make setup-gateway-aks`
- [ ] Kiali deployed and reading telemetry from AKS mesh
- [ ] `make get-service-endpoints` outputs AKS LoadBalancer endpoint
- [ ] `/grafana` route works on AKS LoadBalancer
- [ ] `/kiali` route works on AKS LoadBalancer
- [ ] EKS and local k3d Istio/gateway/Kiali setup remains unchanged
- [ ] All existing `make` targets still pass
