# Feature Specification: Slow Database Fault for the Demo Shop on Azure

**Feature Branch**: `008-aks-db-latency-fault`

**Created**: 2026-10-22

**Status**: Draft — all six sections approved during authoring (constitution principle IX); specification quality validation passed (see `checklists/requirements.md`). Amended on 2026-10-22 and 2026-10-23 after hands-on research on the live cluster and the plan's dashboard decision (see Clarifications, sessions 2 and 3); the amended wording is awaiting the developer's read-through. Awaiting `gate:spec-approved`.

**Input**: [Issue #115](https://github.com/infracloudio/sre-stack/issues/115) — "Trigger increased backend DB latency for robot-shop on AKS with one command"

## Clarifications

### Session 2026-10-22

- Q: If the cluster restarts the database partway through a demo, must the slowness still be on afterwards? → A: Yes; the fault must survive a database restart, and the tests restart the database to prove it. **Superseded in session 2.**

### Session 2026-10-22 (after hands-on research on the live cluster)

- Q: Must the slowness survive a database restart? → A: No. Making it survive would mean restarting the database itself, which takes the shop's ratings and shipping down on every start and every revert. After a restart the fault is gone, the status command says so, and the start command can be run again.
- Q: Which shop request shows the slowness? → A: The shipping cost lookup. **Superseded in session 3**: ratings is included again.
- Q: How slow is "slow"? → A: The shipping cost lookup takes longer than 2 seconds. There is no upper limit, as long as the request still answers. **Refined in session 3**: shipping measured about 0.2 to 0.3 seconds normally in the latest test, and ratings is slow above 0.5 seconds.
- Q: Can there be a panel on the Database dashboard? → A: Yes, one new panel showing the average time a database query takes. A panel showing the time within which nine in ten queries finish is not possible, because this database version does not report it.

### Session 2026-10-22 (after a different way to slow the database was found)

- Q: Which shop requests show the slowness? → A: Both the shipping cost lookup and the ratings lookup. The database now makes each of those two lookups wait a fixed short time before answering, so each can be set to a useful speed on its own and the answers stay identical.
- Q: How slow is "slow" for each? → A: The shipping cost lookup takes longer than 2 seconds and the ratings lookup longer than 0.5 seconds (ratings normally takes about 0.02 seconds). Neither has an upper limit, as long as the request still answers.
- Q: Is there anything the presenter can use to look at one slow request in detail? → A: Yes, one new Azure-only dashboard lists slow shipping and ratings requests, and each entry opens the step-by-step view of that request, where the database step is most of the time. It is separate from the Database dashboard so that it appears only on Azure.
- Q: Must the slowness survive a database restart? → A: No, unchanged. A restart was tested on the live cluster: the fault is gone afterwards and the shop's data is reloaded.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Make the database slow with one command (Priority: P1)

As a person demonstrating the demo shop (robot-shop) on Azure, I want to run one documented command that makes the shop's database slow to answer, so I can show a realistic "slow database" incident on the monitoring dashboards. Today the only database fault is for the Amazon cloud and cannot run on Azure. The slowness shows in the shop's shipping cost lookup, the step where the shop works out delivery cost, and in the ratings lookup, the step that shows a product's star rating.

**Why this priority**: Making the database slow is the core outcome of the issue. Without it, the Azure demo has no way to show slow database responses.

**Independent Test**: On a running Azure demo shop with monitoring and shop traffic, run the documented start command, use the shop, and open the dashboards.

**Acceptance Scenarios**:

1. **Given** the demo shop and monitoring are running on Azure and no fault is active, **When** the person runs the documented start command, **Then** the shipping cost lookup and the ratings lookup become visibly slower.
2. **Given** the fault has been started, **When** the person opens the dashboards during a 2-minute demo, **Then** the dashboards show the rise in response time.
3. **Given** the fault is already active, **When** the person runs the start command again, **Then** the command succeeds and the fault stays active as before.

---

### User Story 2 - Return the database to normal with one command (Priority: P1)

As the same person, I want to run one documented command that removes the slowness, so the shop recovers and I can show the recovery on the dashboards without losing or damaging any shop data.

**Why this priority**: A demo that cannot be undone leaves the shop degraded. The issue requires that reverting brings response times back to normal and leaves the data intact.

**Independent Test**: With the fault active, run the documented revert command, use the shop, and open the dashboards.

**Acceptance Scenarios**:

1. **Given** the fault is active, **When** the person runs the documented revert command, **Then** the shipping cost lookup and the ratings lookup are back to their normal speed and the dashboards show the response time falling.
2. **Given** the fault was active and then reverted, **When** the person looks at the shop's data (for example, the product catalogue and existing ratings), **Then** nothing is missing or changed.
3. **Given** no fault is active, **When** the person runs the revert command, **Then** the command succeeds and changes nothing.

---

### User Story 3 - Check whether the fault is on (Priority: P2)

As the same person, I want to run one documented command that only reports whether the slow-database fault is currently on, so I can tell before or during a demo without changing anything.

**Why this priority**: The fault stays on until reverted, so someone needs a safe way to see its state. The start and revert commands work without it.

**Independent Test**: Run the status command with the fault on, then with it off, and confirm it reports each state correctly and changes nothing.

**Acceptance Scenarios**:

1. **Given** the fault is active, **When** the person runs the status command, **Then** it reports "fault active".
2. **Given** no fault is active, **When** the person runs the status command, **Then** it reports "fault not active".

---

### User Story 4 - Find the instructions (Priority: P2)

As a person new to the project, I want the scenarios guide to explain how to start and revert this fault on Azure, so I can run the demo without asking anyone.

**Why this priority**: The issue names the missing guide. The fault itself (stories 1 and 2) is useful even before the guide is updated.

**Independent Test**: Follow only the scenarios guide, from a running Azure demo shop, to start and then revert the fault.

**Acceptance Scenarios**:

1. **Given** a running Azure demo shop, **When** a person follows the scenarios guide, **Then** they find what must already be running, the start command, the status command, the revert command, and what to look for on the dashboards.

### Edge Cases

- **EC-001 — No shop traffic**: With no traffic, the dashboards show no change even though the fault is active, so a flat dashboard does not prove the fault failed. The project's load generator ends each run after one hour and is then started again automatically, so traffic can pause briefly mid-session. The guide tells the presenter how to confirm traffic is flowing and how to start the load generator. This follows FR-011 and SC-001.
- **EC-002 — Shop deployment re-run while the fault is active**: Re-running the demo shop's normal deployment leaves the fault on and reloads the shop's data in about 2 minutes, as without the fault (checked on the live cluster). The guide says the fault stays on and that reverting first is the cleaner order. This follows FR-011 and FR-013.
- **EC-003 — Database restarts while the fault is active**: The database can be restarted or moved to another machine by the cluster. The fault is then gone (tested on the live cluster): the status command says "fault not active" (FR-009), the shop is back at normal speed, and running the start command again restores the fault (FR-004). The revert command still succeeds and changes nothing.
- **EC-004 — Cluster stopped and started while the fault is active**: Azure clusters in this project are stopped between sessions to save cost. After the cluster starts again, the status command MUST tell the truth about whether the fault is active (FR-009), and the revert command MUST bring the shop back to normal speed whichever state it is in.
- **EC-005 — Presenter disconnects after starting**: The fault stays active until someone runs the revert command (FR-003). Anyone with access to the cluster can run it; nothing ties the fault to the person who started it. The status command tells anyone whether it is active (FR-009).
- **EC-006 — Wrong or incomplete cluster**: When the person is connected to a non-Azure cluster, or to an Azure cluster without the demo shop or its database, the start, revert and status commands stop and change nothing (FR-007).
- **EC-007 — Database slow for another reason**: If the shipping cost lookup is slow but this fault was not set, the status command says so instead of reporting the fault as active (FR-009), and the revert command's own check (FR-008) shows whether normal speed returned.
- **EC-008 — Heavy traffic while the database is slow**: Both lookups wait a fixed short time, so extra traffic does not make the answers slower or cause errors (checked with overlapping requests on the live cluster). The shop is back to normal speed within the time in SC-004, and no shop data is lost (FR-006).
- **EC-009 — Old EKS database commands used on Azure**: The existing database scenario limits connections on an Amazon database service, which Azure does not have, so it cannot work on Azure. The scenarios guide already uses "Scenario 02" for both that EKS scenario and the Azure cart memory fault, and "Scenario 3" for the EKS zone-outage scenario, which is not the same as Azure scenario 03. The guide must state clearly which scenario the new Azure commands belong to, so nobody runs the wrong one. This follows FR-011 and FR-012.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On a running Azure demo shop, a person MUST be able to start the fault with one documented command; once started, the shipping cost lookup and the ratings lookup are visibly slower than before.
- **FR-002**: A person MUST be able to remove the fault with one documented command; once removed, the shipping cost lookup and the ratings lookup are back to their normal speed.
- **FR-003**: Once started, the fault MUST stay active until the person runs the revert command; it MUST NOT remove itself after a set time. It is not required to survive the database being restarted or moved to another machine by the cluster (EC-003).
- **FR-004**: Running the start command while the fault is active, or the revert command while no fault is active, MUST succeed and leave the shop in the same state.
- **FR-005**: The fault MUST affect only the shop's database. Parts of the shop that do not use the database MUST keep their normal speed, except pages that wait on a slow database answer, which become slow as well (the knock-on slowness the demo shows).
- **FR-006**: Starting and removing the fault MUST NOT lose, change, or corrupt any shop data; the data after a revert MUST be identical to the data before the start.
- **FR-007**: If the person's environment is not connected to an Azure cluster running the demo shop with its database, the start, revert and status commands MUST stop with a message saying what is missing, and MUST change nothing.
- **FR-008**: After making its change, the start and revert commands MUST each send a few shipping cost lookups and a few ratings lookups as test requests and report success only when they show the expected result: slow answers after start, normal answers after revert. If the result does not appear, the command MUST stop with a message saying what it saw.
- **FR-009**: A person MUST be able to run one documented status command that changes nothing and reports whether the fault is active, using the same test-request check as FR-008 (both lookups). If the fault is not set and the database is slow for another reason, the status command MUST say so instead of reporting the fault as active.
- **FR-010**: The rise and fall in response time MUST be visible on the dashboards already installed by the Azure monitoring setup, without adding new dashboards. The only additions allowed are the panel in FR-015 and the dashboard in FR-016.
- **FR-011**: This fault is called "Azure scenario 03" in every guide. The scenarios guide MUST explain, for Azure: what must already be running, the start command, the status command, what to look for on the dashboards, the revert command, and what happens if the shop's normal deployment is run while the fault is on (EC-002).
- **FR-012**: The files of the EKS scenarios 01, 02 and 04 MUST NOT change. Where Azure needs behavior different from EKS, it MUST be provided separately. Files shared with EKS (the project's settings file and top-level commands) MAY gain Azure-only additions, but their existing settings and commands MUST stay as they are.
- **FR-013**: Setting up Azure and deploying the demo shop MUST behave as today when the fault has not been started, apart from installing the two dashboard additions in FR-015 and FR-016. Setting up any other platform MUST NOT install the dashboard in FR-016.
- **FR-014**: The project's plain-language Azure explainer page MUST also describe Azure scenario 03 (what it does, what a shopper notices, what to look for, and the start, status and revert commands) next to the other Azure scenarios, and MUST correct any statement the fault shows to be wrong or out of date for Azure, so the two guides do not disagree.
- **FR-015**: The existing Database dashboard MUST gain one panel showing the average time a database query takes, so the presenter can show the database itself getting slower and recovering. It MUST be titled as an average. The panel is added to the shared Database dashboard, so it appears wherever that dashboard is installed, including Azure, and MUST NOT change any other panel.
- **FR-016**: The Azure monitoring setup MUST also install one new dashboard, "Slow shop requests", listing slow shipping and ratings requests (the shipping lookup over 2 seconds, the ratings lookup over 0.5 seconds), so the presenter can pick one request and open its step-by-step view, which shows the database step taking most of the time. It MUST appear only on Azure and MUST NOT change any existing dashboard.

## Success Criteria *(mandatory)*

### Measurable Outcomes

In these criteria, the test requests are the shipping cost lookup and the ratings lookup. For shipping, "normal speed" means 2 seconds or less (it normally takes well under 1 second) and "slow" means longer than 2 seconds. For ratings, "normal speed" means 0.5 seconds or less (it normally takes about 0.02 seconds) and "slow" means longer than 0.5 seconds. "Slow" always means the request still answers successfully; there is no upper limit.

- **SC-001**: Within 60 seconds of running the start command, 10 out of 10 shipping test requests and 10 out of 10 ratings test requests are slow, and the dashboards show the response time rising, while the shop is receiving traffic from the project's load generator.
- **SC-002**: While the fault is active, no test request fails with an error because of the slowness: 10 out of 10 shipping and 10 out of 10 ratings requests still succeed, including while the load generator is running. The fault shows slowness, not an outage.
- **SC-003**: While the fault is active, 10 out of 10 requests sent to a part of the shop that does not use the database are answered at normal speed, not counting pages that wait on the database.
- **SC-004**: Within 1 minute of running the revert command, 10 out of 10 shipping test requests and 10 out of 10 ratings test requests are at normal speed; within 5 minutes the dashboards show the response time back at its earlier level.
- **SC-005**: A presenter can start the fault, point to the rise on the dashboards, revert it, and point to the recovery, all within one 2-minute demo.
- **SC-006**: Each command, including its own check of the result (FR-008), finishes in under 60 seconds.
- **SC-007**: The status command gives the correct answer in both states, 10 times out of 10, in under 10 seconds each time, and never changes anything. (With the fault on and the database restarted, the correct answer is "not active".)
- **SC-008**: Shop data is identical before the start and after the revert: the same products, the same ratings (whatever ratings exist at that moment; the shop's traffic adds them), the same users.
- **SC-009**: Following only the scenarios guide, the owner completes one full start, check and revert cycle on a running Azure demo shop on the first attempt without needing anything outside the guide.
- **SC-010**: Running the start command twice in a row, or the revert command twice in a row, ends without errors and leaves the shop in the same state as running it once.
- **SC-011**: Zero lines change in the files of the EKS scenarios 01, 02 and 04; in files shared with EKS, every existing line stays unchanged and only Azure-only lines are added.
- **SC-012**: After a normal Azure setup in which the fault was never started, 100% of shipping test requests stay at normal speed over 5 minutes of shop traffic.
- **SC-013**: *(Removed 2026-10-22: the fault need not survive a database restart. See EC-003 and Clarifications, session 2.)*
- **SC-014**: With shop traffic running, the new Database dashboard panel (FR-015) shows the average query time rising within 2 minutes of the start command and falling back within 5 minutes of the revert command.
- **SC-015**: With shop traffic running, within 2 minutes of the start command the new slow-requests dashboard (FR-016) lists at least one slow shipping request and one slow ratings request, and opening one shows the database step as most of that request's time.

## Assumptions

- The normal Azure setup installs, in order, the cluster, the service mesh (the layer that routes traffic between the shop's services), the monitoring stack with its dashboards, and then the demo shop with its long-running services joined to the mesh. The monitoring stack collects request-duration measurements from the mesh for the shop's services, including the database.
- The shop has one database, kept on its own disk so its data survives a restart. Two parts of the shop use it: the product ratings and the shipping cost lookup. Checked on the live cluster: no other part uses it.
- The ratings answer in about 0.02 seconds in normal use. The shipping lookup is slower even when nothing is wrong, about 0.2 to 1.2 seconds measured on the live cluster (it varies with how recently the database was restarted), because it searches a large table of places. The fault makes each of the two lookups wait a fixed short time before answering, so the answers are slower but identical.
- The shop receives traffic during the demo, from the project's optional load generator (the Azure setup prints how to start it but does not start it) or from a person using the shop. Starting the fault does not change the amount of traffic.
- The Azure monitoring setup already stores the step-by-step record of each request, so the new dashboard in FR-016 needs nothing installed beyond the dashboard itself.
- The dashboards already installed by the Azure monitoring setup include response-time panels (for example P50 latency, P90 latency, and request duration by service).
- The person running the commands can manage the Azure cluster from their machine and uses the project's shared settings file unchanged, which names the shop's location in the cluster.
- One presenter uses the fault at a time; two people starting and reverting it at once on the same cluster is not handled (chosen default, as for the other Azure faults).
- Running this fault together with another Azure fault is not required to work or tested.
- Verification happens on a live Azure cluster only; EKS and local clusters are not tested (out of scope per the issue).
- The EKS database scenario (limiting connections on the Amazon database service) is left as it is and its approach is not reused; the Azure fault makes the database slow instead.

## Out of Scope

From the issue:

- The HTTP abort fault (issue #113, already built) and the out-of-memory fault (a separate story).
- Verifying on EKS or on local clusters.
- The HotROD demo app.
- Repairing or changing the existing EKS database scenario (the one that limits connections on the Amazon database service), or its hardcoded credentials. That scenario intentionally degrades the database and is not repaired here.

Decided while writing this specification:

- Slowing any data store other than the shop's main database (the product and account store, and the shopping-basket store).
- Making the database fail outright, refuse connections, or drop part of its answers. This fault only makes answers slower (SC-002).
- Choosing how slow the database gets by a setting the person can change in the command; the amount is fixed by the success criteria.
- Further dashboards or alerts (FR-010). The new Database dashboard panel in FR-015 and the new Azure-only dashboard in FR-016 are in scope.
- A Database dashboard panel showing the time within which nine in ten queries finish: this database version does not report it.
- Making the fault survive a database restart (EC-003).
- Stopping the shop's deployment from reloading the shop's data each time it runs (EC-002); to be filed as its own story.
- Starting, stopping or changing shop traffic as part of the fault commands.
- Running Azure scenario 03 together with another Azure fault, and coordinating two presenters using it at the same time on one cluster.
- Changing other parts of the Azure explainer page beyond the new scenario and the statements the fault shows to be wrong (FR-014).
