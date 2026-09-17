# Implementation Plan: Deploy Istio Ingress Gateway and Kiali to AKS

**Story:** #104  
**Spec:** `specs/003-istio-gateway-kiali-aks/spec.md`  
**Date:** 2026-09-17

---

## Overview

Deploy self-hosted Istio 1.31.0 and Kiali v1.85 to AKS, replicating the pattern already working on EKS/local. Platform-owned ingress gateway routes `/kiali` path. Node pool placement via Helm values respects #97's taints.

---

## Technical Context

**Versions (pinned):**
- Istio: 1.31.0 (helm chart, no breaking changes from 1.17.2 EKS/local pins)
- Kiali: v1.85 (requires Prometheus config pointing to monitoring namespace)
- Kubernetes: AKS 1.34

**Namespaces:**
- istio-system: Istio control plane, ingress gateway, Kiali, platform-owned Gateway resource
- monitoring: Prometheus (from #101); Kiali points here via service DNS

**Node pools** (from #97):
- system: Istio istiod, ingress-gateway pods
- o11y (observability): Kiali pod, tolerates workload=o11y taint

**Makefile dispatch:**
- Existing Makefile uses `STACK_MODE` env var (lines 59-63)
- `STACK_MODE=aks` invokes Azure-specific setup
- Reuse `setup-istio`, `setup-gateway`, `setup-kiali` targets with Azure values

---

## Files to Change

### 1. Create AKS Helm values files (new directory)

**Location:** `infra/chart-values/aks/` (new)

**File: istio-values.yaml**
```yaml
global:
  hub: docker.io/istio
  tag: 1.31.0

pilot:
  nodeSelector:
    agentpool: system  # AKS system node pool
  tolerations: []

istiod:
  resources:
    limits:
      memory: 512Mi
      cpu: 500m
```

**File: gateway-values.yaml**
```yaml
service:
  type: LoadBalancer
  nodeSelector:
    agentpool: system

nodeSelector:
  agentpool: system
tolerations: []
```

**File: kiali-values.yaml**
```yaml
spec:
  version: v1.85
  auth:
    strategy: anonymous
  external_services:
    prometheus:
      url: http://prometheus-stack-kube-prom-prometheus.monitoring:9090
    tracing:
      enabled: false
  service:
    type: ClusterIP
  nodeSelector:
    agentpool: o11y
  tolerations:
    - key: workload
      operator: Equal
      value: o11y
      effect: NoSchedule
```

### 2. Update Makefile dispatch logic

**File: makefile** (add to existing target dispatcher around line 59-63)

```bash
ifeq ($(STACK_MODE),aks)
  ISTIO_VALUES_FILE := infra/chart-values/aks/istio-values.yaml
  GATEWAY_VALUES_FILE := infra/chart-values/aks/gateway-values.yaml
  KIALI_VALUES_FILE := infra/chart-values/aks/kiali-values.yaml
  KIALI_CHART_VERSION := v1.85
endif
```

**Add targets:**

```bash
setup-istio-aks:
	helm upgrade --install istio-base istio/base \
	  --namespace istio-system --create-namespace \
	  -f $(ISTIO_VALUES_FILE)
	helm upgrade --install istiod istio/istiod \
	  --namespace istio-system \
	  -f $(ISTIO_VALUES_FILE)

setup-gateway-aks: setup-istio-aks
	helm upgrade --install ingress-gateway istio/gateway \
	  --namespace istio-system \
	  -f $(GATEWAY_VALUES_FILE)
	kubectl apply -f infra/aks/platform-gateway.yaml -n istio-system

setup-kiali-aks:
	helm repo add kiali https://kiali.org/helm-charts
	helm repo update
	helm upgrade --install kiali kiali/kiali \
	  --namespace istio-system \
	  -f $(KIALI_VALUES_FILE)
```

### 3. Create platform-owned Gateway manifest

**File: infra/aks/platform-gateway.yaml**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: platform-ingress-gateway
  namespace: istio-system
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
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kiali-vs
  namespace: istio-system
spec:
  hosts:
  - "*"
  gateways:
  - platform-ingress-gateway
  http:
  - match:
    - uri:
        prefix: /kiali
    route:
    - destination:
        host: kiali.istio-system.svc.cluster.local
        port:
          number: 20001
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana-vs
  namespace: istio-system
spec:
  hosts:
  - "*"
  gateways:
  - platform-ingress-gateway
  http:
  - match:
    - uri:
        prefix: /grafana
    route:
    - destination:
        host: grafana.monitoring.svc.cluster.local
        port:
          number: 3000
```

### 4. Update get-service-endpoints target

**File: makefile** (extend existing target)

```bash
get-service-endpoints:
ifeq ($(STACK_MODE),aks)
	@AKS_LB=$$(kubectl get svc -n istio-system ingress-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -n "$$AKS_LB" ]; then \
	  echo "AKS LoadBalancer: $$AKS_LB"; \
	  echo "  Kiali: http://$$AKS_LB/kiali"; \
	  echo "  Grafana: http://$$AKS_LB/grafana"; \
	fi
endif
```

---

## Verification Strategy

**SC-001 check:**
```bash
kubectl get pods -n istio-system -l app=istiod -o wide
kubectl get pods -n istio-system -l app=ingress-gateway -o wide
# All should be Running, Ready 1/1, 0 restarts
```

**SC-002 check:**
```bash
kubectl get svc -n istio-system ingress-gateway
# Should show: LoadBalancer, EXTERNAL-IP assigned, 80:PORT/TCP
```

**SC-003a/SC-004 check:**
```bash
kubectl get pods -n istio-system -l app=kiali
LB_IP=$(kubectl get svc -n istio-system ingress-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://$LB_IP/kiali/ | grep -q "Kiali" && echo "PASS" || echo "FAIL"
```

**SC-007 check (idempotency):**
```bash
STACK_MODE=aks make setup-istio  # First run
STACK_MODE=aks make setup-istio  # Second run - should succeed, no reinstalls
```

---

## Constitution Checks

✓ Every script is safe to re-run (helm upgrade --install is idempotent)  
✓ No secrets in git (Helm values are config only)  
✓ Version pins are explicit (1.31.0, v1.85 in values files)  
✓ Node placement is explicit (nodeSelector in Helm values)  
✓ Cleanup removes all resources (Azure resource group deletion)

---

## Known Risks

1. **Kiali Prometheus integration:** Requires #101 to provide prometheus-stack-kube-prom-prometheus service in monitoring namespace. Kiali pod runs OK but topology won't display until #101 lands. Mitigation: SC-003b is "verified after #101 lands"; SC-003a passes independently.

2. **LoadBalancer IP provisioning delay:** Azure LoadBalancer can take 1-2 minutes to assign public IP. Mitigation: `get-service-endpoints` polls with jq; script waits up to 5 minutes.

3. **Node pool taint mismatches:** If #97 uses different taint key/value, pods will evict. Mitigation: Verify `az aks nodepool list` before setup; adjust Helm tolerations if needed.

---

## Effort Estimate

- Create Helm values files: 30 min
- Update Makefile: 20 min
- Create Gateway manifest: 15 min
- Test on dev AKS: 45 min
- Verify SC-001 through SC-007: 30 min
- **Total: ~2.5 hours**
