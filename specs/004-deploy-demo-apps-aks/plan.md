# Plan: 004-deploy-demo-apps-aks

**Status**: Approved — `gate:plan-approved` granted; implementation complete (PR #108)

**Note on provenance**: An earlier pass at this plan (via `/speckit-plan` in a separate session) produced Technical Context and ten "Phase 0 findings" that were approved in that session's chat but never written to this file. Several of those findings were also factually wrong, verified against the live cluster before this version was written (see "Corrected claims" below). This file is built from `research.md` (real, reproducible command output) and the live cluster checks re-run to settle the contradictions, not from that session's transcript.

## Summary

Restore Robot Shop's and HotROD's deployment commands — currently disabled in the makefile for every platform, not just AKS — to a working state on the AKS cluster, using in-cluster databases only, correct node-pool placement (Principle V), and a per-app external reachability path (FR-011) that shares the existing Istio ingress gateway from story 003 without the two apps' traffic colliding.

## Corrected claims (from the discarded earlier pass)

| Earlier claim | Reality, verified live | Evidence |
|---|---|---|
| Helm release `roboshop` exists with `stack_mode: eks` | Only one release exists in `robot-shop` namespace: release name `robot-shop` (not `roboshop`), revision 6, deployed | `helm list -n robot-shop` |
| `mysql-seeder-rm6pl completed 16 hours ago` | Same pod is still `1/1 Running` at 16h+, not completed; `ratings.cities` table still doesn't exist | `kubectl get pods -n robot-shop \| grep seeder`; `kubectl exec mysql-0 -- mysql -e "SELECT COUNT(*) FROM ratings.cities"` → `ERROR 1146: Table doesn't exist` |
| "~2.5 minute deployment time" | Derived from the false completion timestamp above; not usable | — |
| "Phase 0 Research Complete... end-to-end deployment works and is repeatable" | Core services work end-to-end (verified: homepage, product page, cart, checkout all load correctly through a real browser); the MySQL seed-data job does not complete — an open, reproducible defect | research.md §4d |

`.env`'s `APP_RELEASE_NAME=roboshop` is real (confirmed by reading `.env` directly) — the earlier session got this one fact right, just fabricated the command output "proving" it. This creates a real reconciliation task: research used release name `robot-shop` manually (since the makefile target was disabled); the restored target will use `roboshop` per `.env`. See "Open items" below.

## Approach

1. **Robot Shop**: restore the `setup-robot-shop` makefile target (currently fully commented out, all platforms). Fix the underlying chart defect found in research (§4b): five templates in `app/robot-shop/helm/templates/` (`mysql-statefulset.yaml`, `mysql-config.yaml`, `mysql-secret.yaml`, `mysql-service.yaml`, `mysql-seeed-job.yaml`) gate on `eq .Values.stack_mode "local"`, so MySQL never renders for `stack_mode=aks`. Change the condition to `ne .Values.stack_mode "eks"` in all five, so MySQL renders for both `local` and `aks` — this also restores local's behavior to what it had before (FR-010), since local shares the same broken condition today.
2. **HotROD**: restore the `setup-hotrod` makefile target (a one-line uncomment; chart already has correct `nodeSelector: workload: app` and minimal resources, no defect found). Wire `setup-optional-otel` as an explicit dependency — HotROD's `OTEL_EXPORTER_OTLP_ENDPOINT` points at `opentelemetry-collector.monitoring:4318`, which only exists if that target has been run; it is not currently part of `setup-observability`'s chain.
3. **Gateway (FR-011)**: extend `setup-gateway`'s AKS branch. It is currently a literal no-op (`infra/scripts/cluster/setup-gateway-aks.sh`), with its own comment stating this exact story (#102) is expected to fill it in. Apply Robot Shop's existing `app/robot-shop/Istio/gateway.yaml` (`hosts: "*"`, unchanged) and a new HotROD-specific Gateway/VirtualService scoped to a distinct host (verified working in research with `hotrod.demo.local`) rather than a second wildcard host, which would collide with Robot Shop's on the shared `istio-ingressgateway`.
4. **Idempotency**: `setup-robot-shop`'s namespace creation already uses `--dry-run=client -o yaml | kubectl apply -f -` (safe to re-run); `helm upgrade --install` is idempotent by construction. One real gotcha found in research: the seed-data Job's pod template is immutable once created — a second `helm upgrade` after any pod-template change to the seeder fails with `field is immutable` unless the old Job is deleted first. This needs either a `kubectl delete job --ignore-not-found` step before the seeder apply, or converting it to a Helm hook with `helm.sh/hook-delete-policy: before-hook-creation`.

## Open items (not resolved by this plan; need Architect input)

| Item | Question | Recommendation |
|---|---|---|
| Release name mismatch | Research used `robot-shop`; `.env` says `roboshop`. Two releases could coexist and fight over ownership of the same resources (same failure mode as the metrics-server collision in §6). | Delete the research release (`helm uninstall robot-shop -n robot-shop`) before implementation runs the real `make setup-robot-shop`, so only one release (`roboshop`, per `.env`) ever exists. |
| MySQL seed-data hang (research.md §4d) | Root cause not confirmed after ruling out two theories (strict mTLS, Istio's `mysql`-port protocol filter); third theory (something before Envoy — NetworkPolicy/CNI/conntrack) unconfirmed. | Treat as a known, bounded risk per Constitution Principle X. Either fix within a fixed timebox during implementation, or accept missing seed data for this story and file a follow-up. Not grounds to block `gate:plan-approved` — the store itself works without it. |
| `mysql-service.yaml` port rename (`mysql` → `tcp-mysql`) | Applied during research as a ruled-out fix attempt for the above; didn't fix it, but is harmless and arguably still correct Istio convention. | Keep it (correct protocol convention either way) unless the Architect prefers reverting since it's evidentially not the fix. |

## Files changing

| File | Change | Rationale |
|---|---|---|
| `makefile` | Uncomment `setup-robot-shop` and `setup-hotrod`; add `setup-optional-otel` as a dependency of `setup-hotrod` (or of `setup-observability`); extend `setup-gateway`'s AKS branch to apply both apps' Gateway/VirtualService manifests | Restore disabled commands (FR-001/FR-004); close HotROD's silent telemetry gap; implement FR-011 |
| `app/robot-shop/helm/templates/mysql-statefulset.yaml`, `mysql-config.yaml`, `mysql-secret.yaml`, `mysql-service.yaml`, `mysql-seeed-job.yaml` | Change `eq .Values.stack_mode "local"` → `ne .Values.stack_mode "eks"` | Chart defect fix (research.md §4b); makes in-cluster MySQL render for `aks`, matching FR-003, without changing `eks` behavior |
| `app/hotrod/istio-gateway.yaml` (new) | Gateway + VirtualService for HotROD, host-scoped to avoid colliding with Robot Shop's `hosts: "*"` | FR-011, verified working in research |
| `app/robot-shop/Istio/gateway.yaml` | No change — reused as-is | Already correct; applied live and confirmed reachable |
| `docs/architectural-decisions.md` | New ADR: host-based VirtualService separation chosen over per-app dedicated Gateway or path-prefix rewriting (rejected: path rewriting risks breaking HotROD's internal asset links, untested) | Record the design decision and rejected alternative per repo convention |

## Constitution check (v1.4.0)

| Principle | Satisfied? | Evidence |
|---|---|---|
| **I. Re-runnable Scripts** | Mostly ✓, one gap | Namespace creation and `helm upgrade --install` are idempotent by construction. Gap found in research: the seed-data Job's pod template is immutable, so a second run fails unless the old Job is deleted first (see Approach #4) — must be fixed in tasks.md, not yet fixed. |
| **II. Pinned Versions** | ✓ | Chart version 1.1.0 pinned in `Chart.yaml`; no version changes made by this story. |
| **III. One Configuration Surface** | ✓ | `APP_NS`, `APP_RELEASE_NAME`, `APP_SETUP_TIMEOUT`, `LOCAL_APP_SETUP_TIMEOUT`, `STACK_MODE` all already in `.env`; no new hand-edited values introduced. |
| **IV. No Secrets in Git** | ✓ | `mysql_root_password` passed via `--set` from `.env`-sourced value; no credentials in chart templates or manifests. |
| **V. Workload Placement Contract** | ✓, verified live | `workload=app`/`workload=persistent` labels and matching taints confirmed on the real cluster (research.md §2); Robot Shop's `values.yaml` already had correct `nodeSelector`/`tolerations` for MySQL — only the render condition was the bug, not placement. HotROD's `nodeSelector: workload: app` already correct, no fix needed. |
| **VI. Specs Without Technical Detail** | ✓ | `spec.md` describes outcomes (deploy, reach, observe) without commands/config; verified by re-reading the current file. |
| **VII. Plain Language Everywhere** | Mostly ✓ | Two judgment calls flagged to the Architect during spec review (naming Grafana/Prometheus/Loki; `workload=app`/`persistent` syntax inside the Clarifications record) — not re-litigated here since spec.md is already through one review round. |
| **VIII. Try It Before You Plan It** | Mostly ✓, one gap found and closed | This plan is built from live command output against the real AKS cluster (research.md, plus the corrections table above). One real gap in this claim was caught by architect review: `data-model.md` never captured Robot Shop's actual per-service resource requests/limits, despite FR-006 requiring exactly that measurement — corrected in `data-model.md` (now cites `values.yaml` directly, and surfaces that `mongodb`/`redis` have no resource limits at all, a pre-existing gap now tracked as T026). |
| **IX. Author In Steps, Developer in the Loop** | Partial — see note | spec.md and research.md were authored section-by-section with developer approval at each step. This plan.md file itself was written in one pass at the developer's explicit request ("read and adjust everything") after an incremental first section (Summary + Technical Context) had already been proposed and was mid-review — a deliberate, requested exception, not an oversight. Flagging here rather than silently claiming full compliance. |
| **X. Converge to the Agreed Scope, Then Stop** | N/A yet | No implementation exists yet to converge against. The MySQL seed-data gap is pre-declared here as an accepted, bounded risk (see Open items) so that convergence later doesn't turn it into an open-ended hunt. |

## Complexity table

| Violation | Disposition |
|---|---|
| IX (partial) | This file was written in one pass, not section-by-section, at the developer's explicit request after the first section was already proposed and under review. Accepted as a one-time exception per the developer's direct instruction, not a process failure — recorded here for the Architect's visibility. |

## Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Two Helm releases (`robot-shop` research vs. `roboshop` real) collide over the same resources | HIGH | Delete the research release before implementation's first real `make setup-robot-shop` run (see Open items). Add as an explicit task in tasks.md. |
| MySQL seed-data job never completes | MEDIUM | Documented, bounded risk (research.md §4d). Store functions without it. Time-box further investigation during implementation; do not let it block convergence indefinitely (Principle X). |
| Job immutability breaks re-runs | MEDIUM | `kubectl delete job --ignore-not-found` before the seeder apply, or convert to a Helm hook with delete-before-create policy. Task to be added in tasks.md. |
| HotROD telemetry silently goes nowhere if `setup-optional-otel` is skipped | LOW | Make it an explicit dependency of `setup-hotrod` in the makefile, not a silent prerequisite. |
| Gateway host collision if a third app is added later reusing `hosts: "*"` | LOW | Documented in the new ADR; future stories should follow the host-scoped pattern HotROD established, not Robot Shop's wildcard. |

## Verification

1. **Robot Shop up**: `kubectl get pods -n robot-shop` → all pods `Running`/`Ready` (MySQL StatefulSet included)
2. **HotROD up**: `kubectl get pods -n hotrod` → `1/1 Running`
3. **Reachability (FR-011)**: `curl http://<ingress-IP>/` → Robot Shop responds `200`; `curl -H "Host: hotrod.demo.local" http://<ingress-IP>/` → HotROD responds `200`
4. **Idempotency (FR-008)**: re-run `make setup-robot-shop` and `make setup-hotrod` → both exit 0, no new resources, no errors (seed-data Job immutability fix must be in place first)
5. **Observability (FR-009)**: generate traffic in both apps; confirm Prometheus/Grafana show metrics and Loki shows logs within a few minutes
6. **Local unaffected (FR-010)**: compare `make setup-local` behavior before and after the chart fix — since the fix changes `local`'s render condition too (from `eq "local"` to `ne "eks"`, which still includes `local`), confirm no behavioral difference on `k3d`
