# Feature Specification: Azure Cluster Support

**Feature Branch**: `001-azure-aks-setup`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Extend the existing infrastructure setup so it can also create an empty Kubernetes cluster on Azure, matching the existing Amazon cluster's node groups, labels, and sizes. The cloud provider is chosen by a setting in the shared configuration file."

## Plain-language glossary

- **Cluster**: a group of machines that runs containerised applications together.
- **Amazon cluster (EKS)**: the cluster the repository creates on Amazon Web Services today.
- **Azure cluster (AKS)**: the same kind of cluster, created on Microsoft Azure.
- **Node group**: a named group of machines inside a cluster that share a size and a purpose. This project's node groups are labelled by workload: apps, storage ("persistent"), monitoring ("observability"), and load generation.
- **Shared configuration file**: the single settings file every script in this repository reads. Nothing else is hand-edited to change behaviour.
- **Resource group**: a named container on Azure that groups everything created there, so it can all be removed together.
- **Subscription**: the Azure billing account a person's work is charged to; a person may have access to one or several.

## Clarifications

### Session 2026-09-08

- Q: Which settings must a user fill in, beyond Azure access credentials, before the setup commands can create the Azure cluster? → A: No credentials are stored anywhere; the user signs in to their Azure account beforehand with Azure's own command-line sign-in tool, and every command runs against that signed-in session. The configuration file must name the subscription to use and the location. The cluster name, and the resource group that holds everything created (named from the developer's name plus a short unique suffix), are generated automatically. When no location is given, one documented default location is used as a backup.
- Q: Where should the developer's name, used to name the Azure resource group, come from? → A: Detected automatically from the signed-in Azure account or the machine, not from the configuration file and not asked at run time.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stand up an empty Azure cluster (Priority: P1)

A developer who wants to try the project on Azure selects Azure in the shared configuration file, names their Azure subscription and a location, and signs in to their Azure account with Azure's own command-line sign-in tool. They then run the same start-everything command they use today. They get an empty cluster on Azure whose node groups, labels, and sizes mirror the existing Amazon setup. The cluster and a new resource group holding everything created are named automatically. Nothing else is installed on the cluster yet.

**Why this priority**: this is the foundation; without it, nothing Azure-related can follow.

**Independent Test**: can be fully tested by selecting Azure in the configuration file, signing in, running the start command once, and confirming an empty cluster exists that matches the documented Amazon cluster shape.

**Acceptance Scenarios**:

1. **Given** the developer is signed in to Azure and the subscription and location are set, **When** the developer runs the start command, **Then** an empty cluster is created on Azure with node groups, labels, and sizes matching the existing Amazon cluster, inside a new resource group, with an automatically generated cluster name.
2. **Given** the start command already succeeded once, **When** it is run again without changes, **Then** nothing new is created and the command finishes without error.

---

### User Story 2 - Remove everything afterwards (Priority: P2)

The same developer, done for the day, runs the existing cleanup command. Everything the Azure setup created is removed, leaving nothing behind and no surprise charges.

**Why this priority**: teardown safety is required the moment creation exists; without it, users are left paying for machines.

**Independent Test**: can be fully tested by running cleanup after a successful Azure setup and confirming no resources from the setup remain.

**Acceptance Scenarios**:

1. **Given** an Azure cluster created by the start command, **When** cleanup runs, **Then** the cluster and everything it created are gone.
2. **Given** nothing was ever created, **When** cleanup runs, **Then** it finishes without error.
3. **Given** a setup that stopped partway and reported what was already created, **When** the user runs cleanup, **Then** the partially created resources are also removed.

---

### User Story 3 - Existing setups are untouched (Priority: P3)

Anyone using the repository on Amazon or on their local machine continues exactly as before: same configuration entries still work, same start and cleanup commands still work. Because the person making this change may not have access to a real Amazon account, the check that nothing changed is done in two steps: first confirming the change alters no Amazon or local files, then one real run by a person who does have Amazon access.

**Why this priority**: protects current users; it constrains the change rather than adding value, so it ranks after the new capability.

**Independent Test**: can be tested by comparing the repository's Amazon and local files with their state before the change, and by a person with real Amazon access running the existing start and cleanup commands normally.

**Acceptance Scenarios**:

1. **Given** this change, **When** the repository's Amazon and local files are compared with their state before the change, **Then** they are identical.
2. **Given** a person with real Amazon access, **When** they run the existing start and cleanup commands normally, **Then** they behave exactly as before this change.

---

### Edge Cases

- What happens when the configuration file selects Azure but the Azure requirements (not signed in, subscription missing, unusable location) are not met? The start command must stop with a clear, plain-language message instead of half-creating anything.
- What happens when the configuration file selects neither supported provider? The start command must stop with a clear message naming the valid choices.
- What happens when creation or removal stops partway (network drop, quota, permissions)? The command must stop, tell the user in plain language exactly what was already created, and leave it in place. Nothing is deleted automatically. The user then either reruns start, which reuses what already exists without duplicating it, or runs cleanup to remove everything and start fresh.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The shared configuration file MUST let the user choose which cloud provider the setup commands act on.
- **FR-002**: The start command MUST create an empty cluster on the chosen provider, mirroring the existing Amazon cluster's node groups, labels, workload-separation markings (taints), sizes, and storage arrangements.
- **FR-003**: The start command MUST be safe to run twice without creating duplicates.
- **FR-004**: The cleanup command MUST remove everything the setup created on the chosen provider, leaving nothing behind.
- **FR-005**: The start and cleanup commands MUST refuse to act, with a clear plain-language message, when the chosen provider's requirements are missing or wrong — for Azure: not signed in, subscription missing, or an unusable location.
- **FR-006**: The start and cleanup commands MUST refuse to act, with a clear plain-language message, when no supported provider is selected.
- **FR-007**: Existing Amazon and local behaviour, including every existing configuration entry, MUST keep working unchanged.
- **FR-008**: Only the empty cluster and its node groups are in scope; no application components and no auxiliary cloud services are installed.
- **FR-009**: The setup on Azure MUST create one new resource group that holds everything it creates, named from the developer's name (detected automatically from the signed-in Azure account or the machine) plus a short suffix derived from the settings, so the same settings always produce the same names. It MUST generate the cluster name automatically.
- **FR-010**: The Azure location MUST come from the configuration file; when it is missing, the setup MUST fall back to one documented default location.
- **FR-011**: When creation or removal stops partway, the command MUST stop with a plain-language report of what was already created and MUST NOT delete or roll back anything automatically; the user retries start, which reuses what exists, or runs cleanup.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user signed in to Azure, with subscription and location set in the configuration file, gets an empty cluster within the same working session, without any manual steps beyond signing in, filling in the configuration file, and running the commands.
- **SC-002**: Every node group on the Azure cluster matches its Amazon counterpart in purpose, count, machine size, labels, and workload-separation markings, checked against the documented Amazon setup.
- **SC-003**: After cleanup, no resources created by the Azure setup remain; a second cleanup run also finishes without error.

## Assumptions

- The user already has an Azure account with permission to create a cluster and signs in to it with Azure's own command-line sign-in tool; no credentials are stored in the repository or the configuration file.
- "Mirror the Amazon cluster" means matching the node groups, their labels, and machine sizes as they exist when this story is written; later Amazon changes are separate stories.
- Cluster creation happens in the user's own Azure subscription with its own costs; no budget or billing controls are added in this story.
- The empty-cluster scope covers the machines and the cluster itself only; connectivity to managed databases or secret stores comes in later stories.
- Generated names (resource group, cluster) are built from stable ingredients — detected developer name plus a suffix derived from the settings — so identical settings always produce identical names and reruns find what earlier runs created.
