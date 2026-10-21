# Feature Specification: Out-of-Memory Kill of a Demo Shop Pod on Azure

**Feature Branch**: `007-aks-oom-kill`

**Created**: 2026-10-21

**Status**: Draft — all six sections approved during authoring (constitution principle IX); clarified 2026-10-21 (two answers); quality validation passed; amended 2026-10-21 after `/speckit-analyze` (Out of Scope, FR-002, FR-010, FR-012 and Assumptions reworded; developer approved the edits while the Architect was unavailable); awaiting the Architect's `gate:spec-approved`, who should confirm those amendments. Story acceptance was confirmed by the developer in session on 2026-10-21; the `intent:accepted` label is still to be added to [issue #114](https://github.com/infracloudio/sre-stack/issues/114).

**Input**: [Issue #114](https://github.com/infracloudio/sre-stack/issues/114) — "Trigger an OOM kill of a robot-shop pod on AKS with one command"

## Clarifications

### Session 2026-10-21

- Q: If the shop has been deployed again, or its memory allowance has been changed by someone else, while the fault is active, which allowance should the revert command restore? → A: The allowance the shop is installed with right now; the shop's own definition stays the source of truth, and no value recorded at start time is replayed.
- Q: While the fault is active but the pod is waiting for its next restart (the cluster has backed off), should the status command still report the fault as active? → A: Yes; status reports "fault active" as usual, because the lowered allowance and the recorded out-of-memory kill are still true and the pause is normal cluster behaviour.
- Q: On the cluster, no dashboard the monitoring setup installs shows a pod's restart count or its out-of-memory kills, so FR-011 as first written could not be met. Should FR-011 change? → A: Yes. The fault is shown by adding a section to a dashboard the monitoring setup already installs and the demo already opens. Creating a new dashboard stays out of scope, which keeps FR-011's own promise that this story adds nothing to install or run.
- Q: The Restarts section built for FR-011 only watches the cart container, but any pod can restart or be killed for running out of memory. Should it cover every pod? → A: Yes (developer, 2026-10-21, after seeing the section live). The section shows restarts and out-of-memory kills for every pod in every namespace, over the last 5 minutes, and names the pod. No memory-usage panel is added. The fault itself still only touches cart.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Make a shop pod run out of memory with one command (Priority: P1)

As a person demonstrating the demo shop (robot-shop) on Azure, I want to run one documented command that makes the shop's cart pod run out of memory and be killed by the cluster, so that a short demo can show a pod that has been killed for running out of memory and the restarts that follow on the monitoring dashboards.

A "pod" is one running copy of a service; the shop runs a few of these, one per service. An "out of memory kill" is what the cluster does when a container asks for more memory than its allowance: it stops the container and marks it with the status `OOMKilled`. The restart counter for that pod then goes up as the cluster starts it again.

**Why this priority**: Starting the fault is the core outcome of the issue. Today Azure has no documented way to make a shop pod run out of memory, so no demo there can show that status or its restarts.

**Independent Test**: On a running Azure demo shop with monitoring, run the documented start command, watch the shop's pods, and open the dashboards. This alone delivers the value of the story.

**Acceptance Scenarios**:

1. **Given** the demo shop and monitoring are running on Azure and no fault is active, **When** the person runs the documented start command, **Then** the cart pod is killed for running out of memory, shows the `OOMKilled` status, and its restart count begins to climb.
2. **Given** the fault has been started, **When** the person opens the dashboards during a 2-minute demo, **Then** the pod's restarts and its out-of-memory kills are visible on the dashboards already installed by the Azure monitoring setup, with nothing new added.
3. **Given** the fault is already active, **When** the person runs the start command again, **Then** the command succeeds and the pod stays in the same failing state.

---

### User Story 2 - Return the shop to normal with one command (Priority: P1)

As the same person, I want to run one documented revert command that gives the pod its original memory allowance back, so that the shop recovers and I can show on the dashboards that the restarts have stopped.

**Why this priority**: A demo that cannot be undone leaves a broken shop behind. The issue requires that reverting restores the pod's resources and the shop returns to healthy.

**Independent Test**: With the fault active, run the documented revert command, watch the shop's pods, and open the dashboards.

**Acceptance Scenarios**:

1. **Given** the fault is active, **When** the person runs the documented revert command, **Then** the pod holds its original memory allowance again, stays running without further out-of-memory kills, its restart count stops climbing, and the shop answers requests normally.
2. **Given** no fault is active, **When** the person runs the revert command, **Then** the command succeeds and changes nothing.

---

### User Story 3 - Check whether the fault is active (Priority: P2)

As the same person, I want one documented command that tells me whether the cart pod is currently being killed for running out of memory because of this fault, without changing anything, so that I can tell what state I am in before a demo and after someone else has used the cluster.

**Why this priority**: The fault stays on until someone reverts it, so anyone arriving at the cluster needs a way to find out which state it is in. #113 set this convention for the Azure faults; this story follows it.

**Independent Test**: With the fault active, run the documented status command and read its answer; run it again after reverting.

**Acceptance Scenarios**:

1. **Given** the fault is active, **When** the person runs the documented status command, **Then** it reports that the fault is active and changes nothing.
2. **Given** no fault is active, **When** the person runs the status command, **Then** it reports that the fault is not active and changes nothing.
3. **Given** the cart pod is being killed for running out of memory for a reason other than this fault, **When** the person runs the status command, **Then** it says the fault is not active and that the pod is failing for another reason, instead of claiming the fault is on.

---

### User Story 4 - Find the instructions (Priority: P2)

As a person new to the project, I want the scenarios guide to explain how to start, check and revert this fault on Azure, so I can run the demo without asking anyone.

**Why this priority**: The issue names the missing guide. The fault itself (stories 1 to 3) is useful before the guide exists, but the demo is only repeatable once it is written down.

**Independent Test**: Follow only the scenarios guide, starting from a running Azure demo shop, to start the fault, check it, and then revert it.

**Acceptance Scenarios**:

1. **Given** a running Azure demo shop, **When** a person follows the scenarios guide, **Then** they find what must already be running, the start command, the status command, the revert command, and what to look for on the dashboards.

---

### Edge Cases

- **EC-001 — No shop traffic**: The pod may take longer to reach the lowered allowance, or may never reach it, when nobody is using the shop. An empty dashboard then does not prove the fault failed. The guide tells the presenter how to confirm traffic is flowing and how to start the load generator. This follows FR-009 and SC-001.
- **EC-002 — Shop deployed again while the fault is active**: Re-running the normal shop deployment may put the pod's original allowance back, clearing the fault without anyone asking for it. Running the start command again restores it, and the revert command then finds the allowance already correct, confirms that, and still succeeds (FR-008). The guide says so. This follows FR-004 and FR-008.
- **EC-003 — Presenter disconnects after starting**: The fault stays active until someone runs the revert command (FR-004). Anyone with access to the cluster can run it; nothing ties the fault to the person who started it. The status command tells anyone which state the cluster is in (FR-003).
- **EC-004 — The pod is restarted, rescheduled or moved**: The fault belongs to the cart pod's definition, not to one running copy, so it survives the pod being replaced or moved to another machine. This follows FR-004.
- **EC-005 — Wrong or incomplete cluster**: When the person is connected to a non-Azure cluster, cannot reach a cluster, or the shop or its cart service is not deployed, the start, status and revert commands stop and change nothing (FR-007).
- **EC-006 — Cart is failing for its own reasons**: Cart may run out of memory at its original allowance because of a real problem. The status command must not claim the fault is active in that case (FR-010), and the revert command must not present that failure as something it fixed (FR-008).
- **EC-007 — Restarts slow down over time**: The cluster waits longer before each restart of a container that keeps failing, so the restart count climbs quickly at first and then in bigger steps. A presenter who waits a while sees fewer new restarts even though the fault is still active. The guide says the count is still climbing, and the status command is the reliable answer, still reporting the fault as active during the wait (FR-010). This follows FR-003 and SC-002.
- **EC-008 — Someone edits cart's allowance by hand**: If a person changes the pod's allowance while the fault is active or after it, the revert command still leaves the allowance the shop is installed with, not whatever was typed last and not a value recorded when the fault was started. This follows FR-008.
- **EC-009 — Old EKS scenario 04 or scenario 01 commands used on Azure**: Scenario 04's RabbitMQ memory squeeze needs the EKS tooling and does not run on Azure; scenario 01's EKS scripts change other parts of the shop and run on a timer. The guide states that the new commands are the Azure way and that the existing EKS scenario folders are for EKS. This follows FR-012 and FR-013.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On a running Azure demo shop, a person MUST be able to start the fault with one documented command; once started, the cart pod MUST be killed for using more memory than its allowance, MUST show the `OOMKilled` status, and MUST start again after each kill.
- **FR-002**: A person MUST be able to revert the fault with one documented command; once reverted, the cart pod MUST hold its original memory allowance again, MUST stay running without further out-of-memory kills, and its restart count MUST stop climbing (the replacement pod may start counting again from zero).
- **FR-003**: A person MUST be able to run one documented status command that changes nothing and reports whether the fault is active.
- **FR-004**: Once started, the fault MUST stay active until someone runs the revert command; it MUST NOT remove itself after a set time.
- **FR-005**: Running the start command while the fault is active, or the revert command while no fault is active, MUST succeed and leave the shop in the same state.
- **FR-006**: Only the cart pod's memory allowance MUST be changed. Every other demo-shop service MUST keep the allowance it had before the command ran, apart from requests they pass on to the cart service, which fail while cart is restarting (the knock-on failure the demo shows).
- **FR-007**: If the person's environment is not connected to an Azure cluster running the demo shop, or the cart service is not deployed, the start, status and revert commands MUST stop with a message saying what is missing, and MUST change nothing.
- **FR-008**: The revert command MUST leave the cart pod at the memory allowance the shop is installed with at the moment it runs, whether or not the fault is still active — including when the shop was deployed again while the fault was active, when the fault was never started, and when a person changed the allowance by hand. It MUST NOT replay an allowance recorded when the fault was started.
- **FR-009**: After making its change, the start and revert commands MUST each wait until they see the expected result before reporting success: an out-of-memory kill after start, a running pod with no further kills after revert. If the result does not appear, the command MUST stop with a message saying what it saw.
- **FR-010**: The status command MUST report the fault as active only when this fault is in place on the cart pod (a kill may still be pending just after start). If cart is being killed for another reason, status MUST say so instead of reporting the fault as active. While the fault is active but the pod is waiting between restarts, status MUST still report the fault as active: that wait is normal and the lowered allowance is still in place.
- **FR-011**: The out-of-memory kills and restarts MUST be visible on a dashboard that the Azure monitoring setup already installs and that the demo already opens. Showing them may mean adding a section to a dashboard it installs today; creating a new dashboard is out of scope. The section MUST show every pod in every namespace, not only cart: a restart or an out-of-memory kill of any pod appears there, named, within the last 5 minutes (the clarification of 2026-10-21).
- **FR-012**: The scenarios guide MUST explain, for Azure: what must already be running, the start command, the status command, what to look for on the dashboards, and the revert command. The project's Azure explainer page MUST also describe the fault and correct any statement the fault shows to be wrong for Azure.
- **FR-013**: The files of the EKS scenarios 01, 02 and 04 MUST NOT change. Where Azure needs behavior different from EKS, it MUST be provided separately. Files shared with EKS (the project's settings file and top-level commands) MAY gain Azure-only additions, but their existing settings and commands MUST stay as they are.
- **FR-014**: Setting up Azure and deploying the demo shop MUST behave as today when the fault has never been started.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Within 60 seconds of running the start command, the cart pod shows the `OOMKilled` status and its restart count is at least 1, while the shop is receiving traffic.
- **SC-002**: Within 3 minutes of running the start command, the cart pod has been killed for running out of memory at least 3 times, so a presenter can point at a restart count that is still climbing rather than a single old event.
- **SC-003**: Within 60 seconds of running the revert command, the cart pod holds its original memory allowance, is running, and its restart count has stopped climbing; within 2 minutes the dashboards show no new out-of-memory kills and the shop answers requests normally.
- **SC-004**: A presenter can start the fault, point to the kills and restarts on the dashboards, revert it, and point to the recovery, all within one 2-minute demo.
- **SC-005**: Each command, including its own check of the result (FR-009), finishes in under 90 seconds.
- **SC-006**: The status command gives the correct answer in both states, 10 times out of 10, in under 10 seconds each time, and never changes anything.
- **SC-007**: Following only the scenarios guide, the owner completes one full start, check and revert cycle on a running Azure demo shop on the first attempt without needing anything outside the guide.
- **SC-008**: Running the start command twice in a row, or the revert command twice in a row, ends without errors and leaves the shop in the same state as running it once.
- **SC-009**: Zero lines change in the files of the EKS scenarios 01, 02 and 04; in files shared with EKS, every existing line stays unchanged and only Azure-only lines are added.
- **SC-010**: After a normal Azure setup in which the fault was never started, zero shop pods show the `OOMKilled` status over 5 minutes of shop traffic.
- **SC-011**: With any pod other than cart restarting or being killed for running out of memory, the Restarts section on the Application Dashboard shows that pod by name within 2 minutes, and shows nothing for pods that have not restarted in the last 5 minutes.

## Assumptions

- The normal Azure setup installs, in order, the cluster, the service mesh, the monitoring stack with its dashboards, and then the demo shop. The monitoring stack already collects the pod restarts the demo needs.
- The shop runs in the namespace named by the project's shared settings file, and the person running the commands can manage the Azure cluster from their machine and uses that file unchanged.
- The shop is installed with its own default memory allowances, and the person has not changed them by hand. "Original allowance" in this spec means the allowance the shop is installed with.
- The shop receives traffic during the demo: from the project's optional load generator, which the Azure setup prints how to start but does not start, or from a person using the shop. Triggering the fault does not change the amount of traffic.
- The load generator sends its traffic to the shop's front end, and the front end passes shopping visits on to the cart service, so cart is in use while the demo runs. Checked on the live cluster during planning (research.md Finding 5): the load generator's traffic reaches cart often enough to trigger the kill.
- The cart service runs as a single pod on Azure, because the shop's definition fixes it at one copy for every target other than the EKS setup.
- The cluster starts a stopped container again on its own, without anyone running a command: the shop's other services say so explicitly, and cart leaves it at the cluster's default, which is to always restart. Checked by reading the shop's deployment definitions; the default itself is a documented cluster behaviour.
- Checked on the live cluster during planning (research.md Finding 1): cart idles well below its allowance, and a small enough allowance kills it within seconds, repeatedly, always showing the out-of-memory status. The exact numbers are in research.md. This is what SC-001 and SC-002 depend on.
- Checked on the live cluster during planning (research.md Finding 2): no dashboard the monitoring setup installs — on this cluster or on EKS — shows a pod's restart count or its out-of-memory kills. As clarified, FR-011 now allows a section to be added to an existing dashboard, and the two numbers a presenter points at were confirmed to move on the live cluster while the fault ran and while it was reverted.
- Checked on the live cluster during planning (research.md Finding 3): deploying the shop again while the fault is active clears the fault, which FR-008 is written to tolerate.
- One presenter uses the fault at a time; two people starting and reverting it at once on the same cluster is not handled (chosen default).
- Verification happens on a live Azure cluster only; EKS and local clusters are not tested (out of scope per the issue).
- Scenario 01's existing EKS commands, including their known faults, are left as they are (FR-013); fixing them for EKS is a separate story. Scenario 04's unfinished mitigation is likewise not repaired here.

## Out of Scope

From the issue:

- The HTTP abort fault (story #113) and its files.
- Increased latency on the backend database (separate story).
- Verifying on EKS or on local clusters.
- hotrod.
- Fixing scenario 04's unfinished mitigation, and repairing the RabbitMQ memory squeeze it performs.

Decided while writing this specification:

- Making any shop pod other than cart run out of memory, or hitting more than one pod at a time.
- Making a whole machine run out of memory, or evicting pods for node-level memory pressure. This story changes one container's allowance only.
- Changing the shop's traffic, including starting or stopping the load generator as part of the commands.
- Choosing or tuning the shop's memory allowances for real workloads. The original allowance is restored; it is not re-designed.
- New dashboards, alerts or recording rules. One added section on a dashboard the monitoring setup already installs is in scope (FR-011 as clarified).
- A history of who started the fault or when, or any automatic removal after a set time or after a disconnect (FR-004).
- Coordinating two presenters using the fault at the same time on one cluster.
- Fixing scenario 01's EKS commands, their timer, or their shell problems (FR-013).
- Scenario 02's hardcoded database credentials; scenario 02 intentionally degrades the database and is not repaired here.
