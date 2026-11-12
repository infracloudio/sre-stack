# Specification Quality Checklist: Install Keep on AKS with one command

**Purpose**: Validate specification completeness and quality before planning
**Created**: 2026-10-29
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs). Scan for tool, command and file names: `kubectl` and "chart" were removed. Left on purpose: the `keep-` secret-name prefix (Problem and one edge case), because the prefix is the behavior being described, and the AD-008 reference. Also left on purpose from 2026-11-05: the Secret names and keys (`sre-keep-db`, `DATABASE_CONNECTION_STRING`, `mysql-root-password`, `sre-keep-ai-env`, `fireworks.key`) and the image digests, because AD-008, AD-013 and AD-016 bind them.
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain (count: 0)
- [x] Requirements are testable and unambiguous (13 requirements, FR-001 to FR-013)
- [x] Success criteria are measurable (11 criteria, SC-001 to SC-011; SC-005, SC-007, SC-008, SC-009, SC-010 and SC-011 are pass/fail, the rest have numbers)
- [x] Success criteria are technology-agnostic
- [x] All acceptance scenarios are defined (3 stories, 11 scenarios)
- [x] Edge cases are identified (6, closed at approval)
- [x] Scope is clearly bounded (6 out-of-scope items)
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria. FR-005 and FR-006 had none; SC-008 (standard storage) and SC-009 (no secret value in files, secrets check passes) were added on 2026-10-29 at the developer's go-ahead and are cross-referenced from the requirements.
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification, except the bound Secret names, keys and image digests listed under Content Quality

## Notes

Passing is not the same as proven:

- Proven by hand in research on the real cluster (`research.md`, Findings 6 to 8), not yet by the command: four parts Running, password refused when empty, secrets surviving removal, empty database after reinstall, no usage reports from server or browser. Finding 6 used a cleanup hook image that is no longer selected; that is historical evidence.
- Not proven anywhere, implementation must prove: FR-008 (second run changes nothing), FR-009 (missing key file), edge cases 1, 2, 3 and 6, and the monitoring-machine headroom (seen, not measured).
- The 5-minute target in SC-001 is a target. Research installs reached Running in about 80 to 115 seconds.
- Departures from the accepted issue #123: the login stays in story 6a (decided by the developer on 2026-10-29). The busybox pin is no longer narrowed: the AD-013 override renders (research.md Finding 9, a developer decision after Architect consultation, not an Architect approval, 2026-11-05). The manual Secret cleanup replaces the uninstall cleanup hook (AD-016 decision 5; research.md Finding 20). The issue text still carries the older wording and needs updating before `gate:spec-approved`.
- Verified by rendered Helm output (`helm template`, dummy values, research.md Findings 9, 11, 13 and 14): the busybox override and the unpinned default it replaces, the MySQL digest line, the database Secret keys and `items` restriction, and the backend `secretKeyRef` for `OPENAI_API_KEY`.
- Supported by registry metadata or image contents, not executed (Findings 9, 12, 13): the digests of `busybox:1.38.0` and `mysql:8.4.13`; the presence of `sh`, `grep`, `xargs`, `nc` in the busybox layer; the October smoke test of the Fireworks model. The `alpine/k8s:1.34.11` digest and layer listing (Finding 10) are historical: the image is not used.
- Source read at the pinned versions, not executed (Findings 15, 16, 17): the chart gives one ServiceAccount to every Keep pod, and to the cleanup hook while the chart still renders it; the backend's Kubernetes secret store needs `create`, `get`, `patch` and `delete` on Secrets; the frontend route's OpenAI SDK reads `OPENAI_BASE_URL` from the environment (openai 4.86.2); the backend's Secret code does not appear to call `list`.
- Source read and RBAC documentation read, not executed (Findings 18, 19, 20): the backend's namespace-wide Secret permissions remain a residual risk under every design considered; the optional MySQL cleanup CronJob is disabled by default and would expect a passwordless root login; the `keep-` prefix basis for manual cleanup is partly verified (see Decision status).
- Still requires runtime validation on the cluster or in a running container: the second run changing nothing (FR-008), the missing key file (FR-009), the busybox init container waiting on `keep-database`, `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME` reaching Fireworks from the backend and the frontend, the thinking-only token limit, the `sre-keep-ai-env` and `sre-keep-ai-frontend` Secrets surviving `helm uninstall`, the frontend key staying out of browser code at runtime, and the manual cleanup procedure (FR-013), which has not been run on any namespace.
- Uninstall mechanism: the documented uninstall command is `helm uninstall keep -n <namespace> --no-hooks` (AD-016 decision 6; research.md Finding 20). The chart still renders the pre-delete hook, unchanged, and `--no-hooks` prevents its execution. A plain `helm uninstall` would still run it. This was checked from Helm documentation and the local CLI help, not run against AKS. Enforcement in the scripts and runbook is not yet implemented. SC-011(a) checks that the documented command includes the flag, not that the rendered manifest is absent.
- Length is about 1,750 words against the 400-word target. The rules say targets never override acceptance criteria. The developer reviewed each section during drafting. This is developer review only, not approval. Architect approval and `gate:spec-approved` are still pending.
- Not verified: whether the web page sends error reports to a third party. It is named in Known limits.

## Decision status

Completed developer decisions (recorded in the documents; none is an Architect approval):

- The start-up wait container is pinned through a values override, `busybox:1.38.0` by digest, as AD-013 point 3 sets (research.md Finding 9).
- The database Secret names and keys follow AD-013, and the password is generated with `openssl rand -hex 24`.
- The Fireworks base URL is `https://api.fireworks.ai/inference/v1`, and the model is the one named in research.md Finding 12.
- The key name `fireworks.key` is kept for the backend Fireworks Secret (AD-016 decision 1; the exception itself is pending).
- The chart's existing shared ServiceAccount is retained for the initial implementation, subject to Architect review (AD-016 decision 4; research.md Finding 18). Post-render separation is not implemented.

Recorded Architect agreement (this is agreement to remove the hook only; it is not acceptance of AD-016 or of any other decision):

- Uninstall mechanism (AD-016 decision 6): `helm uninstall keep -n <namespace> --no-hooks`, with no Helm post-renderer, no fork or modification of the upstream chart, and Helm 3 supported. This is a decision on the mechanism only. It is not acceptance of AD-016.
- The Architect agreed (recorded 2026-11-06) to remove the Helm uninstall cleanup hook that used `alpine/k8s:1.34.11`. Administrator-operated manual Secret cleanup is the selected operational approach (AD-016 decision 5; research.md Finding 20; spec.md FR-013).
- The request for Architect acknowledgement of the cleanup-image risk is withdrawn, because the image is not used.

Pending Architect approval or acknowledgement (`gate:spec-approved` remains pending):

- AD-016 acceptance as a whole. Its status is Proposed.
- Acceptance of the proposed exception to AD-008 for the backend Fireworks Secret (`fireworks.key`).
- Acceptance of the frontend Fireworks Secret configuration (`sre-keep-ai-frontend`, key `OPEN_AI_API_KEY`, with `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME`; FR-012 and SC-010).
- Architect review of the shared ServiceAccount and explicit acknowledgement of the residual namespace-wide backend Secret risk (`create`, `get`, `patch` and `delete` on namespace Secrets).

Outstanding validation (not run):

- Test `helm uninstall keep -n <namespace> --no-hooks` on a throwaway namespace, and confirm that the pre-delete hook does not execute. No cluster command has been run.
- Implement enforcement of `--no-hooks` in the installation and uninstallation scripts and in the operational runbook (not started).
- Verify that every Keep-generated Secret in the `keep` namespace begins with `keep-`, including any write path the source search may have missed (AD-016 manual cleanup section; research.md Finding 20). A transient `none-*` Secret from `prepare_provider` is a known gap.
- Run the manual cleanup procedure on a throwaway namespace before relying on it (research.md Finding 20).

Untested alternative, not adopted: post-render ServiceAccount separation (AD-016 option 2).
