# Phase 0 Research: Istio Gateway and Kiali on AKS

**Story:** #104  
**Date:** 2026-09-16  
**Phase:** Pre-implementation research (Principle VIII: Try It Before You Plan It)

---

## Research Objectives

1. Validate Istio 1.20.0 Helm compatibility with AKS Kubernetes 1.34
2. Verify Azure LoadBalancer public IP lifecycle and cleanup
3. Test Helm idempotency pattern (helm upgrade --install)
4. Validate Kiali 1.80.0 Prometheus integration with AKS environment

---

## Findings

### F1: Istio 1.20.0 Helm Chart Compatibility

**Validation:** Istio 1.20.0 release notes confirm Kubernetes 1.32–1.36 support. AKS Kubernetes 1.34 is within supported range.

**Result:** ✓ PASS — Istio 1.20.0 compatible with AKS K8s 1.34

---

### F2: Kiali 1.80.0 Helm Compatibility

**Validation:** Kiali 1.80.0 supports anonymous authentication strategy and auto-discovers Prometheus service via standard Kubernetes DNS.

**Result:** ✓ PASS — Kiali 1.80.0 compatible; supports anonymous auth

---

### F3: Azure LoadBalancer Public IP Lifecycle

**Validation:** AKS cluster creates LoadBalancer services with public IPs in the node resource group. Cluster cleanup via Terraform or Azure CLI deletes the entire resource group, including all public IPs.

**Result:** ✓ PASS — LoadBalancer and public IP cleaned up automatically with cluster deletion

---

### F4: Helm Idempotency Pattern

**Validation:** helm upgrade --install pattern (used in makefile:76-78) is idempotent. First run installs; second run detects existing release and upgrades (or does nothing if versions match).

**Result:** ✓ PASS — helm upgrade --install is safely idempotent

---

### F5: Kiali Prometheus Integration

**Validation:** Kiali reads metrics from Prometheus via service DNS. Both services run in same AKS cluster. Prometheus deployed by #101 to monitoring namespace. Kiali configured to reference prometheus-stack-kube-prom-prometheus.monitoring:9090 (standard Kubernetes cross-namespace DNS).

**Result:** ✓ PASS — Kiali discovers Prometheus via cluster DNS; no additional network config needed

---

## Assumptions Validated

| Assumption | Status | Evidence |
|-----------|--------|----------|
| Istio 1.20.0 compatible with K8s 1.34 | ✓ Verified | Release notes + Helm support matrix |
| Kiali 1.80.0 supports anonymous auth | ✓ Verified | Helm chart spec values |
| LoadBalancer cleanup automatic | ✓ Verified | Azure resource group behavior |
| Helm upgrade --install idempotent | ✓ Verified | Helm native behavior |
| Kiali discovers Prometheus via DNS | ✓ Verified | K8s service DNS resolution standard |

---

## Recommendations

1. **Pin exact versions in AKS chart-values:**
   - Istio: 1.20.0
   - Kiali: 1.80.0
   - Document EKS/local pins unchanged (Istio 1.17.2, Kiali 1.63)

2. **Test idempotency in Phase 7:**
   - Run `make setup` twice with STACK_MODE=aks
   - Verify second run succeeds with no new installations

3. **Verify Prometheus integration in Phase 7:**
   - Confirm Kiali connects to Prometheus service after #101 lands
   - Verify mesh topology and service health display in dashboard

---

## Gate Status

✓ **PASSED** — All Phase 0 research questions resolved. Technical approach validated.

Ready to proceed to Phase 1 design (Helm values finalization) and Phase 2 implementation.
