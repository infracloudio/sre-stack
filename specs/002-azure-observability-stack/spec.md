# Feature Specification: Azure Observability Stack

**Feature Branch**: `002-azure-observability-stack`

**Created**: 2026-09-15

**Status**: Draft

**Input**: User description: "Deploy the core observability stack — Prometheus, Grafana, Loki, and the optional OpenTelemetry Collector — onto the Azure cluster from the earlier Azure story, scheduled only onto the observability node pool via the same workload-separation marking the Amazon and local setups use. The dashboards must be reachable and healthy, the Azure-specific tool settings must live in their own folder, and the documentation and decision record must be updated."

## Plain-language glossary

- **Cluster**: a group of machines that runs containerised applications together.
- **Amazon setup, local setup, Azure setup**: the three ways this project deploys the same stack — on Amazon's cloud, on the developer's own machine, and on Microsoft's cloud.
- **Monitoring stack**: the tools that show what a running system is doing. Here it means a metrics store, a dashboards app, and a logs store.
- **Metrics store**: collects numbers over time, such as how much processor a service used (today this is Prometheus).
- **Dashboards app**: the web page with charts and log search (today this is Grafana).
- **Logs store**: collects and searches the text that programs print while running (today this is Loki).
- **Log shipper**: a small helper that forwards each machine's log text to the logs store, so logs actually arrive.
- **Telemetry collector**: an optional component that receives measurements from applications and forwards them on. Today it is installed only when someone asks for it.
- **Observability pool**: the node group in the cluster reserved for monitoring, marked so only monitoring workloads may run there.
- **Workload-separation marking (taint)** and **toleration**: the mark that keeps other work off a pool, and the matching permission a workload carries to run there anyway.
- **Shared settings file**: the single settings file every script in this repository reads. Nothing else is hand-edited to change behaviour.
- **Tool settings file**: the file that lists the exact version and options used to install one tool, so the same install can be repeated later.
- **Release pin**: naming one exact version instead of accepting whatever is newest on the day.
- **Entry point**: one web address in front of the two web screens, so people can open them from their own machine.
- **Endpoints command**: the existing command that prints the web addresses of what is running.
- **Verification check**: a separate script that only reads a live cluster and reports, in plain language, whether it matches what the setup should have produced.

## Clarifications

### Session 2026-09-15

- Q: How should the two web screens be reachable from the developer's machine — one public address each, or one shared entry point? → A: One shared entry point. The cluster's own managed ingress feature is enabled and kept running by the platform, so only one public address is created and this project installs and maintains no gateway of its own. Each screen is reached under its own path on that one address.
- Q: Where should the dashboards app keep its data (dashboards, users, settings) on Azure? → A: The same arrangement as today — the small in-cluster database the existing setups use — so behaviour matches what people already know.
- Q: Which logging setup should Azure get? → A: The current stable release of the logs store plus a log shipper, so cluster logs actually appear in the dashboards. The version choice used by the Amazon/local setups is neither reused nor changed.
- Q: Does the ordinary start command now deploy the monitoring stack on Azure? → A: Yes. One command installs the cluster first, then the monitoring stack, then prints the addresses. The monitoring steps stay callable on their own, and the telemetry collector stays optional.
- Q: Where do Azure-specific settings live? → A: In their own folder. Every existing Amazon/local tool settings file stays exactly as it is.
- Q: The story text asked for test cases to verify the deployment; what should be built? → A: No automated test cases. Verification is a basic read-only check run against the live Azure cluster, reporting whether the monitoring workloads run on the observability pool and whether the dashboards app's sources are connected and healthy.
- Q: Should the log shipper run on every machine it can reach, or stay pinned to the observability pool like the rest of the stack? → A: Mirror today's setups — the shipper runs wherever it can (cluster system machines, the app pool, and the observability pool), because a shipper only collects the machines it runs on; every other monitoring workload stays on the observability pool only.
- Q: Should Entra ID sign-in — so that people with contributor access to the Azure subscription can log in with their work account — be part of this story? → A: No. It becomes its own follow-up story, because it needs an HTTPS hostname and certificate (Entra ID requires https redirect addresses) plus an app registration with tenant-side assignment and consent; and "contributor on the subscription" cannot be checked automatically, so the access list must be maintained by hand. This story keeps the dashboards tool's own admin account.
- Q: How is the dashboards app's admin password handled? → A: The tool creates the admin account itself and keeps the password in a cluster secret; no credential is stored in the repository, and this story's documentation explains how to read it from the cluster.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Monitoring stack running on the Azure cluster (Priority: P1)

A developer selects the Azure provider in the shared settings file, signs in to Azure, and runs the same start command they use today. The command creates the cluster as it does now, then installs the metrics store, the dashboards app, and the logs store onto it, all placed on the observability pool. When it finishes, it prints the web address for the dashboards and for the metrics screen. Opening the dashboards address shows the app loaded, with the metrics source and the logs source connected and healthy. No application data is needed yet — a healthy, reachable stack is the deliverable.

**Why this priority**: this is the whole point of the story. Without it the Azure path cannot be used for demos and cannot be validated end to end.

**Independent Test**: run the start command against Azure, then open the printed addresses and confirm both sources are connected and healthy, and that every monitoring workload runs on the observability pool.

**Acceptance Scenarios**:

1. **Given** a signed-in Azure session with the settings filled in and the cluster from the earlier Azure story available, **When** the start command runs, **Then** the metrics store, the dashboards app, and the logs store run on the cluster, every one of their workloads is placed on the observability pool (the log shipper alone running wherever it can reach, as in the existing setups), and the endpoints command prints a web address for each screen.
2. **Given** the monitoring stack is already installed, **When** the start command runs again, **Then** nothing is duplicated and it finishes without error.
3. **Given** the monitoring stack is running, **When** the dashboards address is opened from the developer's machine, **Then** the app loads and reports the metrics source and the logs source connected and healthy.
4. **Given** the monitoring stack is running, **When** someone inspects where the monitoring workloads run, **Then** all of them run on the observability pool and none on the other pools, except the log shipper, which runs wherever it can reach.

---

### User Story 2 - Optional telemetry collector on Azure (Priority: P2)

The optional telemetry collector, which today can be installed on the Amazon and local setups with its own command, can also be installed on the Azure cluster with an equivalent Azure-specific command. It is placed on the observability pool the same way. The ordinary start command does not install it.

**Why this priority**: it adds demo value, but the stack stands without it, so it ranks below the core stack.

**Independent Test**: run the collector command against the Azure cluster and confirm its workloads run on the observability pool; run the ordinary start command alone and confirm the collector is not installed.

**Acceptance Scenarios**:

1. **Given** a running Azure monitoring stack, **When** the collector command runs, **Then** the collector is installed and its workloads run on the observability pool.
2. **Given** a fresh Azure setup, **When** only the ordinary start command runs, **Then** the collector is not installed.

---

### User Story 3 - Existing setups are untouched (Priority: P3)

Anyone using the Amazon or local setup keeps exactly what they have: the same commands, the same behaviour, and the same logging release choice. Because the person making this change may not have access to a live Amazon account, "nothing changed" is proven without a cloud account in two ways: the existing tool settings files are unchanged from before the change, and the repository's own checks still pass.

**Why this priority**: it protects current users and constrains the change rather than adding value, so it ranks after the new capability.

**Independent Test**: compare the existing tool settings files and the Amazon/local command definitions with their state before the change, and run the repository's own checks; both must show no change.

**Acceptance Scenarios**:

1. **Given** this change, **When** the existing tool settings files are compared with their state before the change and the Amazon/local commands are inspected, **Then** every existing tool settings file is identical and the Amazon/local commands behave exactly as before; the only edits to shared command wiring are the lines that select the Azure path, and all new Azure-specific settings and commands are additions in their own folder.
2. **Given** this change, **When** the repository's own checks run, **Then** they pass unchanged, giving no evidence of a change to Amazon or local behaviour.

---

### Edge Cases

- What happens when the monitoring setup is asked to run but the Azure requirements are not met (not signed in, no cluster, unusable location)? The command must stop with a clear, plain-language message instead of installing part of the stack.
- What happens when the cluster's managed entry point has no web address yet, or the endpoints command is run before the stack is up? The setup must wait for the address and must not print a broken or empty link; if it gives up, it says plainly what is installed and that the address is not ready, and a rerun finishes the job.
- What happens when the observability pool has too little room for the monitoring stack? The setup must stop with a plain-language message naming what could not be placed, and a rerun must reuse whatever was already installed.
- What happens when the small database the dashboards app stores its data in is missing or not ready? The dashboards app must not be reported as ready, and the setup must say which part is still missing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When the Azure provider is selected and the start command runs, the metrics store, the dashboards app, and the logs store MUST be installed on the Azure cluster, after the cluster itself is ready.
- **FR-002**: Every workload of the monitoring stack MUST select the observability pool and tolerate its workload-separation marking, so the stack runs only there and nothing lands on the other pools. The log shipper is the one exception: exactly as in the existing setups, it MUST run on every machine it can reach (cluster system machines, the app pool, and the observability pool) so their logs are collected. Cluster-managed platform components, such as the managed entry point, run where the platform places them.
- **FR-003**: The start command MUST be safe to run twice: a second run installs nothing new and finishes without error.
- **FR-004**: The endpoints command MUST print a working web address for the dashboards app and for the metrics screen of the Azure setup, with no manual step beyond running it.
- **FR-005**: The two web screens MUST be reachable from the developer's machine through one shared public address, provided by the cluster's own managed ingress feature, each screen under its own path on that address.
- **FR-006**: The dashboards app MUST load with the metrics source and the logs source connected and healthy, with no application data required.
- **FR-007**: The logs store MUST be installed from its own Azure-specific tool settings file, pinned to one current stable release chosen when this story is built. It MUST NOT reuse the release choice of the Amazon/local setup, and the Amazon/local logging setup MUST NOT change.
- **FR-008**: All Azure-specific tool settings files MUST live in their own folder; no existing Amazon/local tool settings file may change.
- **FR-009**: The dashboards app's data MUST be stored the same way as today, in the small in-cluster database the existing setups use.
- **FR-010**: The optional telemetry collector MUST be installable on the Azure cluster through its own Azure-specific command, placed like the rest of the stack; the ordinary start command MUST NOT install it.
- **FR-011**: A read-only verification check MUST inspect the live Azure cluster and report in plain language whether the monitoring workloads run on the observability pool and whether the dashboards app's sources are connected and healthy. It MUST only read, never change cluster or cloud state.
- **FR-012**: When the Azure requirements are missing or wrong (not signed in, no cluster, unusable location), or when the observability pool cannot host the stack, the command MUST stop with a clear, plain-language message and MUST NOT report the stack as ready.
- **FR-013**: The monitoring setup MUST NOT create anything outside the cluster that would outlive the existing cleanup command; running cleanup MUST still remove everything the setup created.
- **FR-014**: Documentation this change touches — the project readme, the agent context notes, and the help listing — MUST describe the new Azure monitoring commands and how to invoke them.
- **FR-015**: The design decisions made by this story MUST be recorded in the project's decision record.
- **FR-016**: Existing Amazon and local behaviour MUST keep working unchanged, including every existing command, the full Amazon stack, and the existing optional components.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer signed in to Azure, with the settings filled in, gets the cluster and the running monitoring stack within one working session, with no manual steps beyond signing in, filling in the settings, and running the commands.
- **SC-002**: Every monitoring workload on the Azure cluster runs on the observability pool, and none runs on the other pools, except the log shipper, which runs on every machine it can reach as the existing setups do; checked against the live cluster.
- **SC-003**: Both web screens open from the developer's machine at the addresses the endpoints command prints, and the dashboards app reports its metrics and logs sources connected and healthy.
- **SC-004**: The existing tool settings files are identical to their state before the change, the Amazon and local commands behave exactly as before, and the repository's own checks pass unchanged.
- **SC-005**: The read-only verification check, run against a freshly set-up Azure cluster, prints a report showing the monitoring workloads on the observability pool and the dashboards app's sources healthy; that report is the acceptance evidence for this story.
- **SC-006**: Running the start command a second time finishes without error and installs nothing new.

## Assumptions

- The user already has an Azure account and signs in with Azure's own command-line sign-in tool, as in the earlier Azure story; no credentials are stored in the repository.
- The cluster from the earlier Azure story exists, or is created by the same start command; its observability pool carries the same workload-separation marking the other setups use.
- The cluster's managed ingress feature is available in the chosen region and subscription; enabling it is part of this story and is safe to repeat.
- The dashboards and metrics screens are reachable from the internet exactly as the existing setups are; no extra protection is added in this story. The dashboards app's admin account is created by the tool itself and its password lives in a cluster secret, never in the repository.
- Sign-in with work accounts (Entra ID), limited to people with contributor access to the subscription, is a follow-up story: it needs an HTTPS hostname and certificate and an app registration with tenant-side assignment, and its access list must be maintained by hand.
- The chosen logs-store release is selected when this story is built and pinned in the Azure-specific settings file; the Amazon/local choice is neither reused nor changed.
- The dashboards app keeps its data in the same small in-cluster database arrangement as today.
- Traces, traffic monitoring, and the other optional tools the story text defers, application workloads, and alerting rules are out of scope for this story.
- No automated test cases are added; verification is the read-only live check plus the repository's own checks, as recorded in the clarifications above.
- One cluster target is in use at a time, as today.
