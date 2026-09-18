# Spec: Istio Gateway on AKS

**Branch**: 003-istio-gateway-kiali-aks · **From**: issue #104 · **Status**: draft

## Problem

AKS has no service mesh today — story #97 stood up only the empty cluster. EKS and local k3d already run Istio with a single ingress-gateway LoadBalancer that serves `/grafana`, `/kiali`, and app routes via path-based routing (`setup-istio` + `setup-gateway`, surfaced through `get-service-endpoints`'s `LB_ENDPOINT`). The spec for the AKS observability story (#101/PR #103) ended up inventing its own answer to "how do I expose Grafana on AKS" — an AKS-managed mesh add-on plus the Kubernetes Gateway API — instead of reusing this existing, already-working pattern. That decision doesn't belong in that story and creates inconsistency between clouds. Without a mesh and gateway on AKS, there's also no way to run Kiali there, since Kiali reads its data straight from the mesh's telemetry.

## Outcome

Running the AKS setup installs Istio on the AKS cluster the same way `setup-istio` does today for EKS/local (self-hosted, open-source Istio via Helm — not an AKS-managed mesh add-on) — including the shared Istio ingress gateway, which `setup-istio`'s third Helm install creates directly (see R2; `setup-gateway` does no work this story needs). `make get-service-endpoints` reads the AKS load-balancer's external IP the same way it reads EKS's today, in the same `LB_ENDPOINT` variable shape (bare IP/hostname). Its existing (unchanged) behavior prints multiple `http://` lines, not one — see R4 and the makefile-targets.md contract for the exact output.

## User Scenarios

1. **Scenario: Deploy Istio to AKS** — A user sets `STACK_MODE=aks` in `.env`, runs `make setup-istio`: Istio control plane is installed in the `istio-system` namespace via Helm, following the same target and pattern as EKS/local. The chart version is 1.30.4 on AKS (EKS/local remain on 1.17.2, which does not support Kubernetes 1.34).

2. **Scenario: Istio installs the ingress gateway** — A user runs `make setup-istio` on AKS: the third Helm chart it installs (`istio/gateway`) creates the `istio-ingressgateway` LoadBalancer Service, matching EKS exactly. The gateway answers on port 80. `make setup-gateway` runs afterward as a no-op for this story (see R2) — there is no app-specific route to apply yet, since Robot Shop (story #102) hasn't landed on AKS.

3. **Scenario: Get the gateway address** — A user runs `make get-service-endpoints`: it reads the `istio-ingressgateway` Service (created by `setup-istio`) and prints multiple `http://` lines (Robot Shop, `/grafana`, `/kiali`), not a single address. `LB_ENDPOINT` itself is a bare IP or hostname (e.g., `52.xxx.xxx.xxx`), not prefixed with `http://` or suffixed with a port (verified: makefile lines 43/45). The `http://` URLs a user sees are built separately by `get-service-endpoints`'s own `@echo` lines (e.g., `echo "Visit ... http://$(LB_ENDPOINT)"`), in the same format EKS already produces. This is the address later stories (Grafana, Kiali, app routing) will route through.

4. **Scenario: Idempotent setup** — A user runs `make setup-istio` twice in a row: the second run exits 0 in under 30 seconds; the first run's resources remain untouched. The check for this is a `helm status`/release-exists guard in the script itself, not string-matching command output — documented Helm 3 behavior on an unchanged release prints "has been upgraded. Happy Helming!", which isn't a string this spec can safely match against. See S4/S5 and T016.

5. **Scenario: Clean teardown** — A user runs `make cleanup-istio` and `make cleanup-gateway` (or their AKS equivalents): all Istio and gateway resources are removed. Running cleanup a second time exits 0 without error messages ("already gone").

## Requirements

- R1  `make setup-istio` follows the same pattern on AKS as on EKS/local: installs all three Istio Helm charts (`istio-base`, `istiod`, and `istio/gateway` — the last of which creates the `istio-ingressgateway` LoadBalancer Service that `get-service-endpoints` reads) into the `istio-system` namespace (verified: `sed -n '74,90p' makefile` — `setup-istio` at line 74 installs all three). The Istio chart version is pinned per-platform (AKS: 1.30.4; EKS/local: 1.17.2, unchanged) because Istio 1.17.2 does not support Kubernetes 1.34 (AKS's pinned version per story #97); see research.md §1-§2.
- R2  On EKS, `setup-gateway` (makefile:152) does not create the ingress-gateway Deployment or Service — that happens inside `setup-istio`'s third Helm install (makefile:78). `setup-gateway` on EKS only creates the `robot-shop` namespace and applies `app/robot-shop/Istio/gateway.yaml` (an app-specific Gateway/VirtualService). Since Robot Shop is out of scope for this story (#102), `setup-gateway` on AKS has no app-specific resource to apply yet, so it's a standalone no-op target (matching R1's pattern), invoked directly. It is not wired into the composite `setup:` chain: under `STACK_MODE=aks` (verified: `sed -n '53,57p' makefile`), `setup:` only runs `setup-cluster` — deliberately, per the makefile's own comment that "the aks lifecycle is the empty cluster only... the workloads come in later stories." Whether to wire `setup-istio`/`setup-gateway` into that composite chain is a separate decision for a later integration story; this spec does not propose it.
- R3  The gateway (created by `setup-istio`'s Helm install, not `setup-gateway` — see R2) answers on port 80 and is ready to accept path-based routes (VirtualServices) as they are added by later stories; this story applies no VirtualServices itself. The `/grafana` route is created by story #101 (which applies `monitoring/istio-observability-addons/` via `setup-istio-o11y-addons`), and `/kiali` by the observability story
- R4  `make get-service-endpoints` returns the AKS load-balancer external IP the same way EKS's does today. `LB_ENDPOINT` is a make variable holding a bare IP or hostname (no scheme, no port), computed once near the top of the makefile (verified: `sed -n '42,46p'` and `sed -n '169,190p' makefile`); `get-service-endpoints` never echoes the variable by name, it only interpolates the value into `http://$(LB_ENDPOINT)` URL lines. "Same format as EKS" holds loosely — EKS reads a `.hostname` (ELB DNS name), AKS reads a raw `.ip`; both are bare hosts with no scheme or port.
- R5  Istio resources (control plane AND ingress gateway, both installed by `setup-istio` per R2) are removable by `cleanup-istio`; `setup-gateway` and `cleanup-gateway` remain no-ops for this story, so there is nothing for `cleanup-gateway` to remove (no orphaned resources either way)
- R6  Scripts are check-then-create and re-runnable: running `setup-istio` and `setup-gateway` twice creates nothing new on the second run; idempotency is guaranteed
- R7  Cleanup is complete and repeatable: `cleanup-gateway` and `cleanup-istio` remove all created Istio/gateway resources; running cleanup twice exits 0 without error
- R8  EKS and local k3d Istio/gateway setups remain byte-identical to `main`; `make setup-istio` and `make setup-gateway` on EKS are unchanged
- R9  STACK_MODE=aks in the makefile correctly branches to AKS-specific Istio/gateway targets
- R10  Istio control-plane components (istiod; istio-base installs CRDs only, no pods) and the ingress-gateway are scheduled on the AKS system node pool, which carries no taint (verified: `sed -n '96p' specs/001-azure-aks-setup/data-model.md` → `| system | Standard_D2s_v5 | 1–1 | — | — | no | System |`). No tolerations or custom Helm values are required for placement, and AD-003 (spot-priority toleration) does not apply to this story, since the system pool is not a spot-priced workload pool.

## How we'll know it works (success criteria)

- S1  `make setup-istio` completes on a fresh AKS cluster in under 5 minutes (measured, not promised); all Istio control-plane pods in `istio-system` reach Running state within the timeframe
- S2  `make setup-istio` (whose third Helm install creates the gateway) completes in under 5 minutes and the ingress-gateway LoadBalancer Service acquires a stable external IP address (folded into S1's timing — there is no separate 2-minute budget for `setup-gateway`, since it does no work on AKS for this story; see R2)
- S3  `curl <LB_ENDPOINT>` returns a response from the gateway on port 80 (a 404 from Istio's own gateway is an acceptable pass here, since no route exists yet — this story does not create the `/grafana` route)
- S4  Second `make setup-istio` run exits 0 in under 30 seconds, and the script's own `helm status`/release-exists guard confirms no new release action was taken. This is not verified by matching specific command-output strings (e.g. "Creating"/"Installing") — see T016.
- S5  Second `make setup-gateway` run exits 0 in under 30 seconds — trivially true, since `setup-gateway` is a no-op for this story (see R2)
- S6  After `make cleanup-gateway` and `make cleanup-istio`, `kubectl get all -n istio-system` returns nothing at all (no system-managed pods run in `istio-system` — kube-dns/CoreDNS is in `kube-system`)
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
- Story #101: Grafana on AKS — not a blocking dependency; this story's gateway is route-agnostic and installs independently of #101 (see makefile-targets.md contract). The only link is that `/grafana` (once routed by a later story) won't return anything useful until #101 deploys Grafana — a statement about the route's usefulness, not about this story's setup order.
