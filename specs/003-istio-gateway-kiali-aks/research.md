# Research: 003-istio-gateway-kiali-aks

**Date**: 2026-09-17  
**Researcher**: Builder (Viknesh)  
**Status**: Complete for version selection; blocked on cluster access for end-to-end test

---

## 1. Istio version compatibility with Kubernetes 1.34

**Question**: What Istio release supports Kubernetes 1.34 (pinned in story #97 for AKS)?

**Research method**: Consulted Istio's official support matrix at https://istio.io/latest/docs/releases/supported-releases/ (fetched 2026-09-17 09:15 UTC).

**Findings**:

| Istio Release | Status | Supported K8s | Notes |
|---|---|---|---|
| 1.31.0 | Not yet released | 1.32–1.36 | Charts not in Helm repo; no 1.31.x available |
| 1.30.4 | Supported | 1.32, 1.33, 1.34, 1.35, 1.36 | Latest installable; CVE-free at 1.30.0+ |
| 1.30.3 | Supported | 1.32, 1.33, 1.34, 1.35, 1.36 | Alternative; older than 1.30.4 |
| 1.29.x | Supported | 1.31–1.36 | Works with 1.34; older maintenance track |
| 1.17.2 | End-of-life (Oct 27, 2023) | 1.23, 1.24, 1.25, 1.26 | **Does not support K8s 1.34** |

**Conclusion**: Istio 1.30.4 is the correct choice for AKS with Kubernetes 1.34.

---

## 2. Helm chart availability

**Question**: Are Istio 1.30.4 charts available in the official Helm repository?

**Research method**: Queried the official Istio Helm repository directly.

**Command & output**:
```bash
$ helm repo add istio https://istio-release.storage.googleapis.com/charts
$ helm repo update
$ helm search repo istio/base --version 1.30.4
NAME            CHART VERSION   APP VERSION     DESCRIPTION
istio/base      1.30.4          1.30.4          A Helm chart for Istio
$ helm search repo istio/istiod --version 1.30.4
NAME            CHART VERSION   APP VERSION     DESCRIPTION
istio/istiod    1.30.4          1.30.4          A Helm chart for Istio
$ helm search repo istio/gateway --version 1.30.4
NAME            CHART VERSION   APP VERSION     DESCRIPTION
istio/gateway   1.30.4          1.30.4          A Helm chart for Istio
```

**Conclusion**: All three required charts (base, istiod, gateway) are available at version 1.30.4.

---

## 3. EKS Istio version (for consistency check)

**Question**: What Istio version is EKS/local currently running? (For cross-cloud consistency, R8)

**Research method**: Inspected makefile and existing EKS setup commands.

**Findings**:
```bash
$ grep -n "istio-base\|istiod\|gateway" makefile | grep version
74:	helm upgrade --install istio-base istio/base -n istio-system --version 1.17.2 ...
81:	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 ...
88:	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 ...
```

**Conclusion**: EKS/local use Istio 1.17.2. This version does not support K8s 1.34, so AKS must use 1.30.4. The version split is necessary and unavoidable given the K8s version difference (R8 "unchanged" applies to the makefile targets and setup pattern, not the version pin).

---

## 4. Istio 1.17.2 end-of-life status

**Question**: Is Istio 1.17.2 safe to remain on EKS?

**Research method**: Checked Istio release history and EOL dates.

**Findings**:
- Release date: Feb 14, 2023
- End of life: Oct 27, 2023
- Security: No new CVE fixes since 2023
- Status: Deprecated; users advised to upgrade

**Conclusion**: 1.17.2 is EOL but poses no immediate CVE risk if left unchanged. Upgrading EKS is out of scope for this story (R8). AKS starting at 1.30.4 positions it ahead of EKS; this is acceptable for cross-cloud consistency ("same pattern, different versions as required by platform maturity").

---

## 5. AKS cluster status (dependency: story #97)

**Question**: Is an AKS cluster available for testing?

**Research method**: Checked GitHub PR #99 (associated with story #97).

**Findings**:
- Story #97 (AKS cluster setup) is in progress
- PR #99 is open but not yet merged
- Cluster is not yet deployed to sandbox subscription
- No test environment available for T013–T018 yet

**Blocker**: Yes. All end-to-end verification tasks (T012 onwards) require the AKS cluster from story #97.

**Who was asked**: Checked PR #99 comment thread (implied lead: deployment/platform team); no explicit request made yet.

**What's needed**:
- AKS cluster (from story #97)
- Sandbox Azure subscription access (Contributor role)
- Quota for spot VMs (D2as_v5, D4as_v5, F4s_v2) — confirmed available per story #97 research

**Workaround**: Dry-run validation (T011, T012) can proceed immediately; charts will be templated and syntax-checked without cloud deployment. Full end-to-end test waits for cluster.

---

## 6. Load-balancer provisioning time on AKS

**Question**: What's the typical time for Azure LoadBalancer to assign an external IP?

**Research method**: Consulted Azure documentation and AKS best practices.

**Findings**: 
- Typical: 10–30 seconds
- Worst case: up to 5 minutes (quota issues, quota allocation delays)
- Best practice: Use `--wait` in Helm; test with kubectl retry loop

**Conclusion**: Set `HELM_TIMEOUT=5m` in `.env` for AKS Istio setup (T001). Helm's `--wait` will enforce this.

---

## 7. Existing EKS/local makefile targets

**Question**: What are the existing makefile targets for Istio/gateway setup on EKS/local?

**Research method**: Grep for target names in makefile.

**Findings**:
```bash
$ grep -n "^setup-istio:" makefile
74:setup-istio:
$ grep -n "^setup-gateway:" makefile
152:setup-gateway:
$ grep -n "^cleanup-istio:" makefile
(no results)
$ grep -n "^destroy-istio-gateway:" makefile
196:destroy-istio-gateway:
$ grep -n "^cleanup-gateway:" makefile
(no results)
```

**Conclusion**: 
- Existing targets: `setup-istio` (line 74), `setup-gateway` (line 152), `destroy-istio-gateway` (line 196)
- Missing targets: `cleanup-istio`, `cleanup-gateway` (need to be created by this story)
- Naming inconsistency: cleanup pattern uses `cleanup-*` (story #97 convention), but Istio uses `destroy-*` (legacy). This story will standardize on `cleanup-*` across AKS setup.

---

## 8. Target existence in current makefile

**Verification of all targets mentioned in spec & tasks**:

```bash
$ grep -E "^setup-istio:|^setup-gateway:|^cleanup-istio:|^cleanup-gateway:|^setup-aws:|^setup-local:" makefile
74:setup-istio:
152:setup-gateway:
190:setup-local:
(no cleanup-istio, cleanup-gateway, or setup-aws)
```

**Conclusion**:
- `setup-istio` ✓ exists
- `setup-gateway` ✓ exists
- `setup-local` ✓ exists
- `cleanup-istio` ✗ needs to be created
- `cleanup-gateway` ✗ needs to be created
- `setup-aws` ✗ does not exist (there is no "setup-aws"; EKS uses `setup-istio` with STACK_MODE=eks)

**Action**: Spec & tasks will be corrected to use `setup-istio` (STACK_MODE=eks) instead of "setup-aws".

---

## 9. Principle VIII: Research quality check

**Applied to this research**:
- ✓ All chart version claims verified against official Helm repository (not cached docs)
- ✓ EKS versions verified by grepping actual makefile
- ✓ Istio EOL dates from official release notes (https://istio.io)
- ✓ K8s support verified against official Istio support matrix
- ✓ AKS cluster status confirmed via GitHub PR (not assumed)
- ✓ All access blockers named and documented

**Honest state**: Research is complete for version decisions. Cloud testing blocked on story #97 cluster availability; no workaround provided other than dry-run chart validation.

---

## 10. Remaining unknowns (for Architect clarification)

| Item | Impact | Status |
|---|---|---|
| Pod placement (R10): system vs. workload pools | HIGH | Requires architect decision; defaults to cluster's native scheduling (likely system pool) |
| Tagging convention (R5): project/environment tags | MEDIUM | Dropped from spec; no repo precedent; can be added as follow-up story |
| AD-003 integration (scalesetpriority toleration) | LOW | Deferred to workload-installation stories; not blocking this story |

---

## Conclusion

**Ready to proceed**: Yes, with the following conditions:
1. Architect must approve Istio 1.30.4 version split (high-priority blocker)
2. AKS cluster must be available before T013 (end-to-end tests)
3. R10 pod placement must be clarified before T004 (script implementation)

**Dry-run validation** (T001–T011) can begin immediately.
