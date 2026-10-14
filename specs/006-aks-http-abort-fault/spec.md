# Feature Specification: HTTP Abort Fault for the Demo Shop on Azure

**Feature Branch**: `006-aks-http-abort-fault`

**Created**: 2026-10-14

**Status**: Approved — all six sections approved during authoring (constitution principle IX); specification quality validation passed; `gate:spec-approved` granted on PR #117. Edited after the gate during `/speckit-analyze` (FR-013 narrowed; EC-001 and EC-002 settled from planning research); these edits need the Architect's re-approval.

**Input**: [Issue #113](https://github.com/infracloudio/sre-stack/issues/113) — "Trigger an HTTP abort fault on robot-shop on AKS with one command"

## Clarifications

### Session 2026-10-14

- Q: When the start or revert command finishes, should it check that the fault actually took effect before reporting success? → A: Yes; both commands send a few test requests to ratings and report success only when they see the expected result (errors after start, normal answers after revert); otherwise they stop with a message.
- Q: Should there be a third documented command that only reports whether the fault is currently active, without changing anything? → A: Yes; a read-only status command reports "fault active" or "fault not active" using the same test-request check as FR-012.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start the fault with one command (Priority: P1)

As a person demonstrating the demo shop (robot-shop) on Azure, I want to run one documented command that makes the shop's ratings service start refusing requests with server errors, so I can show a realistic outage on the monitoring dashboards. An "HTTP abort" is a fault in which requests to a service fail immediately with a server error instead of reaching it.

**Why this priority**: Starting the fault is the core outcome of the issue; today Azure has no documented command that starts this fault and leaves it running until the presenter removes it.

**Independent Test**: On a running Azure demo shop with monitoring, run the documented start command, use the shop, and open the dashboards.

**Acceptance Scenarios**:

1. **Given** the demo shop and monitoring are running on Azure and no fault is active, **When** the person runs the documented start command, **Then** requests to the ratings service fail with server errors.
2. **Given** the fault has been started, **When** the person opens the dashboards during a 2-minute demo, **Then** the dashboards show the server errors for the ratings service.
3. **Given** the fault is already active, **When** the person runs the start command again, **Then** the command succeeds and the fault stays active as before.

---

### User Story 2 - Remove the fault with one command (Priority: P1)

As the same person, I want to run one documented command that removes the fault, so the shop recovers and I can show the recovery on the dashboards.

**Why this priority**: A demo that cannot be undone leaves the shop broken; the issue requires that reverting returns the shop to healthy.

**Independent Test**: With the fault active, run the documented revert command, use the shop, and open the dashboards.

**Acceptance Scenarios**:

1. **Given** the fault is active, **When** the person runs the documented revert command, **Then** requests to the ratings service succeed again and the dashboards show the errors stopping.
2. **Given** no fault is active, **When** the person runs the revert command, **Then** the command succeeds and changes nothing.

---

### User Story 3 - Find the instructions (Priority: P2)

As a person new to the project, I want the scenarios guide to explain how to start and remove this fault on Azure, so I can run the demo without asking anyone.

**Why this priority**: The issue names the missing guide; the fault itself (stories 1 and 2) is useful even before the guide is updated.

**Independent Test**: Follow only the scenarios guide, from a running Azure demo shop, to start and then remove the fault.

**Acceptance Scenarios**:

1. **Given** a running Azure demo shop, **When** a person follows the scenarios guide, **Then** they find the start command, the status command, the revert command, what to look for on the dashboards, and what must already be running.

### Edge Cases

- **EC-001 — No shop traffic**: With no traffic, the dashboards show no errors even though the fault is active, so an empty dashboard does not prove the fault failed. The project's load generator ends each run after one hour and is then started again automatically, so traffic can pause briefly mid-session. The guide tells the presenter how to confirm traffic is flowing and how to start the load generator. This follows FR-008 and SC-001.
- **EC-002 — Shop deployment re-run while the fault is active**: Re-running the demo shop's normal deployment touches the same ratings routing that the fault changes. Checked on the live cluster during planning: the fault survives the re-run as long as the shop's own ratings routing is unchanged, and the guide says so. If it is ever removed, running the start command again restores it (FR-004). This follows FR-008 and FR-010.
- **EC-003 — Presenter disconnects after starting**: The fault stays active until someone runs the revert command (FR-003). Anyone with access to the cluster can run it; nothing ties the fault to the person who started it. The status command tells anyone whether the fault is currently active (FR-013).
- **EC-004 — Ratings restarts while the fault is active**: The fault belongs to the ratings routing, not to a running copy of ratings, so it stays active when ratings is restarted, rescheduled or moved to another machine. This follows FR-003.
- **EC-005 — Wrong or incomplete cluster**: When the person is connected to a non-Azure cluster, to an Azure cluster without the shop, or the mesh is not running or the shop is not joined to it, the start, revert and status commands stop and change nothing (FR-006).
- **EC-006 — Old scenario 01 commands used on Azure**: Scenario 01's existing timed script removes the fault on its own after its timer and raises shop traffic, which would interfere with a demo started by the new command. The guide states that the new commands are the Azure way and the old commands are for EKS. This follows FR-008, FR-009 and FR-011.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On a running Azure demo shop, a person MUST be able to start the fault with one documented command; once started, every request to the ratings service fails with a server error.
- **FR-002**: A person MUST be able to remove the fault with one documented command; once removed, the ratings service answers requests normally again.
- **FR-003**: Once started, the fault MUST stay active until the person runs the revert command; it MUST NOT remove itself after a set time.
- **FR-004**: Running the start command while the fault is active, or the revert command while no fault is active, MUST succeed and leave the shop in the same state.
- **FR-005**: The fault MUST be placed only on the ratings service. While it is active, the other demo-shop services MUST keep answering requests normally, except requests they pass on to the ratings service, which fail as well (the knock-on failure the demo shows).
- **FR-006**: If the person's environment is not connected to an Azure cluster running the demo shop, or the service mesh is not running, or the shop is not joined to it, the start, revert and status commands MUST stop with a message saying what is missing, and MUST change nothing.
- **FR-007**: The server errors caused by the fault MUST be visible on the dashboards already installed by the Azure monitoring setup, without adding new dashboards.
- **FR-008**: The scenarios guide MUST explain, for Azure: what must already be running, the start command, the status command, what to look for on the dashboards, and the revert command.
- **FR-009**: The files of the EKS scenarios 01, 02 and 04, including scenario 01's existing commands, MUST NOT change. Where Azure needs behavior different from EKS, it MUST be provided separately. Files shared with EKS (the project's settings file and top-level commands) MAY gain Azure-only additions, but their existing settings and commands MUST stay as they are.
- **FR-010**: Setting up Azure and deploying the demo shop MUST behave as today when the fault has not been started.
- **FR-011**: The project's plain-language Azure guide MUST describe the new start, status and revert commands for this fault in place of its current, timed scenario 01 instructions, so the two guides do not give conflicting steps.
- **FR-012**: After making its change, the start and revert commands MUST each send a few test requests to the ratings service and report success only when they show the expected result: server errors after start, normal answers after revert. If the result does not appear, the command MUST stop with a message saying what it saw.
- **FR-013**: A person MUST be able to run one documented status command that changes nothing and reports whether the fault is active, using the same test-request check as FR-012. If this fault is not set and ratings is failing for another reason, the status command MUST say so instead of reporting the fault as active. While the fault is set, every request is stopped before it reaches ratings, so status cannot tell whether ratings itself is healthy; the revert command's own check (FR-012) shows that.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Within 60 seconds of running the start command, the dashboards show server errors for the ratings service, while the shop is receiving traffic.
- **SC-002**: While the fault is active, 10 out of 10 requests sent to the ratings service fail with a server error, and 10 out of 10 requests sent to each other demo-shop service that takes web requests still succeed, not counting requests that service passes on to ratings.
- **SC-003**: Within 10 seconds of running the revert command, 10 out of 10 requests sent to the ratings service succeed; within 60 seconds the dashboards show the ratings error count falling, and within 2 minutes it is back to zero.
- **SC-004**: A presenter can start the fault, point to the errors on the dashboards, revert it, and point to the recovery, all within one 2-minute demo.
- **SC-005**: Each command, including its own check of the result (FR-012), finishes in under 30 seconds.
- **SC-006**: A person new to the project, using only the scenarios guide, completes one full start-and-revert cycle on a running Azure demo shop on the first attempt without asking for help.
- **SC-007**: Running the start command twice in a row, or the revert command twice in a row, ends without errors and leaves the shop in the same state as running it once.
- **SC-008**: Zero lines change in the files of the EKS scenarios 01, 02 and 04; in files shared with EKS, every existing line stays unchanged and only Azure-only lines are added.
- **SC-009**: After a normal Azure setup in which the fault was never started, the ratings service shows zero server errors over 5 minutes of shop traffic.

## Assumptions

- The normal Azure setup installs, in order, the cluster, the service mesh (the layer that routes traffic between the shop's services), the monitoring stack with its dashboards, and then the demo shop with every one of its long-running services joined to the mesh (only the one-time database-loading task stays outside it). The monitoring stack collects request measurements from the mesh for every shop service.
- The shop receives traffic during the demo, from the project's optional load generator (the Azure setup prints how to start it but does not start it) or from a person using the shop. The load generator sends its traffic to the shop's front end. Starting the fault does not change the amount of traffic.
- The shop's front end passes every ratings request on to the ratings service, and the load generator fetches and submits ratings through the front end on every shopping visit; this is defined in the shop's published application code, not in this project's files. The project's load generator does not switch on the shop's built-in deliberate-error traffic.
- The person running the commands can manage the Azure cluster from their machine and uses the project's shared settings file unchanged, which names the shop's location in the cluster.
- One presenter uses the fault at a time; two people starting and reverting it at once on the same cluster is not handled (chosen default).
- On Azure, the shop's normal deployment sends all ratings traffic straight to the ratings service with no extra rules; reverting restores exactly that.
- Verification happens on a live Azure cluster only; EKS and local clusters are not tested (out of scope per the issue).
- Scenario 01's existing EKS commands, including their known faults, are left as they are (FR-009); fixing them for EKS is a separate story.

## Out of Scope

From the issue:

- Increased latency on the backend database (follow-up story).
- A pod running out of memory (follow-up story).
- Verifying on EKS or on local clusters.
- hotrod.
- The hardcoded database credentials in scenario 02 (separate story); scenario 02 intentionally degrades the database and is not repaired here.

Decided while writing this specification:

- Fixing scenario 01's existing EKS commands, including their outdated shop location and the script that fails under a plain shell (FR-009).
- Scenario 01's second case (ratings slow to become ready) on Azure.
- Faults on any service other than ratings, or failing only part of the ratings requests.
- Starting, stopping or changing shop traffic as part of the fault commands.
- New dashboards, panels or alerts (FR-007).
- Coordinating two presenters using the fault at the same time on one cluster.
