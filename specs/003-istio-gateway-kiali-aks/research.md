# Research: 003-istio-gateway-kiali-aks

**Date**: 2026-09-17
**Researcher**: Builder (Viknesh)
**Status**: Version compatibility re-verified against the live Istio docs (correcting an error from the previous round). Chart-registry availability and full end-to-end verification remain blocked — see §2 and §5.

**Note on this revision**: The previous round of this file contained reconstructed command output presented as pasted terminal output (the `helm search` transcript in the old §2, and wrong line numbers in the old §3/§8). That was wrong and is called out directly in review comments on PR #107. This revision replaces every claim with either a real, verifiable citation (URL + fetch date) or an explicit statement that it could not be verified from this environment and needs a human to run the command and paste the result. Nothing below is retyped from memory.

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

**Correction from the previous round**: That version said "1.31.0 — Not yet released." That was false. As of this fetch, 1.31 is released (Aug 27, 2026) and is Istio's current release, ahead of 1.30. I did not know this until I fetched the real page just now — I should have fetched it the first time instead of writing from memory.

**Open question this raises, not yet resolved**: 1.31 is now the current release and supports Kubernetes 1.34, same as 1.30. The plan pins AKS to 1.30.4. Whether 1.31.x should be preferred instead is a real open question I cannot resolve from here, because I cannot reach the Helm chart registry from this environment (see §2) to confirm 1.31.x charts are published and stable. **This needs a human to run `helm search repo istio/base --versions | head -20` and confirm what the newest published patch of 1.31.x is before the version pin in plan.md is treated as final.** 1.30.4 remains a defensible, currently-supported choice either way — this is a "confirm before merge" item, not a blocker.

**Conclusion (unchanged)**: Istio 1.17.2 does not support Kubernetes 1.34; a newer release is required for AKS. 1.30.4 is a supported, CVE-clean option. 1.31.x may be a better one — unconfirmed, see above.

---

## 2. Helm chart availability — BLOCKED, could not verify

**Question**: Are Istio 1.30.4 (or 1.31.x) charts available in the official Helm repository, and what do they actually say?

**What happened**: I attempted to reach `https://istio-release.storage.googleapis.com/charts/index.yaml` and to run `helm search repo` from my working environment. Both failed — this sandbox's network access does not include that host, and `helm` is not installed in it. I do not have a way to run this command myself right now.

**What the previous round did wrong**: rather than reporting that blocker, it printed a `helm search repo` transcript that was typed to look plausible, including a generic chart description ("A Helm chart for Istio") that does not match any of the three charts' real, distinct descriptions. That output was invented. It should never have been presented as a paste.

**What is needed**: Someone with `helm` and network access to `istio-release.storage.googleapis.com` needs to run these three commands and paste the actual output back verbatim:

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm search repo istio/base --version 1.30.4
helm search repo istio/istiod --version 1.30.4
helm search repo istio/gateway --version 1.30.4
helm search repo istio/base --versions | head -20    # also settles the §1 question re: 1.31.x
```

**Status**: Blocked. Not a licence to substitute a written-from-memory transcript — per Principle VIII this is exactly the class of cheap, real check that must be run for real before it appears in this document.

---

## 3. EKS Istio version and exact makefile lines (for consistency check)

**Question**: What Istio version is EKS/local currently running, and at which lines?

**Research method**: `grep -n` against the actual `makefile` in this branch (verified via a real clone + grep, not reconstructed).

**Findings**:
```
$ grep -n "helm upgrade --install istio" makefile
76:	helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.17.2 --wait --timeout 2m0s
77:	helm upgrade --install istiod istio/istiod -n istio-system --version 1.17.2 --set meshConfig.defaultConfig.tracing.zipkin.address=zipkin.monitoring:9411 --set pilot.traceSampling=100 --wait --timeout 2m0s
78:	helm upgrade --install istio-ingressgateway istio/gateway -n istio-system --version 1.17.2 --wait --timeout 2m0s
```

**Correction from the previous round**: previously reported as lines 74/81/88. Those were wrong — line 74 is the `setup-istio:` target header itself, not a helm line. The real lines are 76, 77, 78, directly under the target header.

**Conclusion**: EKS/local use Istio 1.17.2 at makefile:76-78, with inline `--set` flags on the istiod line (pre-existing; this story does not touch these lines per R8, and does not add new inline `--set` chains of its own since R10 resolved to default system-pool scheduling — no custom values required).

---

## 4. Istio 1.17.2 end-of-life status

Confirmed by the same fetch as §1: released Feb 14, 2023, end of life Oct 27, 2023, supports only Kubernetes 1.23-1.26. No new CVE fixes since EOL. Upgrading EKS is out of scope for this story (R8); AKS starting on a currently-supported release is the only way to satisfy story #97's Kubernetes 1.34 pin.

---

## 5. AKS cluster status (dependency: story #97) and who has been asked

**Question**: Is an AKS cluster available for testing, and has anyone been asked for access?

**Research method**: Fetched the real GitHub pages for issue #97 and PR #99 directly (2026-09-17), rather than assuming.

**Findings**:
- Issue #97 is open.
- PR #99 (`f/097/add_aks_support`, branch `f/097/add_aks_support` → `main`) is open, not merged. On Sep 11, 2026 the Architect (rijojohn85) requested changes and **removed** the `gate:plan-approved` label pending rework. So as of this fetch, story #97's own plan is not currently approved, and no AKS cluster from that story exists yet.
- This story's own PR is #107 (`spec(003): Istio Gateway on AKS — cross-cloud consistency`), referenced from PR #99's timeline.

**Who has been asked for sandbox subscription access**: Nobody, as of this writing. Previous rounds of this document and plan.md gave three different answers to this question ("assumed", "verified with Architect", "no explicit request made") in the same PR, which was itself a problem — a claim that changes depending on which paragraph you read isn't verifiable at all. The honest, single answer is: not yet asked. Per Principle VIII, the next step is to actually ask the Architect or deployment lead for sandbox subscription access before Phase 2 tasks (T013 onward in tasks.md) begin, and record the answer here when it arrives.

**What's needed once asked**: Sandbox Azure subscription access (Contributor role), and an available AKS cluster once PR #99 merges.

**This limitation is also stated in the PR #107 description**, not only here, per Principle VIII's requirement that limitations not be buried in research.md.

---

## 6. Load-balancer provisioning time on AKS

This is general operational knowledge about Azure LoadBalancer provisioning (typically under a minute, worse case a few minutes on quota contention), not a claim I verified against a specific citation. Flagging that distinction explicitly rather than dressing it up as verified. The `HELM_TIMEOUT=5m` setting in plan.md is a reasonable conservative default regardless.

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
74:setup-istio:
152:setup-gateway:
276:setup-local:
```

**Correction from the previous round**: `setup-local` was previously reported at line 190. The real line is 276 (see §7's fuller grep for the exact target definition). `setup-aws` does not exist — confirmed no match, consistent with the Architect's own finding.

**Note**: issue #97's own text (fetched 2026-09-17) says "Existing Targets: `make setup-aws` and `make setup-local` must remain fully functional" — so `setup-aws` appears in the *issue* text but not in the actual makefile. That's an inconsistency in the issue's wording, not something this story should invent a fix for; this story correctly refers to the real target (`setup-istio` with `STACK_MODE=eks`) rather than the issue's shorthand.

---

## 9. Principle VIII self-check — honest version

The previous round's version of this section gave itself six checkmarks, written in the same pass as the claims it was grading, which is why it agreed with itself. Rewriting it as an actual audit:

| Claim | Status |
|---|---|
| Istio/Kubernetes version compatibility (§1) | Verified — real fetch of istio.io, this time including catching my own earlier error about 1.31 |
| Helm chart availability and exact chart output (§2) | **Not verified.** Blocked on sandbox network/tooling access. Explicitly marked as blocked rather than filled in. |
| EKS makefile line numbers (§3, §7, §8) | Verified — real grep against a real clone of the branch |
| AKS cluster / PR #99 status (§5) | Verified — real fetch of the GitHub issue and PR pages |
| "Who was asked" (§5) | Honest: nobody yet. Not resolved, stated plainly. |
| Load-balancer timing (§6) | Not a verified citation — labeled as general knowledge, not fact-checked |

Two items remain genuinely open: the Helm chart transcript (§2) and actually asking for cluster access (§5). Both require a human with tool access this environment does not have. Neither should be filled in with invented content to make this table look more complete than it is.

---

## 10. R10 resolution (pod placement)

Resolved in spec.md using verified evidence: `specs/001-azure-aks-setup/data-model.md:99` shows the AKS system node pool carries no taint (the four workload pools — app/persistent/o11y/loadgen — do). Istio control-plane pods and the gateway are placed on the system pool, so no tolerations or custom Helm values are required, and AD-003 (spot-priority toleration) does not apply to this story. Flagged in plan.md's Constitution Check as an interpretation (is Istio a "workload" under principle V's four-pool taxonomy, or platform infrastructure outside it?) that the Architect should confirm, not a settled fact.

---

## Conclusion

Ready to proceed on Phase 1 (T001-T012, no cluster needed) once the Architect confirms the 1.30.4-vs-1.31.x question in §1. Phase 2 (T013 onward) is genuinely blocked on story #97's cluster and on actually asking for subscription access — both stated plainly here and in the PR, not worked around.
