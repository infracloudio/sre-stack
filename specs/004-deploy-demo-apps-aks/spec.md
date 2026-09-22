# Feature Specification: Demo Applications for AKS Observability

**Feature Branch**: `004-deploy-demo-apps-aks`

**Created**: 2026-09-22

**Status**: Draft

**Input**: User description: "Deploy Robot Shop and HotROD demo applications onto the AKS cluster so the observability stack has something real to monitor, instead of empty dashboards."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See real traffic in the dashboards (Priority: P1)

Someone showing off the monitoring setup on the AKS cluster wants the dashboards to display real activity, not sit empty. They deploy Robot Shop — an online store demo made of several small services (browsing, cart, checkout, payments, shipping, ratings, and user accounts) plus the databases it needs — onto the AKS cluster, using the same command already used to deploy it elsewhere. Once it's running and someone clicks around the store, the monitoring dashboards show real activity from it.

**Why this priority**: without any real application running, the monitoring dashboards have nothing to show. This is the minimum needed to make a demo meaningful.

**Independent Test**: deploy Robot Shop to the AKS cluster, generate a few clicks through the store, and confirm the monitoring dashboards show activity from it.

**Acceptance Scenarios**:

1. **Given** the AKS cluster is ready, **When** Robot Shop is deployed using the existing command, **Then** the store and its databases come up and stay running.
2. **Given** Robot Shop is running, **When** someone browses the store, **Then** the monitoring dashboards show activity from it.
3. **Given** Robot Shop is already deployed, **When** the same deploy command is run again, **Then** nothing breaks and nothing is duplicated.

---

### User Story 2 - Show a second kind of demo traffic (Priority: P2)

The same person also deploys HotROD, a second demo application, onto the AKS cluster using its existing command. HotROD is commonly used to show request-tracing (following one request as it travels through several services), so it demonstrates a different part of the monitoring setup than Robot Shop does.

**Why this priority**: it broadens what the demo can show, but Robot Shop alone already proves the monitoring setup works.

**Independent Test**: deploy HotROD to the AKS cluster, generate some activity, and confirm it shows up in the monitoring tools alongside Robot Shop without either interfering with the other.

**Acceptance Scenarios**:

1. **Given** the AKS cluster is ready, **When** HotROD is deployed using the existing command, **Then** it comes up and stays running.
2. **Given** both Robot Shop and HotROD are running, **When** someone generates activity in each, **Then** both show up correctly in the monitoring tools at the same time.

---

### User Story 3 - Nothing else changes (Priority: P3)

Anyone who already deploys Robot Shop or HotROD to Amazon's cloud, or to their own local test cluster, keeps doing so exactly as before. Adding AKS as a new place to deploy these apps must not change how they behave anywhere else.

**Why this priority**: this protects current users; it's a constraint on the change rather than new value.

**Independent Test**: compare how Robot Shop and HotROD deploy and run on Amazon's cloud and on the local test cluster, before and after this change, and confirm nothing is different.

**Acceptance Scenarios**:

1. **Given** this change is made, **When** Robot Shop or HotROD is deployed to Amazon's cloud, **Then** it behaves exactly as it did before.
2. **Given** this change is made, **When** Robot Shop or HotROD is deployed to the local test cluster, **Then** it behaves exactly as it did before.

---

### Edge Cases

- What happens if the AKS cluster doesn't have enough room set aside for applications? The deployment should fail with a clear explanation, not half-succeed.
- What happens if the monitoring stack isn't installed yet when the demo apps are deployed? The apps should still come up fine; the dashboards simply have nothing to show until monitoring is added.
- What happens if someone deploys Robot Shop or HotROD a second time without removing it first? Nothing should break or duplicate.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Deploying Robot Shop to the AKS cluster MUST use the same deployment command already used to deploy it elsewhere, with no new steps required.
- **FR-002**: All parts of Robot Shop — the store itself and the databases it depends on — MUST be placed within the sections of the cluster already set aside for applications and for data storage.
- **FR-003**: Robot Shop's databases MUST run inside the cluster; the store MUST NOT depend on any managed database service outside the cluster.
- **FR-004**: Deploying HotROD to the AKS cluster MUST use the same deployment command already used to deploy it elsewhere, with no new steps required.
- **FR-005**: HotROD MUST be placed within the section of the cluster already set aside for applications.
- **FR-006**: Robot Shop and HotROD MUST be sized modestly on this cluster — a single copy of each piece, using little compute — since this is for demonstration, not for handling real production load.
- **FR-007**: Data that Robot Shop's databases store MUST survive a restart of the pieces that hold it.
- **FR-008**: Running either app's deployment command a second time MUST NOT create duplicates or break the existing deployment.
- **FR-009**: Once deployed, activity in both apps MUST become visible in the monitoring tools already running on the cluster, without extra setup.
- **FR-010**: This change MUST NOT alter how Robot Shop or HotROD deploy or behave on Amazon's cloud or the local test cluster.

### Key Entities

- **Robot Shop**: an online store demo application made up of several small services (browsing, cart, checkout, payments, shipping, ratings, user accounts) and the databases they use.
- **HotROD**: a demo application commonly used to show how a single request travels across several services, useful for demonstrating request-tracing.
- **Monitoring tools**: the dashboards and log/metric collection already running on the AKS cluster from the earlier observability story, which this story gives real activity to display.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A person can deploy Robot Shop and immediately browse and use the store, with no steps beyond running its existing deploy command.
- **SC-002**: A person can deploy HotROD and immediately generate example activity, with no steps beyond running its existing deploy command.
- **SC-003**: Activity generated in either app appears in the monitoring dashboards without any manual configuration.
- **SC-004**: Running either app's deploy command more than once never produces errors or duplicate resources.
- **SC-005**: A side-by-side comparison of Robot Shop and HotROD's deployment and behavior on Amazon's cloud and the local test cluster, from before and after this change, shows no differences.

## Assumptions

- The AKS cluster, and the sections of it set aside for applications and for data storage, already exist from the earlier cluster story.
- The monitoring tools may already be running on the cluster, or may be added independently; this story does not depend on the order the two are done in.
- The existing deployment commands for Robot Shop and HotROD already work correctly elsewhere and only need to work against this new cluster.
- No new user-facing feature is being added to either app; they are deployed as they already exist today.
