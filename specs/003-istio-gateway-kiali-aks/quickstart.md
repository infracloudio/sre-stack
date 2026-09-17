# Quickstart: Istio Gateway on AKS

## Overview

This guide validates that Istio and the ingress gateway are deployed correctly on AKS, following the same pattern as EKS/local. It covers end-to-end setup, routing validation, and idempotency checks.

## Prerequisites

- AKS cluster is deployed and running (story #97 completed — as of 2026-09-17 this is not yet true; PR #99 is open and awaiting rework, see research.md §5)
- System node pool exists with no taint (per R10 / `specs/001-azure-aks-setup/data-model.md:99`); Istio and the gateway schedule there by default
- kubectl is configured and authenticated to the AKS cluster
- Helm 3.x is installed
- `.env` has STACK_MODE=aks

Note: Grafana and Kiali are not prerequisites for this story's validation — this story does not route to either (see spec.md R3, Out of Scope).

## Validation Scenario 1: Deploy Istio Control Plane

**Objective**: Verify that `make setup-istio` deploys the Istio control plane and reaches Ready state within 5 minutes (S1).

### Steps

1. **Start**: Record the current time and baseline state
   ```bash
   start_time=$(date +%s)
   kubectl get all -n istio-system
   # Expected: no istio-system namespace or empty namespace
   ```

2. **Deploy**: Run setup-istio
   ```bash
   make setup-istio
   # Expected: Helm repo add, helm upgrade --install for istio-base, istiod, istio-ingressgateway
   # Exit code: 0
   ```

3. **Verify pods reach Running state**
   ```bash
   kubectl get pods -n istio-system --watch
   # Expected within ~5 minutes:
   # - istiod-XXX: Running, all containers Ready (1/1)
   # - istio-ingressgateway-XXX: Running, all containers Ready (1/1)
   ```

4. **Check pod placement** (validates Constitution V & R10 recommendation)
   ```bash
   kubectl get pods -n istio-system -o wide
   # Expected:
   # - istiod pod NODE should match o11y node pool (e.g., aks-o11y-NNN)
   # - istio-ingressgateway pod NODE should match app node pool (e.g., aks-app-NNN)
   ```

5. **Measure elapsed time**
   ```bash
   end_time=$(date +%s)
   elapsed=$((end_time - start_time))
   echo "Deployment completed in $elapsed seconds"
   # Expected: < 300 seconds (5 minutes, per S1)
   ```

6. **Verify cleanup coverage** (R5: every resource `setup-istio`/`setup-gateway` creates is removable by `cleanup-istio`/`cleanup-gateway`)
   ```bash
   kubectl get all -n istio-system
   # Note the resources present here; cleanup (Scenario 4) must remove all of them, system pods aside
   ```

---

## Validation Scenario 2: Deploy Ingress Gateway & Verify LB Assignment

**Objective**: Verify that `make setup-gateway` deploys the gateway, acquires a LoadBalancer IP, and becomes accessible within 2 minutes (S2).

### Prerequisites
- Scenario 1 completed (istiod is Running)
- APP_NS (robot-shop) namespace exists

### Steps

1. **Start**: Record time and baseline
   ```bash
   start_time=$(date +%s)
   kubectl get svc -n istio-system istio-ingressgateway
   # Expected: service does not exist yet (or no external IP)
   ```

2. **Deploy**: Run setup-gateway
   ```bash
   make setup-gateway
   # Expected: kubectl apply for gateway.yaml
   # Exit code: 0
   ```

3. **Wait for external IP assignment**
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway --watch
   # Expected within ~2 minutes:
   # NAME                    TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
   # istio-ingressgateway    LoadBalancer   10.0.X.X       52.XXX.XXX.XXX   80:XXXXX/TCP
   ```

4. **Capture the load balancer endpoint**
   ```bash
   LB_ENDPOINT=$(kubectl get svc -n istio-system istio-ingressgateway \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   echo "LB_ENDPOINT=http://${LB_ENDPOINT}:80"
   # Expected: http://52.XXX.XXX.XXX:80
   ```

5. **Measure elapsed time**
   ```bash
   end_time=$(date +%s)
   elapsed=$((end_time - start_time))
   echo "Gateway ready in $elapsed seconds"
   # Expected: < 120 seconds (2 minutes, per S2)
   ```

---

## Validation Scenario 3: Verify Service Endpoints & Routing

**Objective**: Verify that `make get-service-endpoints` returns the LB endpoint and that basic HTTP connectivity works (S3).

### Prerequisites
- Scenario 2 completed (LoadBalancer has external IP)
- Robot Shop application is deployed and web service is Running (spec dependencies)

### Steps

1. **Run get-service-endpoints**
   ```bash
   make get-service-endpoints
   # Expected output:
   # LB_ENDPOINT=http://52.XXX.XXX.XXX
   ```
   This story validates only that the gateway answers (Scenario 2); routes to Robot Shop, Grafana, and Kiali are added by later stories that own those workloads (spec.md Out of Scope).

2. **Test basic connectivity to gateway**
   ```bash
   LB_ENDPOINT=$(kubectl get svc -n istio-system istio-ingressgateway \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   
   # Test root path (robot-shop app)
   curl -i http://${LB_ENDPOINT}:80/
   # Expected: HTTP 200 or HTTP 302 redirect (to robot-shop app)
   ```

3. **Verify Gateway and VirtualService CRDs are in place**
   ```bash
   kubectl get gateway -n robot-shop
   # Expected: robotshop-gateway exists
   
   kubectl get virtualservice -n robot-shop
   # Expected: robotshop exists, routes traffic through gateway
   ```

---

## Validation Scenario 4: Test Idempotency (First Re-run)

**Objective**: Verify that running setup-istio and setup-gateway twice produces no new resources and exits cleanly (R6, S4, S5).

### Prerequisites
- Scenarios 1-3 completed (Istio is deployed and running)

### Steps

1. **Re-run setup-istio**
   ```bash
   make setup-istio
   # Expected output: Helm upgrade/install commands show no "Creating" output
   # Expected exit code: 0
   # Expected duration: < 30 seconds (per S4)
   ```

2. **Verify no new pods were created**
   ```bash
   kubectl get pods -n istio-system
   # Expected: Same pod names and ages as before (no fresh pods)
   ```

3. **Re-run setup-gateway**
   ```bash
   make setup-gateway
   # Expected output: kubectl apply shows no "created" output (only "unchanged" or nothing)
   # Expected exit code: 0
   # Expected duration: < 30 seconds (per S5)
   ```

4. **Verify no new resources**
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway
   # Expected: Same external IP, service unchanged
   ```

---

## Validation Scenario 5: Test Cleanup & Idempotency

**Objective**: Verify that cleanup targets remove resources and can be run twice safely (R7, S6, S7).

### Prerequisites
- Scenarios 1-4 completed

### Steps

1. **Run cleanup-gateway**
   ```bash
   make cleanup-gateway
   # Expected: Helm uninstall istio-ingressgateway
   # Expected exit code: 0
   ```

2. **Verify gateway is gone**
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway 2>&1
   # Expected: Error: services "istio-ingressgateway" not found
   ```

3. **Run cleanup-istio** (future, when implemented)
   ```bash
   make cleanup-istio
   # Expected: Helm uninstall istio-base, istiod
   # Expected exit code: 0
   ```

4. **Verify control plane is gone**
   ```bash
   kubectl get pods -n istio-system
   # Expected: No istiod/istio-base pods remain (namespace may retain system-managed pods)
   ```

5. **Re-run cleanup-gateway and cleanup-istio** (test idempotency)
   ```bash
   make cleanup-gateway
   # Expected exit code: 0 (no error "release not found")
   
   make cleanup-istio
   # Expected exit code: 0 (no error "release not found")
   ```

---

## Validation Scenario 6: Verify No Changes to EKS/Local

**Objective**: Verify that EKS and local k3d Istio/gateway setups remain byte-identical (R8, S8).

### Prerequisites
- Branch 003-istio-gateway-kiali-aks is checked out

### Steps

1. **Check that AWS/local scripts are unchanged**
   ```bash
   git diff main -- infra/scripts/cluster/aws/ infra/scripts/cluster/local/
   # Expected: Empty output (no changes)
   ```

2. **Check that Makefile EKS/local Istio targets are unchanged**
   ```bash
   git show main:Makefile | grep -A 5 "^setup-istio:" > /tmp/main_istio.txt
   cat Makefile | grep -A 5 "^setup-istio:" > /tmp/branch_istio.txt
   diff /tmp/main_istio.txt /tmp/branch_istio.txt
   # Expected: No diff (identical for EKS/local paths)
   ```

---

## Validation Scenario 7: Lint Checks

**Objective**: Verify that all scripts and manifests pass linting (R9, S9).

### Steps

1. **Run make lint**
   ```bash
   make lint
   # Expected exit code: 0, no new linting errors
   ```

---

## Expected Outcomes Summary

| Scenario | Success Criterion | Related Spec |
|----------|-------------------|--------------|
| 1 | Control plane Ready within 5 min, pods on correct nodes | S1, R1, R10 |
| 2 | Gateway has external IP within 2 min | S2, R2 |
| 3 | get-service-endpoints prints LB endpoint; curl succeeds | S3, R3, R4 |
| 4 | Re-run exits 0 in <30s; no new resources | S4, S5, R6 |
| 5 | Cleanup removes all Istio/gateway; re-run exits 0 | S6, S7, R7 |
| 6 | EKS/local setups unchanged (git diff empty) | S8, R8 |
| 7 | make lint exits 0; no new errors | S9 |

---

## References

- **Data Model**: See `data-model.md` for resource configurations, pod placement rules, validation rules
- **Makefile Contracts**: See `contracts/makefile-targets.md` for target signatures and dependencies
- **Kubernetes Contracts**: See `contracts/kubernetes-resources.md` for namespace, service, CRD specs
