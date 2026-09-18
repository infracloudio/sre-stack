# Research: 003-istio-gateway-kiali-aks

**Date**: 2026-09-17 (initial). **Correction (round-7 audit)**: the "last revised" pointer here has gone stale every round since it was added — this document has since had round-6 edits too (§9 table, line 160). Dropping the specific-round pointer: see git history for the actual revision timeline rather than a date this field will always lag.
**Researcher**: Builder (Viknesh)
**Status**: Version compatibility and chart availability both verified (§1, §2 — the latter via the Architect's real Helm output). Cluster access and end-to-end verification remain genuinely blocked — see §5.

**Note on this revision**: The previous round of this file contained reconstructed command output presented as pasted terminal output (the `helm search` transcript in the old §2, and wrong line numbers in the old §3/§8). That was wrong and is called out directly in review comments on PR #107. This revision replaces every claim with either a real, verifiable citation (URL + fetch date) or an explicit statement that it could not be verified from this environment and needs a human to run the command and paste the result. **Correction (round-5 audit, precision)**: "nothing below is retyped from memory" overstated it — §6 is explicitly labeled general knowledge, not fact-checked against a source, and §2 is the Architect's own paste, attributed as his, not mine. Neither is presented as something I verified myself; both are labeled as what they are.

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

**Open question — now closed.** 1.31 is Istio's current release and supports Kubernetes 1.34, same as 1.30, so whether 1.31.x should be preferred was a real question. It's resolved in §2 below: the Architect (rijojohn85) ran the actual Helm search on 2026-09-17 and confirmed no 1.31.x chart is published yet, so 1.30.4 is not just defensible but the *only* currently-installable option ahead of 1.17.2.

**Conclusion**: Istio 1.17.2 does not support Kubernetes 1.34; a newer release is required for AKS. 1.30.4 is the newest installable, supported, CVE-clean option — confirmed in §2, not assumed.

---

## 2. Helm chart availability — verified, run by the Architect

**Question**: Are Istio 1.30.4 charts available in the official Helm repository, and is there a newer 1.31.x already published?

**What happened last round**: I could not reach `https://istio-release.storage.googleapis.com/charts/index.yaml` or run `helm` from my own environment (no network path to that host, no `helm` binary), and said so plainly instead of inventing a transcript. That was the right call at the time, but the block has since been cleared by someone who does have the access.

**Real output**, run by rijojohn85 (Architect) on 2026-09-17 and pasted directly into the PR #107 review (round 3, comment on `plan.md:25`):

```
$ helm search repo istio/base --version 1.30.4
NAME           CHART VERSION  APP VERSION  DESCRIPTION
istio/base     1.30.4         1.30.4       Helm chart for deploying Istio cluster resource...
istio/istiod   1.30.4         1.30.4       Helm chart for istio control plane
istio/gateway  1.30.4         1.30.4       Helm chart for deploying Istio gateways

$ helm search repo istio/base --versions | grep -c "1\.31\."
0
```

**Conclusion**: All three charts (base, istiod, gateway) exist at 1.30.4, with three distinct, real descriptions (not the generic placeholder text the previous round invented). No 1.31.x chart is published yet — `grep -c` returned 0 — so the §1 question is settled: 1.30.4 is not only supported, it's the newest version actually installable today.

I have not independently re-run this command myself (still no `helm`/network path from my environment); this section records the Architect's real output rather than my own, which is why the attribution above names who ran it and when. That's a deliberate difference from research.md's other sections, where I ran the check myself.

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
- **Correction (round-5 audit)**: issue #97 is **CLOSED** (`stateReason: COMPLETED`). Re-fetched directly (`curl` against the real issue page, 2026-09-18) and this time parsed the underlying JSON payload rather than the rendered header: the object with `"number":97` carries `"state":"CLOSED","stateReason":"COMPLETED"`. This matches the Architect's `gh issue view 97 --json state` and the independent audit LLM's own fetch — both of which reported CLOSED all along. My prior fetches across three earlier sessions read the page differently and reported Open; I don't have a confirmed explanation for the discrepancy (possibly misreading a cached or partially-rendered page, since I was checking the header/sidebar text rather than the underlying state field). I'm not going to guess further — CLOSED is what this fetch shows, it matches two independent parties, and I was wrong three times in a row before this. Recording CLOSED as the resolved status, not a disagreement.
- **Correction, and this one matters**: PR #98 (separate from #99) already merged `setup-cluster-aks.sh`, `azure-common.sh`, and `verify-cluster-aks.sh` to `main` — verified directly (`git log main --oneline`, `ls infra/scripts/cluster/`). The AKS cluster-provisioning *code* already exists on `main`. I previously framed the blocker as "waiting for PR #99 to merge," which conflated two different things: PR #99 is a separate, still-open PR whose exact relationship to #98 I have not mapped out (I'm not asserting one I haven't verified). The actual open question is not "has the code merged" (it has, via #98) but "has anyone actually run `make setup-cluster` against a real Azure subscription, and does Viknesh have access to that subscription."
- PR #99 (`f/097/add_aks_support`, branch `f/097/add_aks_support` → `main`) is open, not merged. On Sep 11, 2026 the Architect (rijojohn85) requested changes and **removed** the `gate:plan-approved` label pending rework.
- This story's own PR is #107 (`spec(003): Istio Gateway on AKS — cross-cloud consistency`), referenced from PR #99's timeline.

**Who has been asked for sandbox subscription access**: Still nobody, as of 2026-09-18. This is the one item in this whole document that cannot be closed by running a command — it requires Viknesh to actually message the Architect (or deployment lead) and wait for a reply. That message has not been sent as of this revision. Per Principle VIII, "asked and waiting" is an acceptable, honest state; "not yet asked" is not — it's simply not done yet, and this document says so plainly rather than implying otherwise.

**What's needed once asked**: Sandbox Azure subscription access (Contributor role), and confirmation of whether a cluster is already deployed or still needs to be created with the code already on `main`.

**Correction**: the previous round of this document, and of plan.md, both claimed "this limitation is also stated in the PR #107 description." That was false — I checked the real PR #107 description text on 2026-09-18 and it says nothing about blocked access, no cluster, or nobody having been asked; it still contains a placeholder (`Closes: [link to issue #103 when you have it]`) with the wrong issue number besides. This needs to be fixed by editing the actual PR description on GitHub, which I cannot do from here — see the PR description text proposed alongside this patch.

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

**Correction (independent audit caught this)**: the block below previously showed a command with no `-n` flag next to output that had line-number prefixes — impossible, since `-n` is what makes grep print line numbers. That's a second fabricated-looking transcript I introduced, on top of the R10 citation error above. Re-run for real, both ways:

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

**Correction from the previous round**: `setup-local` was previously reported at line 190. The real line is 276 (confirmed again above, with `-n`, and the full untruncated target definition this time). `setup-aws` does not exist — confirmed no match, consistent with the Architect's own finding.

**Note**: issue #97's own text (fetched 2026-09-17) says "Existing Targets: `make setup-aws` and `make setup-local` must remain fully functional" — so `setup-aws` appears in the *issue* text but not in the actual makefile. That's an inconsistency in the issue's wording, not something this story should invent a fix for; this story correctly refers to the real target (`setup-istio` with `STACK_MODE=eks`) rather than the issue's shorthand.

---

## 9. Principle VIII self-check — honest version

The previous round's version of this section gave itself six checkmarks, written in the same pass as the claims it was grading, which is why it agreed with itself. Rewriting it as an actual audit:

| Claim | Status |
|---|---|
| Istio/Kubernetes version compatibility (§1) | Verified — real fetch of istio.io, this time including catching my own earlier error about 1.31 |
| Helm chart availability and exact chart output (§2) | Verified — real output, but run by the Architect (I still cannot reach the Helm registry myself), attributed accordingly rather than presented as my own check |
| EKS makefile line numbers (§3, §7, §8) | Verified — real grep against a real clone of the branch |
| AKS cluster / PR #99 status (§5) | **Correction (round-6 audit)**: previous wording overstated the method — "confirmed against git history" applies only to PR #98 (its merge commit `777a084` is verifiably on `main`). PR #99's open/not-merged status and the Sep 11 label removal are not in git history; they came from a GitHub page fetch on 2026-09-18, same as §5 says. Split out: #98 merge — confirmed in git history; #99 status and issue #97's CLOSED/COMPLETED state — from a page fetch, 2026-09-18. |
| "Who was asked" (§5) | Honest: nobody yet. Not resolved, stated plainly. |
| Load-balancer timing (§6) | Not a verified citation — labeled as general knowledge, not fact-checked |

One item remains genuinely open: actually asking for cluster access (§5), which requires Viknesh to send a real message and is not something any command can produce. The previous round also claimed the PR description already stated this limitation — checked directly against PR #107 this round, and that claim was false. Fixed here rather than repeated a third time.

---

## 10. R10 resolution (pod placement)

**Correction (independent audit caught this, I did not)**: the line citation was wrong. `specs/001-azure-aks-setup/data-model.md:99` is the **o11y** pool row (`workload=o11y`, tainted `o11y=true:NoSchedule`), not the system pool. Re-verified directly:

```
$ sed -n '96,99p' specs/001-azure-aks-setup/data-model.md
| system | Standard_D2s_v5 | 1–1 | — | — | no | System |
| app | Standard_D2s_v5 | 3–6 | `workload=app` | — | yes | User |
| persistent | Standard_D4s_v5 | 2–2 | `workload=persistent` | `persistent=true:NoSchedule` | yes | User |
| o11y | Standard_D4s_v5 | 2–3 | `workload=o11y` | `o11y=true:NoSchedule` | yes | User |
```

The system pool (no label, no taint) is line **96**, not 99. Resolved in spec.md using this corrected citation: Istio control-plane components and the gateway are placed on the system pool (line 96), so no tolerations or custom Helm values are required, and AD-003 (spot-priority toleration) does not apply to this story. Flagged in plan.md's Constitution Check as an interpretation (is Istio a "workload" under principle V's four-pool taxonomy, or platform infrastructure outside it?) that the Architect should confirm, not a settled fact. The placement conclusion (system pool) was right; the citation proving it was wrong, and I'm recording that plainly rather than quietly fixing the number.

---

## Conclusion

The 1.30.4-vs-1.31.x question is closed (§1, §2) — Phase 1 (T001-T012) can proceed without further version confirmation. Phase 2 (T013 onward) remains genuinely blocked on story #97's cluster and on actually asking for subscription access — the latter is an action item for Viknesh, not something resolved by editing this document further.
