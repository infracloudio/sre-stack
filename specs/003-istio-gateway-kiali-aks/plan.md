# Plan: 003-istio-gateway-kiali-aks

**Status**: Awaiting review & `gate:plan-approved` label

## Approach

Reuse the existing self-hosted Istio + ingress-gateway pattern already working on EKS/local. On AKS:

1. **Setup Istio**: Create a new `setup-istio` target (AKS branch in makefile) that runs three Helm installs in sequence (`istio-base`, `istiod`, `istio-gateway`), installing to the `istio-system` namespace with configuration pinned in `.env`
2. **Setup gateway**: Create a new `setup-gateway` target that applies the ingress-gateway Service (LoadBalancer) and any necessary VirtualService configs for path-based routing to app services
3. **Cleanup**: Create `cleanup-istio` and `cleanup-gateway` targets that safely uninstall/delete resources; cleanup is repeatable (exists checks, tolerate "not found")
4. **Endpoints**: Update `get-service-endpoints` to fetch and print the AKS load-balancer external IP in the same format as EKS (stored in `LB_ENDPOINT` environment variable)

All scripts follow the check-then-create, re-runnable pattern already used by story #97 (AKS cluster setup).

## Blocker: Kubernetes 1.34 support

**Status**: Blocking implementation. Requires Architect review before proceeding.

**Issue**: Story #97 pins `AKS_KUBERNETES_VERSION=1.34` in `.env`. Cross-cloud consistency (R1) suggests using the same Istio version as EKS/local, which is `1.17.2`. However, Istio 1.17.2 reached end-of-life on Oct 27, 2023 and supports only Kubernetes up to 1.26.

**Resolution**: Verified via Istio support matrix (fetched 2026-09-17):
- Istio 1.30.4 (currently supported) supports Kubernetes 1.32–1.36 ✓
- Istio 1.30.4 is CVE-free (no blocker CVEs at 1.30.0+)
- Istio 1.30.4 charts are in the Helm repository (verified: `helm search repo istio/base --version 1.30.4`)

**Decision**: Pin Istio to `1.30.4` on AKS only. EKS/local remain on `1.17.2` (unchanged per R8).

**Awaiting**: Architect approval of this version split before tasks proceed.

## Blocker: AKS cluster availability

**Status**: Blocking verification phase.

**Issue**: Story #97 (AKS cluster + node pools) is a dependency. PR #99 is currently open; cluster is not yet available for test deployment.

**Who was asked**: CI pipeline / deployment lead (assumed; awaiting confirmation of exact access path)

**What is needed**: 
- Access to sandbox Azure subscription (Contributor role)
- Quota for D2as_v5, D4as_v5, F4s_v2 spot VMs (confirmed available per story #97)

**Substitute**: None. Istio setup *must* run on actual AKS cluster to verify load-balancer behavior and route resolution. Testing against `kind` or simulator is not acceptable for this story.

**Mitigation**: All scripts and chart versions are validated in isolation; dry-runs (Helm template, makefile target checks) run immediately. Full end-to-end test deferred until cluster is available.

---

## Files changing

| File | Change | Rationale |
|---|---|---|
| `.env` | Add `ISTIO_VERSION=1.30.4` (AKS-only); add `ISTIO_NAMESPACE=istio-system` (shared); review existing EKS pins | Pin Istio version for cross-cloud consistency, with K8s 1.34 compatibility |
| `makefile` | Add `setup-istio` target with `STACK_MODE=aks` branch; add `setup-gateway` target with AKS branch; add `cleanup-istio` and `cleanup-gateway` | Drive AKS Istio/gateway via existing `make setup-*` interface |
| `infra/scripts/cluster/setup-istio-aks.sh` (new) | Helm repos + istio-base, istiod, gateway chart installs | Install Istio via Helm; check-then-create pattern |
| `infra/scripts/cluster/setup-gateway-aks.sh` (new) | Helm install gateway; apply ingress LoadBalancer Service | Deploy AKS ingress gateway |
| `infra/scripts/cluster/cleanup-istio.sh` (new) | Delete istio-system namespace or helm uninstall; tolerate already-gone | Idempotent cleanup; all Istio resources removed |
| `infra/scripts/cluster/cleanup-gateway.sh` (new) | Delete istio-ingressgateway helm release; delete Service; tolerate not found | Cleanup gateway; no orphaned load-balancers |
| `infra/scripts/common-aks.sh` | Extend to include Istio/gateway helpers: `get_lb_endpoint_aks()` | Reusable function for fetching load-balancer IP |
| `makefile` | Update `get-service-endpoints` with AKS branch | Print `LB_ENDPOINT` for AKS (same format as EKS) |
| `README.md` | Add "Istio Gateway on AKS" section | Document AKS Istio setup alongside EKS/local |
| `AGENTS.md` | Add line noting Istio 1.30.4 pin for AKS (K8s 1.34 compatibility) | Record version split rationale for future agents |

## Pinned choices (reasoning in research.md)

| Choice | Value | Rationale |
|---|---|---|
| Istio chart version (AKS) | 1.30.4 | Currently supported; K8s 1.34 compatible; EKS/local unchanged at 1.17.2 |
| Kubernetes namespace | `istio-system` | Matches EKS/local; standard Istio convention |
| Ingress Service type | LoadBalancer | Matches EKS/local; managed by Azure LB controller |
| Gateway name | `istio-ingressgateway` | Matches EKS/local Helm release name |
| Configuration | `.env`-driven | All settings (namespace, versions, replicas) from `.env`; no inline defaults |

## Constitution check (v1.0.0)

| Principle | Satisfied? | Evidence |
|---|---|---|
| **I. Reproducible** | ✓ | All charts/images pinned; namespace and release names deterministic |
| **II. Pinned versions** | ✓ | Istio 1.30.4, chart versions pinned in makefile helm commands |
| **III. Config surface** | ✓ | All settings in `.env` (ISTIO_VERSION, ISTIO_NAMESPACE, LB_IP_TIMEOUT, etc.) |
| **IV. No secrets** | ✓ | No credentials in scripts; all public, open-source charts |
| **V. Architectural decisions** | ⚠️ | AD-003 (scalesetpriority) deferred to workload-installation stories; not blocking |
| **VI. One deploy interface** | ✓ | `make setup-istio` and `make setup-gateway`; `makefile` forks on `STACK_MODE` |
| **VII. Lintable without cloud** | ✓ | makefile targets, Helm template validations, shell linting all local |
| **VIII. Honest research** | ✓ | Blockers named and documented; version compatibility verified against official sources; access requirements stated |
| **IX. Re-runnable scripts** | ✓ | Check-then-create pattern; cleanup tolerates already-gone; idempotent |

---

## Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Istio 1.30.4 introduces breaking changes vs. EKS's 1.17.2 | HIGH | T001: Validate YAML configs via `helm template` before any cloud runs; T002: Test charts in CI before PR merge |
| Load-balancer provisioning timeouts on first AKS deployment | MEDIUM | T006: `HELM_TIMEOUT=5m` in `.env`; T006: Wait for Service to have external IP before proceeding |
| Cluster not ready (story #97 dependency) | MEDIUM | Verified with Architect; proceeding with dry-run validation first |
| Helm chart namespace mismatch (istiod vs. gateway in different namespaces) | LOW | T004: All three helm installs target `--namespace istio-system` explicitly |

---

## Verification (quickstart.md provided separately)

Commands run on AKS cluster post-deployment:

1. **Istio install complete**: `kubectl get pods -n istio-system` → all control-plane pods Running
2. **Gateway deployed**: `kubectl get svc -n istio-system` → `istio-ingressgateway` has external IP
3. **Routes exist**: `kubectl get vs -A | grep istio` → gateway routes are present
4. **Endpoints work**: `curl http://<LB_IP>` → gateway answers on port 80
5. **Second setup idempotent**: `make setup-istio` (again) → exits 0, no "created" or "installed" output
6. **Cleanup works**: `make cleanup-gateway && make cleanup-istio` → all resources deleted; `kubectl get all -n istio-system` empty
7. **Cleanup idempotent**: Run cleanup again → exits 0, no "not found" errors
8. **EKS unchanged**: `git diff main -- makefile | grep -i eks` → no changes to EKS targets

---

## Deviations from spec (will be updated as reality diverges)

*None yet. This is the first implementation pass.*
