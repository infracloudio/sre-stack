# Spec: Istio Gateway on AKS

**Branch**: 003-istio-gateway-kiali-aks · **From**: issue #104 · **Status**: draft

## Problem

AKS has no service mesh today — story #97 stood up only the empty cluster. EKS and local k3d already run Istio with a single ingress-gateway LoadBalancer that serves `/grafana`, `/kiali`, and app routes via path-based routing (`setup-istio` + `setup-gateway`, surfaced through `get-service-endpoints`'s `LB_ENDPOINT`). The spec for the AKS observability story (#101/PR #103) ended up inventing its own answer to "how do I expose Grafana on AKS" — an AKS-managed mesh add-on plus the Kubernetes Gateway API — instead of reusing this existing, already-working pattern. That decision doesn't belong in that story and creates inconsistency between clouds. Without a mesh and gateway on AKS, there's also no way to run Kiali there, since Kiali reads its data straight from the mesh's telemetry.

## Outcome

Running the AKS setup installs Istio on the AKS cluster the same way `setup-istio` does today for EKS/local (self-hosted, open-source Istio via Helm — not an AKS-managed mesh add-on), deploys the same shared Istio ingress gateway (matching `setup-gateway`'s pattern). `make get-service-endpoints` prints one reachable load-balancer address for the AKS cluster, the same shape EKS's output already has today.

## User Scenarios

1. **Scenario: Deploy Istio to AKS** — A user sets `STACK_MODE=aks` in `.env`, runs `make setup-istio`: Istio control plane is installed in the `istio-system` namespace via Helm with the same chart version and values as EKS/local.

2. **Scenario: Deploy Istio gateway** — A user runs `make setup-gateway` on AKS: an ingress-gateway LoadBalancer is deployed and configured for path-based routing to `/grafana` and app routes (VirtualServices), matching the existing EKS/local setup exactly. Kiali routes will be added by the observability story.

3. **Scenario: Access shared services through the gateway** — A user runs `make get-service-endpoints`: it returns one reachable load-balancer address for the AKS cluster (e.g., `http://52.xxx.xxx.xxx:80`), in the same format EKS already produces. They use this URL to access Grafana.

4. **Scenario: Idempotent setup** — A user runs `make setup-istio` twice in a row: the second run exits 0 in under 30 seconds with no "Creating" or "Installing" output; the first run's resources remain untouched.

5. **Scenario: Clean teardown** — A user runs `make cleanup-istio` and `make cleanup-gateway` (or their AKS equivalents): all Istio and gateway resources are removed. Running cleanup a second time exits 0 without error messages ("already gone").

## Requirements

- R1  `make setup-istio` works identically on AKS as on EKS/local: installs Istio via Helm with the same chart version, namespace (`istio-system`), and configuration values from `.env`
- R2  `make setup-gateway` works identically on AKS as on EKS/local: deploys the same ingress-gateway Deployment and Service (LoadBalancer type) and configures VirtualServices for path-based routing
- R3  Gateway is configured to route `/grafana` and future app routes via HTTP path-based routing (matching existing EKS/local VirtualService patterns); `/kiali` routes will be added by the observability story
- R4  `make get-service-endpoints` returns the AKS load-balancer external IP in the same environment variable format as EKS (e.g., `LB_ENDPOINT=http://52.xxx.xxx.xxx`)
- R5  Istio resources created by `setup-istio` are removable by `cleanup-istio`; gateway resources created by `setup-gateway` are removable by `cleanup-gateway` (no orphaned resources)
- R6  Scripts are check-then-create and re-runnable: running `setup-istio` and `setup-gateway` twice creates nothing new on the second run; idempotency is guaranteed
- R7  Cleanup is complete and repeatable: `cleanup-gateway` and `cleanup-istio` remove all created Istio/gateway resources; running cleanup twice exits 0 without error
- R8  EKS and local k3d Istio/gateway setups remain byte-identical to `main`; `make setup-istio` and `make setup-gateway` on EKS are unchanged
- R9  STACK_MODE=aks in the makefile correctly branches to AKS-specific Istio/gateway targets
- R10 [NEEDS CLARIFICATION: Should Istio be installed in the system node pool only, or tolerate scheduling on workload pools with affinity/taints?]

## How we'll know it works (success criteria)

- S1  `make setup-istio` completes on a fresh AKS cluster in under 5 minutes (measured, not promised); all Istio control-plane pods in `istio-system` reach Running state within the timeframe
- S2  `make setup-gateway` completes in under 2 minutes; the ingress-gateway LoadBalancer Service acquires a stable external IP address
- S3  `curl <LB_ENDPOINT>/grafana/` returns HTTP 200 or a redirect to login (Grafana deployed by story #101); gateway answers on port 80
- S4  Second `make setup-istio` run exits 0 in under 30 seconds with no "Creating" or "Installing" output
- S5  Second `make setup-gateway` run exits 0 in under 30 seconds with no "Creating" output
- S6  After `make cleanup-gateway` and `make cleanup-istio`, all Istio/gateway resources are deleted; `kubectl get all -n istio-system` lists only system pods (if any)
- S7  Running cleanup twice exits 0 without error messages (idempotent)
- S8  `make get-service-endpoints` with `STACK_MODE=aks` prints the AKS LB endpoint; `git diff main -- makefile infra/scripts/cluster/` shows only AKS additions, EKS/local targets unchanged
- S9  `make lint` passes; no new linting errors introduced

## Out of scope

- Any AKS-native/managed service mesh add-on (e.g., Azure Service Mesh) or the Kubernetes Gateway API — this story reuses the same self-hosted, open-source Istio + classic ingress-gateway approach EKS/local already run, for cross-cloud consistency
- Deployment of Kiali to AKS; Kiali will be deployed as part of the observability stack (handled in a separate story)
- Deploying Robot Shop/HotROD or routing their traffic through the gateway (that is story #102, not yet accepted)
- Any change to EKS or local k3d's Istio/gateway/Kiali setup
- Retroactively editing story #101's spec (observability stack on AKS); that story's review fixes are handled separately

## Must keep working

- `make setup-istio` on EKS (with `STACK_MODE=eks`) unchanged and still working
- `make setup-gateway` on EKS unchanged and still working
- `make setup-local` (Istio on local k3d) unchanged and still working
- Existing `LB_ENDPOINT` and `get-service-endpoints` behavior for EKS/local unaffected
- All EKS/local Istio and gateway configuration files byte-identical to `main`
- `make lint` passes with no new linting errors

## Dependencies

- Story #97: AKS cluster + node pools (must be running before this story; provides the AKS cluster to deploy Istio to)
- Story #101: Grafana on AKS (must be deployed before `/grafana` route becomes useful in story #101; this story's gateway is route-agnostic)
