# Phase 1 Quickstart: Validation & Testing Guide

## Overview

This guide provides runnable end-to-end validation scenarios that prove the AKS support feature works correctly. Test each scenario in sequence after implementation completes. All commands are copy-paste ready.

---

## Prerequisites

### Local Prerequisites

```bash
# Verify tool versions
azure-cli --version          # ≥2.87.0
kubectl version --short      # ≥1.27
bash --version               # ≥4.0
make --version               # any recent version
```

### Azure Prerequisites

1. **Azure Subscription**: Have access to an Azure subscription for testing
2. **Authentication**: Run login once before testing
   ```bash
   az login
   ```
   Or configure managed identity/service principal in CI environment

3. **Resource Group**: AKS cluster will be created in a dedicated resource group specified in `.env`

4. **Quota Check**: Verify vCPU quota in your region (need 2-4 vCPU available per node type)
   ```bash
   az vm list-skus --location <your-region> --output table | grep -E "Standard_D2s_v5|Standard_D4s_v5"
   ```

### AWS Prerequisites (for EKS regression testing)

```bash
aws --version                # ≥2.x
aws configure                # Credentials must be set
eksctl version               # ≥latest
```

---

## Scenario 1: Provision Empty AKS Cluster

**Objective**: Verify that `.env` can be configured for Azure and an empty AKS cluster with four correctly-shaped node pools is provisioned.

**Test Steps**:

1. **Configure `.env` for Azure**:
   ```bash
   cd /Users/viknesh/sre-stack
   # Edit .env: set CLOUD_PROVIDER=aks and fill in Azure section
   cat > .env.aks-test << 'EOF'
   #!/bin/bash
   
   # Use the first part of existing .env, then override
   CLOUD_PROVIDER=aks
   
   # Azure config
   AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
   AZURE_RESOURCE_GROUP=sre-stack-test-aks
   AZURE_REGION=eastus
   AZURE_CLUSTER_NAME=sre-stack-test
   AZURE_KUBERNETES_VERSION=1.27
   
   # Namespace config
   MONITORING_NS=monitoring
   APP_NS=robot-shop
   EOF
   
   # Source test config over existing .env
   source .env.aks-test
   ```

2. **Run cluster provisioning**:
   ```bash
   make start-cluster
   ```
   
   **Expected Output**:
   - AKS cluster creation begins
   - Four node pools are created: app, persistent, observability, loadgen
   - Command completes in ~15-30 minutes (AKS cluster creation time)
   - Exit code: 0

3. **Verify cluster exists**:
   ```bash
   az aks show --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_CLUSTER_NAME
   ```
   
   **Expected Output**:
   - JSON response with cluster state "Succeeded"
   - `powerState.code`: "Running"

4. **Verify kubeconfig is accessible**:
   ```bash
   kubectl cluster-info
   ```
   
   **Expected Output**:
   - Kubernetes master URL is printed
   - Certificate authority is accessible
   - Exit code: 0

5. **Verify node pools exist**:
   ```bash
   kubectl get nodes -L workload
   ```
   
   **Expected Output**:
   ```
   NAME                                STATUS   ROLES   AGE    VERSION   WORKLOAD
   aks-app-12345678-vmss000000         Ready    agent   5m    v1.27.x   app
   aks-app-12345678-vmss000001         Ready    agent   5m    v1.27.x   app
   ...
   aks-persistent-12345678-vmss000000  Ready    agent   7m    v1.27.x   persistent
   aks-persistent-12345678-vmss000001  Ready    agent   7m    v1.27.x   persistent
   ...
   aks-observability-12345678-vmss0... Ready    agent   8m    v1.27.x   o11y
   aks-observability-12345678-vmss0... Ready    agent   8m    v1.27.x   o11y
   ...
   aks-loadgen-12345678-vmss000000     Ready    agent   10m   v1.27.x   loadgen
   ```
   
   Four distinct pools with matching workload labels.

6. **Verify node count and sizing**:
   ```bash
   kubectl get nodes --show-labels | grep workload
   ```
   
   Verify counts match min/max config:
   - app: 3 nodes (min=3, max=6)
   - persistent: 2 nodes (min=2, max=2)
   - observability: 2 nodes (min=2, max=3)
   - loadgen: 1 node (min=1, max=1)

7. **Verify taints**:
   ```bash
   for pool in persistent o11y loadgen; do
     node=$(kubectl get nodes -l workload=$pool -o jsonpath='{.items[0].metadata.name}')
     echo "=== $pool pool taint ==="
     kubectl describe node $node | grep -A2 "Taints:"
   done
   ```
   
   **Expected Output**:
   - persistent: `persistent=true:NoSchedule`
   - o11y: `o11y=true:NoSchedule`
   - loadgen: `loadgen=true:NoSchedule`
   - app: no taint (or `<none>`)

---

## Scenario 2: Verify No Application Workloads Are Deployed

**Objective**: Confirm that the cluster is empty; no Robot Shop, HotROD, Grafana, or observability workloads are present.

**Test Steps**:

1. **Check namespaces** (only system namespaces should exist):
   ```bash
   kubectl get namespaces
   ```
   
   **Expected Output**: Only default, kube-system, kube-public, kube-node-lease (no robot-shop, monitoring, etc.)

2. **Check for pod deployments**:
   ```bash
   kubectl get pods --all-namespaces --field-selector status.phase=Running
   ```
   
   **Expected Output**: Only system pods (coredns, azure-cni, metrics-server); no application pods.

3. **Check for service deployments**:
   ```bash
   kubectl get svc -n robot-shop 2>&1 | grep "not found" || echo "namespace not empty"
   ```
   
   **Expected Output**: "not found" (namespace does not exist).

---

## Scenario 3: Verify StorageClass `gp2` Exists

**Objective**: Confirm that the `gp2` storage class alias is present and usable.

**Test Steps**:

1. **List storage classes**:
   ```bash
   kubectl get storageclass
   ```
   
   **Expected Output**: Storage class named `gp2` is listed (e.g., `gp2    disk.csi.azure.com ...`).

2. **Describe storage class**:
   ```bash
   kubectl describe storageclass gp2
   ```
   
   **Expected Output**:
   - Provisioner: `disk.csi.azure.com`
   - Reclaim policy: `Delete`
   - Parameters: `type: Premium_LRS` (or `StandardSSD_LRS`)

3. **Test dynamic provisioning** (optional; verifies integration but not required):
   ```bash
   kubectl apply -f - << 'EOF'
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: test-gp2
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 1Gi
     storageClassName: gp2
   EOF
   
   kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/test-gp2 --timeout=30s
   kubectl get pvc test-gp2
   kubectl delete pvc test-gp2
   ```
   
   **Expected Output**: PVC transitions to Bound state; backing Azure managed disk is created and cleaned up.

---

## Scenario 4: Re-run Provisioning (Idempotency Test)

**Objective**: Verify that running `make start-cluster` a second time is idempotent and completes without errors or duplicates.

**Test Steps**:

1. **Re-run provisioning**:
   ```bash
   make start-cluster
   ```
   
   **Expected Behavior**:
   - Command completes quickly (seconds, not minutes)
   - Logs indicate "cluster already exists" or "skipping creation"
   - No duplicate node pools are created
   - Exit code: 0

2. **Verify node count unchanged**:
   ```bash
   kubectl get nodes | wc -l
   ```
   
   Should return the same count as Scenario 1, Step 6.

3. **Verify cluster state**:
   ```bash
   kubectl cluster-info
   ```
   
   Same cluster as before; no disruption.

---

## Scenario 5: Cleanup & Teardown

**Objective**: Verify that `make cleanup` removes all Azure resources and leaves no billable traces.

**Test Steps**:

1. **Run cleanup**:
   ```bash
   make cleanup
   ```
   
   **Expected Behavior**:
   - Cluster deletion begins
   - Resource group deletion (if configured) completes
   - Exit code: 0
   - Duration: ~10-15 minutes

2. **Verify cluster is deleted**:
   ```bash
   az aks show --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_CLUSTER_NAME 2>&1
   ```
   
   **Expected Output**: Error message "NotFound" or "ResourceNotFound".

3. **Verify no orphaned resources in resource group**:
   ```bash
   az resource list --resource-group $AZURE_RESOURCE_GROUP --output table
   ```
   
   **Expected Output**: Empty list (resource group itself may still exist, but all cluster resources are gone).

---

## Scenario 6: Re-run Cleanup (Idempotency Test)

**Objective**: Verify that running `make cleanup` on non-existent cluster is safe and exits cleanly.

**Test Steps**:

1. **Run cleanup again**:
   ```bash
   make cleanup
   ```
   
   **Expected Behavior**:
   - Command completes quickly
   - Logs indicate "cluster does not exist" or "already cleaned up"
   - No errors
   - Exit code: 0

---

## Scenario 7: EKS Regression Test (Existing AWS Path)

**Objective**: Verify that existing AWS/EKS provisioning is unchanged.

**Prerequisites**: AWS credentials configured, quota available

**Test Steps**:

1. **Reset `.env` to AWS defaults**:
   ```bash
   # Use original .env with CLOUD_PROVIDER=eks
   export CLOUD_PROVIDER=eks
   export AWS_REGION=us-west-2
   export CLUSTER_NAME=sre-stack
   ```

2. **Run EKS provisioning**:
   ```bash
   make start-cluster
   ```
   
   **Expected**: Identical behavior to before AKS changes; EKS cluster created as normal.

3. **Verify EKS cluster**:
   ```bash
   kubectl get nodes -L workload
   ```
   
   Four node pools present: app, persistent, o11y, loadgen with correct labels.

4. **Clean up EKS cluster**:
   ```bash
   make cleanup
   ```
   
   Cluster deleted cleanly.

---

## Scenario 8: Local k3d Regression Test

**Objective**: Verify that local k3d provisioning is unchanged.

**Test Steps**:

1. **Set local mode**:
   ```bash
   export CLOUD_PROVIDER=local
   export LOCAL_NODES=5
   ```

2. **Run local provisioning**:
   ```bash
   make setup-local
   ```
   
   **Expected**: k3d cluster created as before.

3. **Verify k3d cluster**:
   ```bash
   kubectl get nodes -L workload
   ```
   
   Nodes present with workload labels.

4. **Clean up k3d**:
   ```bash
   make cleanup-local
   ```
   
   k3d cluster deleted.

---

## Validation Checklist

After all scenarios complete successfully, sign off:

- [ ] Scenario 1: AKS cluster provisioned with four node pools
- [ ] Scenario 2: No application workloads deployed on empty cluster
- [ ] Scenario 3: StorageClass `gp2` exists and is usable
- [ ] Scenario 4: Idempotent re-provisioning works (no duplicates)
- [ ] Scenario 5: Cleanup removes all resources
- [ ] Scenario 6: Re-run cleanup is safe (idempotent teardown)
- [ ] Scenario 7: EKS provisioning unchanged (regression test passes)
- [ ] Scenario 8: k3d provisioning unchanged (regression test passes)

**Sign-Off**:
- [ ] All scenarios executed successfully
- [ ] No manual cleanup required
- [ ] Azure billing shows zero remaining resources
- [ ] `.env` changes are backward compatible
- [ ] All three providers (EKS, k3d, AKS) work as expected

---

## Troubleshooting

### `az aks create` fails with quota error
- Check vCPU quota in region: `az vm list-skus --location <region>`
- Request quota increase via Azure portal or support ticket

### Cluster creation times out
- Check AKS cluster status: `az aks show --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_CLUSTER_NAME`
- If stuck, manually delete via portal and retry provisioning

### `kubectl` cannot connect to cluster
- Verify kubeconfig: `az aks get-credentials --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_CLUSTER_NAME`
- Check network connectivity to Azure API

### Node pools not appearing
- Wait longer; node provisioning takes 5-10 minutes per pool
- Check node pool creation status: `az aks nodepool list --resource-group $AZURE_RESOURCE_GROUP --cluster-name $AZURE_CLUSTER_NAME`

### Cleanup fails on "resource group in use"
- Manual cleanup via Azure portal: delete resource group with all resources
- Ensure no open kubeconfig contexts pointing to cluster

---

## Cost Control

**Important**: This test creates billable Azure resources. After testing:
1. **Always run** `make cleanup` to delete resources
2. **Verify deletion** in Azure portal before signing off
3. **Estimated cost per test run**: ~$5-15 USD (if run for full 30-min lifecycle)
