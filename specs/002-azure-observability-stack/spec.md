# Feature Specification: Azure Observability Stack

**Feature Branch**: `002-azure-observability-stack`

**Created**: 2026-09-15

**Status**: Draft

**Input**: User description: "Deploy the core observability stack — Prometheus, Grafana, Loki, and the optional OpenTelemetry Collector — onto the Azure cluster from the earlier Azure story, scheduled only onto the observability node pool via the same workload-separation marking the Amazon and local setups use. The dashboards must be reachable and healthy, the Azure-specific tool settings must live in their own folder, and the documentation and decision record must be updated. Also deploy a service mesh dashboard (Kiali), compatible with the service mesh already deployed on Azure by the shared-ingress story (#104). Add automated test cases that check the deployment, alongside the read-only live-cluster verification check."

## Plain-language glossary

- **Cluster**: a group of machines that runs containerised applications together.
- **Amazon setup, local setup, Azure setup**: the three ways this project deploys the same stack — on Amazon's cloud, on the developer's own machine, and on Microsoft's cloud.
- **Monitoring stack**: the tools that show what a running system is doing. Here it means a metrics store, a dashboards app, a logs store, and a service mesh dashboard.
- **Metrics store**: collects numbers over time, such as how much processor a service used (today this is Prometheus).
- **Dashboards app**: the web page with charts and log search (today this is Grafana).
- **Logs store**: collects and searches the text that programs print while running (today this is Loki).
- **Log shipper**: a small helper that forwards each machine's log text to the logs store, so logs actually arrive.
- **Telemetry collector**: an optional component that receives measurements from applications and forwards them on. Today it is installed only when someone asks for it.
- **Service mesh (Istio)**: the layer already installed on the Azure cluster by the shared-ingress story (#104) that watches traffic moving between services. The service mesh dashboard reads from it.
- **Service mesh dashboard (Kiali)**: the web page that shows the shape and health of the service mesh's traffic.
- **Observability pool**: the node group in the cluster reserved for monitoring, marked so only monitoring workloads may run there.
- **Workload-separation marking (taint)** and **toleration**: the mark that keeps other work off a pool, and the matching permission a workload carries to run there anyway.
- **Shared settings file**: the single settings file every script in this repository reads. Nothing else is hand-edited to change behaviour.
- **Tool settings file**: the file that lists the exact version and options used to install one tool, so the same install can be repeated later.
- **Release pin**: naming one exact version instead of accepting whatever is newest on the day.
- **Entry point**: one web address in front of the project's web screens, so people can open them from their own machine.
- **Routing step**: the separate, existing command, owned by the demo-applications story, that creates the routing resource the shared entry point uses to send traffic to a screen. This story depends on that command having already been run; it does not run it itself and does not thereby deploy any application workload.
- **Endpoints command**: the existing command that prints the web addresses of what is running.
- **Verification check**: a read-only script that inspects a live cluster and reports, in plain language, whether it matches what the setup should have produced.
- **Deployment check**: an automated check that inspects the Azure-specific setup files themselves — no live cluster needed — and confirms they place every workload on the observability pool with the right marking, before anyone runs them for real.

## Clarifications

### Session 2026-09-25

- Q: The 2026-09-15 session decided the ordinary start command installs the cluster, then the monitoring stack, in one run. But every other Azure story shipped since (the service mesh, the demo applications) deliberately keeps the start command as cluster-only, with each later capability its own command run by hand. Should this story match that pattern? → A: Yes. This supersedes the 2026-09-15 answer below: the start command stays cluster-only on Azure; the monitoring stack, including the service mesh dashboard, installs through its own separate command, run after the cluster and the service mesh are ready. The telemetry collector stays optional and separate either way.
- Q: The dashboards app's and service mesh dashboard's addresses depend on a routing resource that only the demo-applications story's command creates — and that command is not called anywhere in this story's chain. How should this story get a working address? → A: This story depends on that routing command having already been run (by the developer, as a documented prerequisite step, the same way they already run the service mesh's own command first). It creates only the routing entries, not the application workloads themselves, so running it does not put this story's "no application workloads" boundary at risk. This story does not run that command itself and installs no routing resource of its own.

### Session 2026-09-24

- Q: The story text says "also add test cases to verify the Deployment," reversing this spec's earlier decision to skip automated test cases. What should "test cases" mean here? → A: Both kinds. Add a deployment check that needs no live cluster and confirms the Azure-specific setup files place every workload correctly, as part of the repository's own checks; keep the read-only verification check that inspects a live cluster after setup. Neither replaces the other.
- Q: Is the service mesh dashboard (Kiali) in scope for this story? → A: Yes. The shared-ingress story (#104) explicitly defers Kiali to the observability stack story and states that the dashboard's shared-entry-point path is created here, not there. This story installs the dashboard and its path, once the service mesh from #104 is already running; it installs no service mesh of its own.

### Session 2026-09-15

- Q: How should the two web screens be reachable from the developer's machine — one public address each, or one shared entry point? → A: One shared entry point: a single reachable address with each screen under its own path. Which ingress mechanism provides that address is a platform-wide decision outside this story — it is owned by the shared-ingress story (#104) and settled in this story's plan, not here. This story installs and maintains no gateway of its own; it only publishes its screens behind whatever shared entry point the platform provides.
- Q: Where should the dashboards app keep its data (dashboards, users, settings) on Azure? → A: The same arrangement as today — the small in-cluster database the existing setups use — so behaviour matches what people already know.
- Q: Which logging setup should Azure get? → A: The current stable release of the logs store plus a log shipper, so cluster logs actually appear in the dashboards. The version choice used by the Amazon/local setups is neither reused nor changed.
- Q: Does the ordinary start command now deploy the monitoring stack on Azure? → A: Yes. One command installs the cluster first, then the monitoring stack, then prints the addresses. The monitoring steps stay callable on their own, and the telemetry collector stays optional. (Superseded 2026-09-25 — the start command stays cluster-only, matching every Azure story shipped since; the monitoring stack now installs through its own separate command. See the 2026-09-25 session above.)
- Q: Where do Azure-specific settings live? → A: In their own folder. Every existing Amazon/local tool settings file stays exactly as it is.
- Q: Should the log shipper run on every machine it can reach, or stay pinned to the observability pool like the rest of the stack? → A: Mirror today's setups — the shipper runs wherever it can (cluster system machines, the app pool, and the observability pool), because a shipper only collects the machines it runs on; every other monitoring workload stays on the observability pool only.
- Q: Should Entra ID sign-in — so that people with contributor access to the Azure subscription can log in with their work account — be part of this story? → A: No. It becomes its own follow-up story, because it needs an HTTPS hostname and certificate (Entra ID requires https redirect addresses) plus an app registration with tenant-side assignment and consent; and "contributor on the subscription" cannot be checked automatically, so the access list must be maintained by hand. This story keeps the dashboards tool's own admin account.
- Q: How is the dashboards app's admin password handled? → A: The tool creates the admin account itself and keeps the password in a cluster secret; no credential is stored in the repository, and this story's documentation explains how to read it from the cluster.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Monitoring stack running on the Azure cluster (Priority: P1)

A developer selects the Azure provider in the shared settings file, signs in to Azure, and runs the start command to get a bare cluster, as they already do today. Once the cluster, the service mesh, and the routing step are ready — each its own command, run by hand in sequence, the same pattern already used for the service mesh and the demo applications on Azure — the developer runs the monitoring stack's own command. It installs the metrics store, the dashboards app, and the logs store, all placed on the observability pool. When it finishes, the endpoints command prints the web address for the dashboards and for the metrics screen. Opening the dashboards address shows the app loaded, with the metrics source and the logs source connected and healthy. No application data is needed yet — a healthy, reachable stack is the deliverable.

**Why this priority**: this is the whole point of the story. Without it the Azure path cannot be used for demos and cannot be validated end to end.

**Independent Test**: with the cluster ready, run the monitoring stack's command against Azure, then open the printed addresses and confirm both sources are connected and healthy, and that every monitoring workload runs on the observability pool.

**Acceptance Scenarios**:

1. **Given** a signed-in Azure session with the settings filled in and the cluster from the earlier Azure story available, **When** the monitoring stack's command runs, **Then** the metrics store, the dashboards app, and the logs store run on the cluster, every one of their workloads is placed on the observability pool (the log shipper alone running wherever it can reach, as in the existing setups), and the endpoints command prints a web address for each screen.
2. **Given** the monitoring stack is already installed, **When** its command runs again, **Then** nothing is duplicated and it finishes without error.
3. **Given** the monitoring stack is running, **When** the dashboards address is opened from the developer's machine, **Then** the app loads and reports the metrics source and the logs source connected and healthy.
4. **Given** the monitoring stack is running, **When** someone inspects where the monitoring workloads run, **Then** all of them run on the observability pool and none on the other pools, except the log shipper, which runs wherever it can reach.
5. **Given** the monitoring stack's command runs before the routing step has been run, **When** it finishes, **Then** the metrics store, the dashboards app, and the logs store still install and run, but the endpoints command says plainly that their addresses are not reachable yet and names the missing routing step, instead of printing a broken or misleading link.

---

### User Story 2 - Service mesh dashboard on Azure (Priority: P2)

A developer who already has the service mesh running on the Azure cluster (installed by the shared-ingress story) runs the service mesh dashboard's own command — separate from the monitoring stack's command, so a problem here never affects the metrics store, the dashboards app, or the logs store. It installs the service mesh dashboard, placed on the observability pool like the rest of the stack, and reachable from the shared entry point under its own path once the routing step has also been run. Opening it shows the mesh's traffic, confirming the mesh and the dashboard are wired together correctly.

**Why this priority**: it depends on the mesh from another story and adds visibility rather than the core stack itself, but the story names it as a required part of this story's outcome, so it ranks just below the core stack.

**Independent Test**: with the service mesh already running, run the service mesh dashboard's command, open its address, and confirm it loads and shows mesh traffic.

**Acceptance Scenarios**:

1. **Given** the service mesh is already running on the Azure cluster, **When** the service mesh dashboard's command runs, **Then** the dashboard is installed and runs on the observability pool.
2. **Given** the service mesh is not yet running, **When** the service mesh dashboard's command runs, **Then** it stops with a clear, plain-language message naming the missing mesh instead of installing a dashboard with nothing to show; the monitoring stack's own command and its workloads are unaffected either way.
3. **Given** the service mesh dashboard is running and the routing step has also been run, **When** its address is opened, **Then** it loads and shows the mesh's current traffic.
4. **Given** the service mesh dashboard is running but the routing step has not, **When** someone looks for its address, **Then** the endpoints command says plainly that the address is not reachable yet and names the missing routing step.

---

### User Story 3 - Optional telemetry collector on Azure (Priority: P3)

The optional telemetry collector, which today can be installed on the Amazon and local setups with its own command, can also be installed on the Azure cluster with an equivalent Azure-specific command. It is placed on the observability pool the same way. Neither the cluster-creation command nor the monitoring stack's command installs it.

**Why this priority**: it adds demo value, but the stack stands without it, so it ranks below the core stack and the service mesh dashboard.

**Independent Test**: run the collector command against the Azure cluster and confirm its workloads run on the observability pool; run the cluster-creation and monitoring commands alone and confirm the collector is not installed by either.

**Acceptance Scenarios**:

1. **Given** a running Azure monitoring stack, **When** the collector command runs, **Then** the collector is installed and its workloads run on the observability pool.
2. **Given** a fresh Azure setup, **When** only the cluster-creation and monitoring commands run, **Then** the collector is not installed.

---

### User Story 4 - Existing setups are untouched (Priority: P4)

Anyone using the Amazon or local setup keeps exactly what they have: the same commands, the same behaviour, and the same logging release choice. Because the person making this change may not have access to a live Amazon account, "nothing changed" is proven without a cloud account in two ways: the existing tool settings files are unchanged from before the change, and the repository's own checks still pass.

**Why this priority**: it protects current users and constrains the change rather than adding value, so it ranks last.

**Independent Test**: compare the existing tool settings files and the Amazon/local command definitions with their state before the change, and run the repository's own checks; both must show no change.

**Acceptance Scenarios**:

1. **Given** this change, **When** the existing tool settings files are compared with their state before the change and the Amazon/local commands are inspected, **Then** every existing tool settings file is identical and the Amazon/local commands behave exactly as before; the only edits to shared command wiring are the lines that select the Azure path, and all new Azure-specific settings and commands are additions in their own folder.
2. **Given** this change, **When** the repository's own checks run, **Then** they pass unchanged, giving no evidence of a change to Amazon or local behaviour.

---

### Edge Cases

- What happens when the monitoring setup is asked to run but the Azure requirements are not met (not signed in, no cluster, unusable location)? The command must stop with a clear, plain-language message instead of installing part of the stack.
- What happens when the shared entry point's routing step has not been run yet, or the endpoints command is run before it has? The setup must not print a broken or empty link for any of its screens; it says plainly which screens are installed but not yet reachable, and names the missing routing step. A rerun once the routing step exists finishes the job without reinstalling anything.
- What happens when the observability pool has too little room for the monitoring stack? The setup must stop with a plain-language message naming what could not be placed, and a rerun must reuse whatever was already installed.
- What happens when the small database the dashboards app stores its data in is missing or not ready? The dashboards app must not be reported as ready, and the setup must say which part is still missing.
- What happens when the service mesh dashboard is asked to install but the service mesh it depends on is not yet running? Only its own command stops, with a plain-language message naming the missing mesh; it must not install a dashboard with nothing to read from, and the monitoring stack's own command and workloads are unaffected.
- What happens when the service mesh is running but has no application traffic yet? The service mesh dashboard must still load and report healthy, showing an empty view; no application traffic is needed for this story, and is out of scope regardless.
- What happens when Azure already provides its own version of a component the monitoring setup would otherwise install (for example, a built-in equivalent the cluster ships with)? The setup must recognise this and skip or adapt to it without failing the rest of the monitoring install, since a name collision with a platform-provided component must not block the workloads that do not depend on it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Azure setup MUST offer its own command that installs the metrics store, the dashboards app, and the logs store onto the Azure cluster. This command MUST be run after the cluster itself is ready; the cluster-creation command MUST NOT install the monitoring stack automatically, matching the pattern already used for the service mesh and the demo applications on Azure.
- **FR-002**: Every workload of the monitoring stack, including the service mesh dashboard, MUST select the observability pool and tolerate its workload-separation marking, so the stack runs only there and nothing lands on the other pools. The log shipper is the one exception: exactly as in the existing setups, it MUST run on every machine it can reach (cluster system machines, the app pool, and the observability pool) so their logs are collected. Platform components this story does not install, such as the shared entry point, the service mesh, or the routing step, run wherever their own story places them.
- **FR-003**: The monitoring stack's command, and the service mesh dashboard's command, MUST each be safe to run twice: a second run installs nothing new and finishes without error.
- **FR-004**: The endpoints command MUST print a working web address for the dashboards app and for the metrics screen of the Azure setup once they are both installed and the routing step has been run, with no manual step beyond running it.
- **FR-005**: The two web screens, and the service mesh dashboard, MUST be reachable from the developer's machine through one shared public address, each under its own path on that address, once the routing step has been run. The shared entry point, the underlying service mesh, and the routing step are each provided by other stories; this story MUST NOT install or configure a gateway, a service mesh, or a routing resource of its own — it depends on the routing step having already been run, the same way it depends on the service mesh already running, and only adds its own screens' behaviour on top of what those steps provide.
- **FR-006**: The dashboards app MUST load with the metrics source and the logs source connected and healthy, with no application data required.
- **FR-007**: The logs store MUST be installed from its own Azure-specific tool settings file, pinned to one current stable release chosen when this story is built. It MUST NOT reuse the release choice of the Amazon/local setup, and the Amazon/local logging setup MUST NOT change.
- **FR-008**: All Azure-specific tool settings files MUST live in their own folder; no existing Amazon/local tool settings file may change.
- **FR-009**: The dashboards app's data MUST be stored the same way as today, in the small in-cluster database the existing setups use.
- **FR-010**: The optional telemetry collector MUST be installable on the Azure cluster through its own Azure-specific command, placed like the rest of the stack; neither the cluster-creation command nor the monitoring stack's command MUST install it.
- **FR-011**: An automated deployment check that needs no live cluster MUST inspect the Azure-specific setup files themselves and confirm every monitoring workload definition, including the service mesh dashboard, selects the observability pool and tolerates its marking (log shipper excepted). This check MUST run as part of the repository's own checks, so a placement mistake is caught before anyone runs the setup for real.
- **FR-012**: A read-only verification check MUST inspect a live Azure cluster and report in plain language whether the monitoring workloads, including the service mesh dashboard, run on the observability pool and whether the dashboards app's sources are connected and healthy. It MUST only read, never change, cluster or cloud state.
- **FR-013**: When the Azure requirements are missing or wrong (not signed in, no cluster, unusable location), or when the observability pool cannot host the stack, the monitoring stack's command MUST stop with a clear, plain-language message and MUST NOT report the stack as ready. When the service mesh the dashboard depends on is not yet running, only the service mesh dashboard's own command MUST stop this way; it MUST NOT stop or affect the monitoring stack's command or its workloads.
- **FR-014**: The monitoring setup MUST NOT create anything outside the cluster that would outlive the existing cleanup command; running cleanup MUST still remove everything the setup created, including the service mesh dashboard.
- **FR-015**: Documentation this change touches — the project readme, the agent context notes, and the help listing — MUST describe the new Azure monitoring commands, including the service mesh dashboard's own command, how they chain together with the cluster, service mesh, and routing steps, and how to invoke them.
- **FR-016**: The design decisions made by this story MUST be recorded in the project's decision record.
- **FR-017**: Existing Amazon and local behaviour MUST keep working unchanged, including every existing command, the full Amazon stack, and the existing optional components.
- **FR-018**: The service mesh dashboard MUST be installable on the Azure cluster, through its own command separate from the monitoring stack's command, once the service mesh it depends on is running. It MUST run in a version compatible with that service mesh, and MUST NOT be installed twice or left in a conflicting state if a shared installation path also provides it.
- **FR-019**: Opening the service mesh dashboard's address MUST show it loaded and displaying the mesh's current traffic.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer signed in to Azure, with the settings filled in, gets the cluster, the service mesh, the routing step, and the running monitoring stack within one working session, with no manual steps beyond signing in, filling in the settings, and running the commands in sequence.
- **SC-002**: Every monitoring workload on the Azure cluster, including the service mesh dashboard, runs on the observability pool, and none runs on the other pools, except the log shipper, which runs on every machine it can reach as the existing setups do; checked against the live cluster.
- **SC-003**: Both web screens, and the service mesh dashboard, open from the developer's machine at the addresses the endpoints command prints once the routing step has run, and the dashboards app reports its metrics and logs sources connected and healthy.
- **SC-004**: The existing tool settings files are identical to their state before the change, the Amazon and local commands behave exactly as before, and the repository's own checks pass unchanged.
- **SC-005**: The deployment check, run as part of the repository's own checks with no live cluster, passes on a correct setup and fails if a monitoring workload's file is changed to skip the observability pool or its marking.
- **SC-006**: The read-only verification check, run against a freshly set-up Azure cluster, prints a report showing the monitoring workloads (including the service mesh dashboard) on the observability pool and the dashboards app's sources healthy; that report is the acceptance evidence for this story.
- **SC-007**: Running the monitoring stack's command, or the service mesh dashboard's command, a second time finishes without error and installs nothing new for either.
- **SC-008**: The service mesh dashboard opens at its address under the shared entry point and shows the mesh's current traffic.
- **SC-009**: A missing service mesh stops only the service mesh dashboard's command; the monitoring stack's command still succeeds and its workloads still run, checked by running the two commands independently.

## Assumptions

- The user already has an Azure account and signs in with Azure's own command-line sign-in tool, as in the earlier Azure story; no credentials are stored in the repository.
- The cluster from the earlier Azure story exists, or is created by the cluster-creation command; its observability pool carries the same workload-separation marking the other setups use.
- The service mesh, the shared entry point's routing step, and the resulting shared public address are each platform-wide steps provided by other stories, run by the developer before the monitoring stack's or the service mesh dashboard's command, in the same hand-run sequence already used for the service mesh and the demo applications on Azure. This story assumes each has already been run, depends on them by name rather than assuming they happen automatically, and does not run any of them itself. The routing step creates only routing entries for its own screens' use, not application workloads — running it does not put this story's "no application workloads" boundary at risk. The ingress mechanism, the mesh, their releases, and where their workloads run are decided by those other stories, not here. The single public address is enough — no hostname or certificate in this story. Cleanup is always the whole cluster, so anything those steps create is removed with it.
- The dashboards and metrics screens, and the service mesh dashboard, are reachable from the internet exactly as the existing setups are; no extra protection is added in this story. The dashboards app's admin account is created by the tool itself and its password lives in a cluster secret, never in the repository.
- Sign-in with work accounts (Entra ID), limited to people with contributor access to the subscription, is a follow-up story: it needs an HTTPS hostname and certificate and an app registration with tenant-side assignment, and its access list must be maintained by hand.
- The chosen logs-store release is selected when this story is built and pinned in the Azure-specific settings file; the Amazon/local choice is neither reused nor changed.
- The dashboards app keeps its data in the same small in-cluster database arrangement as today.
- No automated test coverage exists for infrastructure lifecycle scripts today beyond linting; this story adds the deployment check as the first of that kind, scoped to placement correctness only — it does not check whether a workload actually starts, which only the live verification check can do.
- Whether the service mesh dashboard reuses an already-existing shared installation or needs its own separate one is settled when this story is built, based on whether that shared installation's version is actually compatible with the service mesh version running on Azure; either way, FR-018 holds.
- One cluster target is in use at a time, as today.

## Out of Scope

- Tracing and traffic-visualisation tools (Tempo, Beyla, Caretta) on Azure — deferred to a later story.
- Deploying application workloads (the demo store, the tracing demo, or any other app) onto Azure — covered by a separate story. This story's dependency on the routing step (see Assumptions) creates only routing entries, never the workloads themselves.
- Alert rules or alert-routing configuration, on Azure or elsewhere.
- Changing the logs-store release used by the existing Amazon/local setup.
- Any secrets-manager or managed-database work.
- Sign-in with work accounts (Entra ID) for the dashboards app — deferred, per the clarifications above.
- Installing or configuring the shared entry point, the service mesh, or the routing step itself — all are owned by other stories; this story only depends on what they provide.
