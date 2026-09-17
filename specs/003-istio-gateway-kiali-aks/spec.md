# Deploy Istio Ingress Gateway and Kiali to AKS

**Story:** #104  
**Depends on:** #97 (AKS cluster + node pools). Related: #101 (verifies Kiali topology)

---

## User Scenarios

**Scenario 1: Platform operator configures observability mesh on AKS**
- Operator runs `make setup` with `STACK_MODE=aks`
- Istio mesh deploys to the cluster with control plane and data plane healthy
- Ingress gateway LoadBalancer gets a public IP
- Operator verifies `/kiali` route is accessible at that IP
- Experience matches EKS

**Scenario 2: SRE accesses Kiali mesh topology on AKS**
- After #101 (Prometheus) lands, SRE opens Kiali dashboard on AKS
- Dashboard loads and displays mesh topology and service health
- Same user experience as EKS/local; no Azure-specific UI differences

**Scenario 3: Application observability stack expands to AKS**
- Once app workloads deploy to AKS (#102), traffic flows through the shared gateway
- Kiali visualizes the mesh; Prometheus ingests metrics from the observability stack (#101)
- No manual gateway reconfiguration needed; platform-owned entry point already in place

---

## Requirements

**FR-001: Self-hosted Istio mesh on AKS**
- Deploy self-hosted, open-source Istio via Helm on AKS cluster
- Mesh and Kiali releases are version-pinned in Azure-specific settings files
- Version pins are chosen at build time to be current and compatible with cluster's Kubernetes version
- Existing Amazon/local version pins do not change

**FR-002: Shared ingress gateway, platform-owned**
- Deploy ingress gateway (LoadBalancer) to AKS in istio-system namespace
- Gateway resource is platform-owned and exists independently of any application
- Gateway enables path-based routing for `/kiali` path
- Same routing patterns as EKS; no Azure-specific workarounds

**FR-003: Kiali observability dashboard on AKS**
- Deploy Kiali configured to read metrics from Prometheus (provided by #101)
- Kiali is installed and operational when this story completes
- Dashboard is accessible via the platform-owned gateway at `/kiali` path with anonymous authentication

**FR-004: Node-pool placement for mesh components**
- Istio control plane and ingress gateway run on system node pool
- Kiali runs on observability node pool with observability toleration
- Components schedule correctly despite node pool constraints from #97

**FR-005: Setup path integrates Azure selection**
- Existing setup path, with `STACK_MODE=aks`, installs the mesh and gateway
- Behaviour is consistent with existing EKS and local setup behavior
- No setup path duplication or new Azure-specific targets

**FR-006: Service endpoints output includes AKS**
- With `STACK_MODE=aks` selected, `make get-service-endpoints` prints the AKS gateway address in the same format EKS and local use

**FR-007: Setup is idempotent and cleanup is complete**
- Running setup a second time with `STACK_MODE=aks` installs nothing new; mesh, gateway, and Kiali are detected as already present
- Setup finishes without error on repeated runs
- Mesh, gateway LoadBalancer, and public IP do not outlive the existing cleanup command; `make cleanup` deletes cluster and removes all resources

---

## Success Criteria

**SC-001: Istio mesh is operational on AKS**
- [ ] All mesh control-plane and gateway pods are Ready with zero restarts after setup completes
- [ ] Data plane can inject sidecars into workloads

**SC-002: Ingress gateway is deployed and responding**
- [ ] Gateway service has assigned external IP (LoadBalancer provisioned)
- [ ] Gateway can route traffic to destination services
- [ ] Routing succeeds without errors or connectivity issues

**SC-003a: Kiali pod is running and dashboard loads**
- [ ] Kiali pod is Running and Ready in observability node pool
- [ ] Dashboard loads at `/kiali` path without errors

**SC-003b: Kiali mesh topology is visible**
- [ ] (Verified after #101 lands) Mesh topology and service health display in Kiali dashboard

**SC-004: `/kiali` route is accessible with anonymous authentication**
- [ ] Operator can reach Kiali via platform-owned gateway `/kiali` path
- [ ] Kiali uses anonymous authentication strategy (no login required)

**SC-005: Node-pool placement is correct**
- [ ] Mesh control plane and gateway pods are scheduled to system pool
- [ ] Kiali pod is scheduled to observability pool
- [ ] No pod evictions due to taint mismatches

**SC-006: EKS and local setups remain unaffected**
- [ ] EKS setup with existing version pins works as before
- [ ] Local setup with existing version pins works as before

**SC-007: Setup is idempotent and cleanup removes all resources**
- [ ] Running setup twice on same AKS cluster succeeds both times; second run detects existing mesh, gateway, and Kiali; installs nothing new
- [ ] After running `make cleanup`, LoadBalancer and public IP are removed
- [ ] No orphaned mesh infrastructure remains in Azure resource groups

---

## Assumptions

1. **Version pins are Azure-specific:** Istio and Kiali versions chosen for AKS K8s 1.34 are separate from and do not affect existing EKS/local pins. Version numbers belong in the plan, not the spec.

2. **Gateway is platform infrastructure:** The shared entry point is owned by the platform team, lives in istio-system namespace, and is independent of application deployments.

3. **Node pools exist:** AKS cluster from #97 provides system pool and observability pool with appropriate taints for placement.

4. **Kiali requires Prometheus:** Kiali reads Istio metrics from Prometheus via service DNS configuration. Prometheus is installed by #101. This story installs and configures Kiali to point at the Prometheus service #101 will provide; mesh topology and health metrics are verified only after #101 lands.

5. **Setup path uses existing mechanism:** Existing Makefile dispatches on `STACK_MODE` env var; no build system changes needed.

6. **Cleanup handles all resources:** `make cleanup` deletes the AKS cluster, removing the LoadBalancer and public IP as well.

7. **Helm upgrade --install is idempotent:** The standard Helm pattern handles both "install if absent" and "upgrade if present" in a single command without additional logic.

---

## Edge Cases

1. **LoadBalancer IP provisioning delay:** Azure takes 1–2 minutes to assign public IP. Mitigation: `make get-service-endpoints` polls with 5s retries up to 2 minutes. If timeout, IP will appear shortly after; retry command.

2. **Node pool taint mismatch:** If #97 defines different taint key/value, pods will evict. Mitigation: Verify `az aks nodepool list` shows correct agentpool labels; adjust Helm tolerations if needed.

3. **Prometheus service name:** Kiali Helm values hardcode prometheus-stack-kube-prom-prometheus (from #101 default chart). If #101 uses different service name, Kiali won't find metrics. Mitigation: SC-003b verification deferred to after #101 lands; Kiali pod itself (SC-003a) runs independently.

---

## Out of Scope

- Robot Shop or HotROD deployment and routing (#102)
- Azure-managed service mesh add-ons or Kubernetes Gateway API
- Retroactively changing #101's observability spec
- Upgrading EKS/local Istio versions

---

## Dependency Direction

**With #101 (Grafana and Prometheus observability on AKS):**
- This story (#104) delivers: mesh, gateway, `/kiali` route, Kiali pod, platform-owned entry point
- #101 delivers: Prometheus, Grafana, and verification of `/grafana` route and Kiali topology visibility
- **#104 completes independently.** #101 verifies SC-003b (Kiali topology display) once Prometheus is available.

**With #97 (AKS cluster + node pools):**
- Blocking dependency. Requires cluster and node pools to exist.
