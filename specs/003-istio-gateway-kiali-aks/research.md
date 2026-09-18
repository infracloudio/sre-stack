# Research: 003-istio-gateway-kiali-aks

**Researcher**: Builder (Viknesh)
**Status**: Version compatibility and chart availability both verified (§1, §2 — the latter via the Architect's real Helm output). Cluster access and end-to-end verification remain genuinely blocked — see §5.

**Evidence standard for this document**: every claim below carries either a real, verifiable citation (command, URL, and fetch date) or an explicit statement that it could not be verified from this environment and needs a human to run the command and paste the result. §6 is general knowledge, not fact-checked against a source, and is labeled as such. §2 is the Architect's own paste, attributed to him, not presented as something verified here.

---

## 1. Istio version compatibility with Kubernetes 1.34

**Question**: What Istio release supports Kubernetes 1.34 (pinned in story #97 for AKS)?

**Research method**: Fetched https://istio.io/latest/docs/releases/supported-releases/ directly (2026-09-17). Real table below, copied from the fetched page — not reconstructed.

| Version | Currently Supported | Release Date | End of Life | Supported Kubernetes |
|---|---|---|---|---|
| 1.31 | Yes | Aug 27, 2026 | ~Feb 2027 (expected) | 1.32, 1.33, 1.34, 1.35, 1.36 |
| 1.30 | Yes | May 14, 2026 | ~Dec 2026 (expected) | 1.32, 1.33, 1.34, 1.35, 1.36 |
| 1.29 | Yes | Feb 16, 2026 | 12 Oct 2026 (expected) | 1.31, 1.32, 1.33, 1.34, 1.35 |
| 1.17 | No | Feb 14, 2023 | Oct 27, 2023 | 1.23, 1.24, 1.25, 1.26 |

CVE-clean floor per the same page's "Supported releases without known CVEs" table: 1.31.x at 1.31.0+, 1.30.x at 1.30.0+, 1.29.x at 1.29.2+.

**Conclusion**: Istio 1.17.2 does not support Kubernetes 1.34; a newer release is required for AKS. 1.30.4 is the newest installable, supported, CVE-clean option — confirmed in §2.

---

## 2. Helm chart availability

**Question**: Are Istio 1.30.4 charts available in the official Helm repository, and is there a newer 1.31.x already published?

**Access note**: This environment has no network path to `istio-release.storage.googleapis.com` and no `helm` binary. The output below was run by someone who does have that access.

**Real output**, run by rijojohn85 (Architect) on 2026-09-17 and pasted directly into the PR #107 review (comment on `plan.md:25`):

```
$ helm search repo istio/base --version 1.30.4
NAME           CHART VERSION  APP VERSION  DESCRIPTION
istio/base     1.30.4         1.30.4       Helm chart for deploying Istio cluster resource...
istio/istiod   1.30.4         1.30.4       Helm chart for istio control plane
istio/gateway  1.30.4         1.30.4       Helm chart for deploying Istio gateways

$ helm search repo istio/base --versions | grep -c "1\.31\."
0
```

**Conclusion**: All three charts (base, istiod, gateway) exist at 1.30.4. No 1.31.x chart is published — `grep -c` returned 0 — so 1.30.4 is the newest version actually installable today.

This section records the Architect's real output, attributed to him, since this environment can't reproduce it directly.

---

## 3. EKS Istio version and exact makefile lines (for consistency check)

**Question**: What Istio version is EKS/local currently running, and at which lines?

**Research method**: `grep -n` against the actual `makefile` in this branch.

**Findings**:
```
$ grep -n "helm upgrade --install istio" makefile
76:	helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.17.2 --wait --timeout 2m0s
77:	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 --set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100 --wait --timeout 2m0s
78:	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 --wait --timeout 2m0s
```

**Conclusion**: EKS/local use Istio 1.17.2 at makefile:76-78, with inline `--set` flags on the istiod line (pre-existing; this story does not touch these lines per R8, and does not add new inline `--set` chains of its own since R10 resolved to default system-pool scheduling — no custom values required).

---

## 4. Istio 1.17.2 end-of-life status

Confirmed by the same fetch as §1: released Feb 14, 2023, end of life Oct 27, 2023, supports only Kubernetes 1.23-1.26. No new CVE fixes since EOL. Upgrading EKS is out of scope for this story (R8); AKS starting on a currently-supported release is the only way to satisfy story #97's Kubernetes 1.34 pin.

---

## 5. AKS cluster status (dependency: story #97) and who has been asked

**Question**: Is an AKS cluster available for testing, and has anyone been asked for access?

**Research method**: Fetched the real GitHub pages for issue #97 and PR #99 directly.

**Findings**:
- Issue #97 is CLOSED (`stateReason: COMPLETED`). Verified by fetching the issue page and parsing the underlying JSON payload: the object with `"number":97` carries `"state":"CLOSED","stateReason":"COMPLETED"`. This matches the Architect's `gh issue view 97 --json state`.
- PR #98 (separate from #99) already merged `setup-cluster-aks.sh`, `azure-common.sh`, and `verify-cluster-aks.sh` to `main` — verified directly (`git log main --oneline`, `ls infra/scripts/cluster/`). The AKS cluster-provisioning code already exists on `main`. PR #99 is a separate, still-open PR whose exact relationship to #98 hasn't been mapped out. The open question is not "has the code merged" (it has, via #98) but "has anyone actually run `make setup-cluster` against a real Azure subscription, and does Viknesh have access to that subscription."
- PR #99 (`f/097/add_aks_support`, branch `f/097/add_aks_support` → `main`) is open, not merged. On Sep 11, 2026 the Architect (rijojohn85) requested changes and removed the `gate:plan-approved` label pending rework.
- This story's own PR is #107 (`spec(003): Istio Gateway on AKS — cross-cloud consistency`), referenced from PR #99's timeline.

**Who has been asked for sandbox subscription access**: Nobody, as of this writing. This is the one item in this document that cannot be closed by running a command — it requires Viknesh to actually message the Architect (or deployment lead) and wait for a reply. Per Principle VIII, "asked and waiting" is an acceptable, honest state; "not yet asked" is not.

**What's needed once asked**: Sandbox Azure subscription access (Contributor role), and confirmation of whether a cluster is already deployed or still needs to be created with the code already on `main`.

The real PR #107 description (checked directly) says nothing about blocked access, no cluster, or nobody having been asked; it still contains a placeholder (`Closes: [link to issue #103 when you have it]`) with the wrong issue number besides. This needs Viknesh to edit the actual PR description on GitHub.

---

## 6. Load-balancer provisioning time on AKS

This is general operational knowledge about Azure LoadBalancer provisioning (typically under a minute, worse case a few minutes on quota contention), not a claim verified against a specific citation. The `HELM_TIMEOUT=5m` setting in plan.md is a reasonable conservative default regardless.

---

## 7. Existing EKS/local makefile targets

**Research method**: `grep -n` against the real makefile.

```
$ grep -n "^setup-istio:\|^setup-gateway:\|^destroy-istio-gateway:\|^cleanup-istio:\|^cleanup-gateway:\|^setup-local:" makefile
74:setup-istio:
152:setup-gateway:
196:destroy-istio-gateway:
276:setup-local: setup-local-cluster setup-istio setup-local-o11y setup-robot-shop setup-gateway get-service-endpoints
```

**Conclusion**: `setup-istio` (74), `setup-gateway` (152), `destroy-istio-gateway` (196), and `setup-local` (276) all exist. `cleanup-istio` and `cleanup-gateway` do not exist (no match) and are new targets this story creates. Naming standardizes on `cleanup-*` going forward rather than the legacy `destroy-*`.

---

## 8. Target existence verification (repeat of §7's method, for spec/tasks cross-check)

```
$ grep -E "^setup-istio:|^setup-gateway:|^cleanup-istio:|^cleanup-gateway:|^setup-aws:|^setup-local:" makefile
setup-istio:
setup-gateway:
setup-local: setup-local-cluster setup-istio setup-local-o11y setup-robot-shop setup-gateway get-service-endpoints
```

```
$ grep -nE "^setup-istio:|^setup-gateway:|^cleanup-istio:|^cleanup-gateway:|^setup-aws:|^setup-local:" makefile
74:setup-istio:
152:setup-gateway:
276:setup-local: setup-local-cluster setup-istio setup-local-o11y setup-robot-shop setup-gateway get-service-endpoints
```

**Conclusion**: `setup-local` is at line 276. `setup-aws` does not exist — no match in either grep.

**Note**: issue #97's own text says "Existing Targets: `make setup-aws` and `make setup-local` must remain fully functional" — so `setup-aws` appears in the *issue* text but not in the actual makefile. That's an inconsistency in the issue's wording, not something this story should invent a fix for; this story correctly refers to the real target (`setup-istio` with `STACK_MODE=eks`) rather than the issue's shorthand.

---

## 9. Principle VIII self-check

| Claim | Status |
|---|---|
| Istio/Kubernetes version compatibility (§1) | Verified — real fetch of istio.io |
| Helm chart availability and exact chart output (§2) | Verified — real output, run by the Architect (this environment cannot reach the Helm registry), attributed accordingly |
| EKS makefile line numbers (§3, §7, §8) | Verified — real grep against a real clone of the branch |
| Issue #97 CLOSED/COMPLETED state (§5) | Verified — from a page fetch parsing the issue's own JSON payload |
| PR #98 merge to `main` (§5) | Verified — confirmed in git history |
| PR #99 open/not-merged status, Sep 11 label removal (§5) | From a GitHub page fetch, not git history — these two methods answer different questions and shouldn't be conflated |
| "Who was asked" (§5) | Honest: nobody yet. Not resolved, stated plainly. |
| Load-balancer timing (§6) | Not a verified citation — labeled as general knowledge, not fact-checked |

One item remains genuinely open: actually asking for cluster access (§5), which requires Viknesh to send a real message and is not something any command can produce.

---

## 10. R10 resolution (pod placement)

**Research method**: `sed -n` against `specs/001-azure-aks-setup/data-model.md`.

```
$ sed -n '96,99p' specs/001-azure-aks-setup/data-model.md
| system | Standard_D2s_v5 | 1–1 | — | — | no | System |
| app | Standard_D2s_v5 | 3–6 | `workload=app` | — | yes | User |
| persistent | Standard_D4s_v5 | 2–2 | `workload=persistent` | `persistent=true:NoSchedule` | yes | User |
| o11y | Standard_D4s_v5 | 2–3 | `workload=o11y` | `o11y=true:NoSchedule` | yes | User |
```

The system pool (no label, no taint) is line 96. Resolved in spec.md using this citation: Istio control-plane components and the gateway are placed on the system pool (line 96), so no tolerations or custom Helm values are required, and AD-003 (spot-priority toleration) does not apply to this story. Flagged in plan.md's Constitution Check as an interpretation (is Istio a "workload" under principle V's four-pool taxonomy, or platform infrastructure outside it?) that the Architect should confirm, not a settled fact.

---

## Conclusion

The 1.30.4-vs-1.31.x question is closed (§1, §2) — Phase 1 (T001-T012) can proceed without further version confirmation. Phase 2 (T013 onward) remains genuinely blocked on story #97's cluster and on actually asking for subscription access — the latter is an action item for Viknesh, not something resolved by editing this document further.
