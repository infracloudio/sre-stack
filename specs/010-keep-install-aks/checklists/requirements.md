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
- [x] Requirements are testable and unambiguous (12 requirements)
- [x] Success criteria are measurable (10 criteria; SC-005, SC-007, SC-008, SC-009 and SC-010 are pass/fail, the rest have numbers)
- [x] Success criteria are technology-agnostic
- [x] All acceptance scenarios are defined (3 stories, 10 scenarios)
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

- Proven by hand in research on the real cluster (`research.md`, Findings 6 to 8), not yet by the command: four parts Running, password refused when empty, secrets surviving removal, empty database after reinstall, no usage reports from server or browser.
- Not proven anywhere, implementation must prove: FR-008 (second run changes nothing), FR-009 (missing key file), edge cases 1, 2, 3 and 6, and the monitoring-machine headroom (seen, not measured).
- The 5-minute target in SC-001 is a target. Research installs reached Running in about 80 to 115 seconds.
- Departures from the accepted issue #123: the login stays in story 6a (decided by the developer on 2026-10-29). The busybox pin is no longer narrowed: the AD-013 override renders (research.md Finding 9, a developer decision after Architect consultation, not an Architect approval, 2026-11-05). The issue text still carries the older wording and needs updating before `gate:spec-approved`.
- Verified by rendered Helm output (`helm template`, dummy values, research.md Findings 9, 11, 13 and 14): the busybox override and the unpinned default it replaces, the hook image line, the MySQL digest line, the database Secret keys and `items` restriction, and the backend `secretKeyRef` for `OPENAI_API_KEY`.
- Supported by registry metadata or image contents, not executed (Findings 10, 12): the digests of `alpine/k8s:1.34.11`, `busybox:1.38.0` and `mysql:8.4.13`; the presence of `sh`, `grep`, `xargs`, `kubectl` and `nc` in the layers; the October smoke test of the Fireworks model.
- Source read at the pinned versions, not executed (Findings 15, 16): the chart gives one ServiceAccount to every Keep pod and the cleanup hook, and the Role is bound to it; the backend's Kubernetes secret store needs Secret rights; the frontend route's OpenAI SDK reads `OPENAI_BASE_URL` from the environment (openai 4.86.2); the backend's Secret code does not appear to call list, but the existing cleanup hook's `kubectl get secrets` does, and the chart exposes no setting to change the Role (Finding 17). Separate Roles through post-render are untested.
- Source read and RBAC documentation read, not executed (Findings 18, 19): RBAC cannot narrow the cleanup hook's or the backend's Secret grants to `keep-*` names, so the residual namespace-wide Secret access remains under any design considered; the optional MySQL cleanup CronJob is disabled by default and would expect a passwordless root login.
- Still requires runtime validation on the cluster or in a running container: the second run changing nothing (FR-008), the missing key file (FR-009), the hook actually deleting `keep-*` Secrets with `alpine/k8s` (kubectl not executed), the busybox init container waiting on `keep-database`, `OPENAI_BASE_URL` reaching Fireworks, the thinking-only token limit, the `sre-keep-ai-env` Secret surviving uninstall (issue live check 2), the frontend key staying out of browser code at runtime, and, for the ServiceAccount decision, whether the hook still deletes `keep-*` Secrets and reports failure without `list` (Finding 17) and whether any non-backend pod works with no token. Also still to test: whether an operator-run cleanup outside the cluster can replace the in-cluster hook (Finding 18), and whether the optional MySQL cleanup job fails under the root password (Finding 19).
- Pending before `gate:spec-approved` (see Decision status below): Architect acceptance of the frontend Fireworks Secret configuration (spec Open questions), AD-016 acceptance (Proposed; it covers the proposed exception that keeps `fireworks.key`, and the backend and frontend Fireworks wiring), and Architect review and explicit acknowledgement of the residual namespace-wide Secret risk under the shared ServiceAccount (AD-016; research.md Finding 18). Nothing in AD-016 is adopted until the Architect accepts it.
- Length is about 1,750 words against the 400-word target. The rules say targets never override acceptance criteria. The developer reviewed each section during drafting. This is developer review only, not approval. Architect approval and `gate:spec-approved` are still pending.
- Not verified: whether the web page sends error reports to a third party. It is named in Known limits.

## Decision status

Completed developer decisions (recorded in the documents; none is an Architect approval):

- The start-up wait container is pinned through a values override, `busybox:1.38.0` by digest, as AD-013 point 3 sets (research.md Finding 9).
- The cleanup image is `alpine/k8s:1.34.11` by digest (research.md Finding 10).
- The database Secret names and keys follow AD-013, and the password is generated with `openssl rand -hex 24`.
- The Fireworks base URL is `https://api.fireworks.ai/inference/v1`, and the model is the one named in research.md Finding 12.
- The key name `fireworks.key` is kept for the backend Fireworks Secret (AD-016 point 1).
- The chart's existing shared ServiceAccount is retained for the initial implementation, subject to Architect review (AD-016 point 4; research.md Finding 18). Post-render separation is not implemented.

Pending Architect approval or acknowledgement (`gate:spec-approved` remains pending):

- AD-016 acceptance. Its status is Proposed.
- Acceptance of the proposed exception to AD-008 for the backend Fireworks Secret.
- Acceptance of the frontend Fireworks Secret configuration (`sre-keep-ai-frontend`, key `OPEN_AI_API_KEY`, with `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME`).
- Architect review of the shared ServiceAccount and explicit acknowledgement of the residual namespace-wide Secret risk. Retaining the shared ServiceAccount does not mitigate this risk.
- Explicit Architect acknowledgement of the cleanup image risk. The cleanup image `alpine/k8s:1.34.11` is a third-party image that runs as root (its image configuration sets no user). This introduces a security and software supply-chain risk. Pinning the image by digest does not eliminate it. The acknowledgement is requested and remains outstanding (research.md Finding 10; AD-016).
- Acceptance of FR-012, the frontend configuration (`OPEN_AI_API_KEY` from Secret `sre-keep-ai-frontend`, `OPENAI_BASE_URL`, `OPENAI_MODEL_NAME`), tested by SC-010 (spec.md).

Untested alternatives, not adopted: post-render ServiceAccount separation (AD-016 option 2) and operator-run cleanup outside the cluster (AD-016 option 3).
