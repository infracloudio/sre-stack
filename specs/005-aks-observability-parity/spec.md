# Feature Specification: Complete Azure Application Observability

**Created**: 2026-10-09

**Status**: Draft — all six sections approved during authoring; specification quality validation passed; formal spec gate remains pending.

**Input**: [Issue #109](https://github.com/infracloudio/sre-stack/issues/109)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See live service connections (Priority: P1)

As a person investigating the demo shop on Azure, I want the Application Dashboard's Service Map to show which application services communicate, so I can understand the connections involved in a problem.

**Why this priority**: The issue reports that the existing map has no data on Azure.

**Independent Test**: Generate demo-shop traffic with the existing load generator and inspect the Service Map for that traffic period.

**Acceptance Scenarios**:

1. **Given** the demo shop and monitoring are running on Azure, **When** a person generates shop traffic and opens the Service Map for that period, **Then** the map shows live links between application services involved in that traffic.

### User Story 2 - Inspect recorded requests (Priority: P1)

As a person investigating the demo shop on Azure, I want to find traces in the dashboards app, so I can examine recorded work for application requests. A trace is a record of work performed while handling a request.

**Why this priority**: The issue reports that the existing trace source does not work on Azure.

**Independent Test**: Generate demo-shop traffic, open the existing trace source in the dashboards app, and search the traffic period.

**Acceptance Scenarios**:

1. **Given** the demo shop and monitoring are running on Azure, **When** a person generates shop traffic and searches the existing trace source for that period, **Then** the search returns traces from that traffic and the person can open a trace to inspect its recorded work.

### User Story 3 - Find automatically collected application measurements (Priority: P1)

As a person operating the demo shop on Azure, I want the monitoring setup to include automatic application measurements, so I can inspect application activity as I can on the other supported environments.

**Why this priority**: Automatic application measurement is the third capability explicitly required by the issue.

**Independent Test**: Complete Azure monitoring setup, generate demo-shop traffic, and query the monitoring system for automatically collected application measurements from that period.

**Acceptance Scenarios**:

1. **Given** Azure monitoring setup has completed and the demo shop is running, **When** a person generates shop traffic and queries the monitoring system, **Then** automatically collected application measurements from that traffic are available without a separate installation step.

### User Story 4 - Keep existing monitoring usable (Priority: P1)

As a person operating a supported environment, I want the added Azure capabilities to preserve working monitoring and setup behavior, so I can continue using existing views and workflows.

**Why this priority**: The issue explicitly requires existing Azure panels, monitoring setup without a service mesh, and the other environments' installations to keep working. A service mesh is a layer that manages communication between application services.

**Independent Test**: Compare existing Azure panels under traffic that produces their data, run Azure monitoring setup without a service mesh, and verify existing Amazon and local observability installation workflows.

**Acceptance Scenarios**:

1. **Given** existing Azure panels show data for generated traffic, **When** the added capabilities are enabled and equivalent traffic is generated, **Then** the request-error, request-volume, success-rate, and error-log panels continue showing their corresponding data.
2. **Given** Azure monitoring prerequisites are met and no service mesh is installed, **When** a person runs monitoring setup, **Then** it succeeds without requiring a service mesh.
3. **Given** an existing Amazon or local setup workflow, **When** a person installs observability through that workflow, **Then** service mapping, tracing, and automatic application measurement remain installed through the same workflow as before.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The existing Azure monitoring setup MUST include service mapping, request tracing, and automatic application measurement without requiring separate installation steps for these capabilities. This supports User Stories 1–3.
- **FR-002**: After the existing load generator produces demo-shop traffic on Azure, the Application Dashboard's Service Map MUST show live links between application services involved in that traffic when the person selects the traffic period. This supports User Story 1.
- **FR-003**: The existing trace source in the Azure dashboards app MUST be connected and usable. After the load generator produces demo-shop traffic, a person MUST be able to find traces from that period and open a returned trace to inspect its recorded work. This supports User Story 2.
- **FR-004**: After the load generator produces demo-shop traffic on Azure, the monitoring system MUST make automatically collected application measurements from that traffic available to query. For example, a person can select the traffic period and find measurements of shop requests. This supports User Story 3.
- **FR-005**: Existing Azure Application Dashboard panels for request errors, request volume, success rate, and error logs MUST continue showing their corresponding data under equivalent traffic after the new capabilities are enabled. This supports User Story 4.
- **FR-006**: When the existing Azure monitoring prerequisites are met, monitoring setup MUST succeed without a service mesh installed. The added capabilities MUST NOT introduce a service-mesh prerequisite for that setup. This preserves the missing-mesh behavior of the earlier observability story's FR-013 and supports User Story 4.
- **FR-007**: Existing Amazon and local observability installation workflows and behavior MUST remain unchanged, including installation of service mapping, tracing, and automatic application measurement. This supports User Story 4.
- **FR-008**: Azure-specific settings for the added capabilities MUST be maintained separately from Amazon and local settings, so changing the Azure setup does not change those environments. This supports User Story 4.
- **FR-009**: The added Azure capabilities MUST use the latest stable releases available when their versions are verified during planning. These release choices MUST NOT change the releases used by Amazon or local environments. This supports User Stories 1–4.
- **FR-010**: Setup of the added Azure capabilities MUST be idempotent: running it again with unchanged settings after a successful installation MUST succeed, create no additional installations, and leave all three capabilities usable. For example, a person can run setup twice without removing the first installation.
- **FR-011**: The existing one-command Azure deployment MUST include all three added capabilities through its monitoring setup, without requiring the person to run extra installation steps. Repeating that deployment with unchanged settings MUST preserve the behavior required by FR-010.
- **FR-012**: The existing Azure deployment instructions MUST be updated to describe the integrated setup, safe repeat runs, how to generate demo-shop traffic, and how to confirm live service links, inspectable traces, and automatically collected application measurements.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After completing the existing Azure monitoring setup, a person can use all three added capabilities with zero separate installation steps. This verifies FR-001.
- **SC-002**: For one recorded demo-shop load-generator run on Azure, a person can confirm all three results for the same traffic period: at least one live link between application services in the Service Map, at least one returned trace that opens with recorded request work, and at least one automatically collected application measurement attributable to that traffic. For example, the person generates shop requests and then inspects the map, traces, and measurements for that run. This verifies FR-002–FR-004.
- **SC-003**: Every previously working Azure Application Dashboard panel for request errors, request volume, success rate, and error logs continues to show its corresponding data under equivalent traffic after the additions. No panel in these groups loses its existing working behavior. This verifies FR-005.
- **SC-004**: With the existing Azure monitoring prerequisites met and no service mesh installed, the monitoring setup completes successfully without requiring a mesh installation. This verifies FR-006.
- **SC-005**: Both existing environments, Amazon and local, retain their observability installation workflows and behavior, with zero changes to their existing settings or selected releases. This verifies FR-007 and the preservation requirement in FR-009.
- **SC-006**: All Azure-specific settings for the three added capabilities are maintained separately from Amazon and local settings. A review finds zero Azure-specific settings for these additions placed in the Amazon/local configuration. This verifies FR-008.
- **SC-007**: All three added Azure tools use the latest stable application release available at their recorded planning-time verification date. The evidence identifies the selected release and the source used to confirm it for each tool. This verifies FR-009.
- **SC-008**: Two successive runs of the Azure monitoring setup with unchanged settings both succeed, leave exactly one installation of each added capability, and allow the person to confirm all three traffic results described in SC-002 after the second run. This verifies FR-010.
- **SC-009**: Two successive runs of the existing one-command Azure deployment with unchanged settings both succeed and include all three added capabilities without extra installation steps. After the second run, each added capability has exactly one installation and all three traffic results described in SC-002 can be confirmed. This verifies FR-011.
- **SC-010**: Using the updated Azure deployment instructions, a reviewer can complete the integrated setup, repeat it safely, generate demo-shop traffic, and confirm all three results described in SC-002 without needing deployment or verification steps supplied outside the guide. For example, the guide explains how to find and open a trace from the generated traffic. This verifies FR-012.

## Assumptions

- **A-001 — Verification environment**: Traffic-based acceptance checks depend on a running Azure demo shop, the existing monitoring prerequisites, and a reviewer who can access the dashboards and monitoring data. These are prerequisites for the checks, not a claim that the current environment has been verified. Live access and readiness remain to be checked during planning.
- **A-002 — Traffic is started deliberately**: The person running verification starts the existing demo-shop load generator after deployment. Installing the monitoring capabilities alone is not expected to produce shop traffic. For example, the reviewer starts a load run, records its time period, and uses that period when inspecting links, traces, and measurements.
- **A-003 — Comparable panel checks**: Checks of existing panels use traffic that produces the data those panels display. In particular, checking error panels and error logs requires relevant error-producing traffic; a run containing only successful requests does not demonstrate that those panels still work.
- **A-004 — Release compatibility remains to be verified**: The latest stable releases required by FR-009 are not assumed to be compatible with the Azure environment until checked during planning. Any incompatibility must be raised with the developer before an older release is selected; it does not silently relax the approved release requirement.

## Edge Cases

- **EC-001 — No relevant traffic**: When no demo-shop traffic has been generated for the selected period, empty traffic views alone do not prove a collection failure or successful acceptance. The reviewer generates traffic and selects its recorded period before checking the three required results. Similarly, a run containing only successful requests cannot prove that error panels and error logs still work. For example, looking at a period before the load run cannot satisfy SC-002. This follows FR-002–FR-005 and A-002–A-003.
- **EC-002 — No service mesh**: When the service mesh is absent but the existing monitoring prerequisites are met, Azure monitoring setup still succeeds. This case applies to the monitoring setup; it does not require the full Azure deployment to omit its existing mesh installation. This follows FR-006 and SC-004.
- **EC-003 — Already installed**: When all three capabilities are already installed successfully, repeating either the monitoring setup or the full Azure deployment with unchanged settings succeeds without duplicate installations. All three capabilities remain usable with newly generated traffic after the repeat run. This follows FR-010–FR-011 and SC-008–SC-009.
- **EC-004 — Trace source exists but is unusable or empty under traffic**: A trace source appearing in the dashboards app is not sufficient evidence of success. If it cannot be queried, or returns no traces from the recorded load run, the trace acceptance check fails. The reviewer must find and open a trace from that run. This follows FR-003 and SC-002.
- **EC-005 — Latest stable release is incompatible**: If planning-time verification finds that a required latest stable release cannot work in the Azure environment, the incompatibility is raised with the developer before selecting an older release. The release requirement is not silently weakened, and Amazon/local releases remain unchanged. This follows FR-007, FR-009, and A-004.

## Out of Scope

- Adding a new dashboard panel for automatically collected application measurements. For example, a reviewer must be able to query those measurements, but this story does not build a dedicated panel for them.
- Changing the existing database, messaging, or service-mesh dashboards identified in the issue as MySQL, RabbitMQ, and istio-service.
- Installing or changing the Amazon managed-database dashboard identified in the issue as RDS.
- Changing the Amazon or local stacks, including their settings, selected releases, and installation behavior. The new release choices and separate settings apply to Azure only.
