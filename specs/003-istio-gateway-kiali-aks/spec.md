# Deploy Istio Ingress Gateway and Kiali to AKS

**Story:** #104  
**Depends on:** #97 (AKS cluster + node pools)

---

## User Scenarios

**Scenario 1: Platform operator configures observability mesh on AKS**
- Operator runs `make setup` with Azure selected
- Istio mesh deploys to the cluster with control plane and data plane healthy
- Ingress gateway LoadBalancer gets a public IP
- Operator verifies `/kiali` route is accessible at that IP
- Experience matches EKS

**Scenario 2: SRE accesses Kiali mesh topology on AKS**
- SRE opens the Kiali dashboard on AKS
- Dashboard loads and displays mesh topology
- Same user experience as EKS/local; no Azure-specific UI differences

**Scenario 3: Application observability stack expands to AKS**
- Once app workloads deploy to AKS (#102), traffic flows through the shared gateway
- Kiali visualizes the mesh; Grafana ingests metrics from the observability stack (#101)
- No manual gateway reconfiguration needed; platform-owned entry point already in place

---

## Requirements

**FR-001: Self-hosted Istio mesh on AKS**
- Deploy self-hosted, open-source Istio via Helm on AKS cluster
- Mesh and Kiali releases are pinned in Azure-specific settings files
- Version pins are chosen at build time to be current and compatible with cluster's Kubernetes version
- Existing Amazon/local version pins do not change

**FR-002: Shared ingress gateway, platform-owned**
- Deploy ingress gateway (LoadBalancer) to AKS
- Gateway resource is platform-owned and exists independently of any application
- Gateway enables path-based routing
- Same routing patterns as EKS; no Azure-specific workarounds

**FR-003: Kiali observability dashboard on AKS**
- Deploy Kiali configured to read telemetry from AKS mesh
- Kiali discovers its data sources from the mesh; no manual external configuration needed
- Dashboard is accessible via the platform-owned gateway

**FR-004: Node-pool placement for mesh components**
- Istio control plane and ingress gateway run on system node pool
- Kiali runs on observability node pool with observability toleration
- Components schedule correctly despite node pool constraints from #97

**FR-005: Setup path integrates Azure selection**
- Existing setup path, with Azure selected, installs the mesh and gateway
- Behaviour is consistent with existing EKS and local setup behavior
- No setup path duplication or new Azure-specific targets

**FR-006: Service endpoints output includes AKS**
- AKS cluster endpoints report via same mechanism as EKS and local
- Operator sees one reachable URL per cluster in same format

---

## Success Criteria

**SC-001: Istio mesh is operational on AKS**
- [ ] Control plane is active and stable
- [ ] Data plane can inject sidecars into workloads
- [ ] No mesh component errors or warnings in logs

**SC-002: Ingress gateway is deployed and responding**
- [ ] Gateway service has assigned external IP (LoadBalancer provisioned)
- [ ] Gateway can route traffic to destination services
- [ ] Routing succeeds without errors or connectivity issues

**SC-003: Kiali is operational and mesh-aware**
- [ ] Kiali service is running and stable
- [ ] Dashboard loads without errors
- [ ] Mesh topology is visible (empty until #102 adds workloads)

**SC-004: `/kiali` route is accessible**
- [ ] Operator can reach Kiali via platform-owned gateway `/kiali` path
- [ ] No authentication or connectivity barriers

**SC-005: Node-pool placement is correct**
- [ ] Mesh control plane and gateway pods are scheduled to system pool
- [ ] Kiali pod is scheduled to observability pool
- [ ] No pod evictions due to taint mismatches

**SC-006: EKS and local setups remain unaffected**
- [ ] EKS setup with existing version pins works as before
- [ ] Local setup with existing version pins works as before
- [ ] Service endpoints report for all three clusters in same format

**SC-007: Dependency with #101 is non-blocking**
- [ ] This story delivers mesh, gateway, and `/kiali` route independently
- [ ] Gateway is platform-owned and functional without any application
- [ ] #101 story can attach `/grafana` route without requiring changes to this story

---

## Assumptions

1. **Version pins are Azure-specific:** Mesh and Kiali versions chosen for AKS K8s 1.34 are separate from and do not affect existing EKS/local pins.

2. **Gateway is platform infrastructure:** The shared entry point is owned by the platform team, lives in a platform namespace, and is independent of application deployments.

3. **Node pools exist:** AKS cluster from #97 provides system pool and observability pool with appropriate taints for placement.

4. **Kiali auto-discovers telemetry:** Kiali discovers metrics sources from the mesh automatically; no manual Prometheus or tracing configuration needed in this story.

5. **Setup path uses existing mechanism:** Existing Makefile dispatches on cloud selection; no build system changes needed.

6. **#101 attaches its own route:** Grafana observability story (#101) defines and verifies its `/grafana` route; this story delivers the platform-owned gateway that enables it.

---

## Out of Scope

- Robot Shop or HotROD deployment and routing (#102)
- Azure-managed service mesh add-ons or Kubernetes Gateway API
- Retroactively changing #101's observability spec
- Upgrading EKS/local Istio versions

---

## Dependency Direction

**With #101 (Grafana observability on AKS):**
- This story (#104) delivers: mesh, gateway, `/kiali` route, platform-owned entry point
- #101 delivers: Grafana and verification of `/grafana` route through the gateway
- **#101 depends on #104, not vice versa.** #104 completes independently. #101 then attaches its own route and verifies end-to-end.

**With #97 (AKS cluster + node pools):**
- Blocking dependency. Requires cluster and node pools to exist.
