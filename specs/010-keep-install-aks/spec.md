# Install Keep on AKS with one command

## Problem and outcome

**Problem.** The Azure demo has no tool for managing alerts. The later stories in this epic need one, called Keep, to collect alerts, group them into incidents and tell Slack. Nothing in the stack installs Keep today.

Installing Keep with its published defaults would not be safe for us:

- It sends usage reports to its makers: the server reports counts of its users, rules, alerts and incidents every hour, and the web page contacts the makers' servers whenever someone opens it.
- Some of its parts have no fixed version, so a rebuild next month can pull different software from what we tested.
- Its database has no password, so anything that can reach it can read it.
- Its database files sit on one machine's disk, not on the storage the rest of our stack uses.
- Removing Keep also deletes every secret whose name starts with `keep-`, which could wipe our own passwords.

*Example:* someone installs Keep on a Tuesday and the demo works. After a cluster rebuild on Friday a newer database version starts, the demo breaks, and nobody knows why.

**Outcome.** One command on the Azure demo installs Keep and leaves it running. Afterwards:

- Keep's four parts (server, web page, live-update service and database) are running on the machines set aside for monitoring.
- Keep sends no usage reports, from the server or from the web page.
- Every image Keep's install uses is pinned to an exact version tag. The start-up wait container, the uninstall cleanup image and MySQL also carry an exact digest. No image uses `latest` or another floating tag.
- The database has a password, created on the first run and reused after that. A login with no password is refused.
- The database files sit on the same storage as the rest of the stack.
- The AI key is kept in a secret in the cluster (`sre-keep-ai-env`, key `fireworks.key`), created at install time from a local file that is not in git. The backend reads it as its AI key. Keeping `fireworks.key` as the Secret key is a proposed exception to AD-008 and is not yet accepted (AD-016). Whether the web page gets its own copy is an open question below. Passwords never appear in git.
- Removing Keep does not delete our own secrets. After a reinstall, the same database password still works.
- Running the command a second time changes nothing and restarts nothing.
- If the AI key file is missing, the command run on its own stops before touching the cluster and names the missing file. Inside the full Azure setup, it skips Keep with a message and the rest of the setup finishes.
- Keep's page opens from a laptop through a temporary connection. There is no login yet; story 6a adds it.

**Known limits.** Removing Keep deletes its saved data, so a reinstall starts empty. The cleanup image that runs on removal is a third-party image pinned by digest, so moving to a newer one is a deliberate change. All Keep pods and the cleanup job share one ServiceAccount. The chart binds that ServiceAccount to `create`, `get`, `list`, `patch` and `delete` on Secrets across the whole namespace, and offers no per-pod identity. The backend needs `create`, `get`, `patch` and `delete` for Keep's Kubernetes secret store, and the cleanup hook needs `get`, `list` and `delete`. A compromised Keep pod, including the web page or websocket server, could therefore read or change the database Secret. Whether to accept this or separate the identities is open for the Architect (AD-016; research.md Finding 15). The existing cleanup hook needs the `list` verb. The chart offers no setting to change the Role, and a shared Role without `list` would likely make the hook fail without a failed job (source read; not run). Separate Roles through a post-render step are one option, not yet tested (research.md Finding 17). Even with separate Roles, the cleanup hook and the backend keep namespace-wide Secret access that RBAC cannot narrow to `keep-*` names (research.md Finding 18). That residual risk is open for the Architect.

## Scope and must keep working

**In scope.** Installing Keep on the Azure demo, as described in the Outcome above.

**Out of scope.** These belong to later stories in the same epic:

- Sending alerts from the monitoring system to Keep, and the keys that protect that link.
- Grouping alerts into incidents.
- Posting to Slack, and connecting the AI service.
- Keep's workflows.
- The login (story 6a) and Keep's own web address (story 6b).
- Installing Keep on the local or Amazon clusters.

**Must keep working.**

- Setting up the local cluster and the Amazon cluster, which do not change.
- The full Azure setup when no Keep secrets are present: it finishes as it does today.
- Everything else that runs on the monitoring machines still starts. Keep must not crowd it out.
- The repo's lint check passes, including the check on the new Keep settings file.
- Deleting the Azure cluster still removes everything, Keep included.

## User scenarios and acceptance

**US1: Install Keep safely (must have).** A person setting up the Azure demo runs one command and gets a working Keep that follows the Outcome.

1. **Given** the Azure demo is running and the AI key file exists, **when** the person runs the install command, **then** Keep's four parts are Running on the monitoring machines and the Keep page opens through a temporary connection with no login.
2. **Given** Keep is installed, **when** someone lists the images it runs, **then** every image shows an exact version tag, the wait container, cleanup image and MySQL also show a digest, and no image uses `latest`.
3. **Given** Keep is installed, **when** someone opens the Keep page and when the server's logs are checked, **then** neither sends a usage report.
4. **Given** Keep is installed, **when** someone tries to log in to its database without a password, **then** it is refused; with the generated password it works.
5. **Given** the rest of the monitoring stack is running, **when** Keep is installed, **then** every monitoring pod is still Running.

**US2: Run it again, remove it, bring it back (must have).** A person re-runs the command, or removes Keep and installs again.

1. **Given** Keep is installed, **when** the person runs the command a second time, **then** nothing changes and no part restarts.
2. **Given** Keep is installed, **when** the person removes Keep, **then** our own secrets (the AI key and the database password) are still there.
3. **Given** Keep was removed, **when** the person installs again, **then** Keep is Running again, the same database password works, and the saved data starts empty.

**US3: The AI key file is missing (must have).** Example: a new teammate forgot to create the file.

1. **Given** the AI key file is missing, **when** the person runs the Keep command on its own, **then** it stops before changing the cluster and names the missing file.
2. **Given** the file is missing, **when** the person runs the full Azure setup, **then** Keep is skipped with a message and the rest of the setup finishes.

## Requirements and success criteria

**Requirements**

- **FR-001.** One command installs Keep's four parts on the Azure demo's monitoring machines. (US1.1)
- **FR-002.** Keep sends no usage reports, from the server or the web page. (US1.3)
- **FR-003.** Every image is pinned to an exact version tag. The start-up wait container, the cleanup image and MySQL also carry a digest. No image uses `latest` or another floating tag. (US1.2)
- **FR-004.** The database requires a password, created on the first run and reused. A login without it is refused. (US1.4, US2.3)
- **FR-005.** The database files use the stack's standard storage. (SC-008)
- **FR-006.** The AI key and the database password reach Keep as secrets in the cluster, built from local files. No secret value is in git. The database Secret `sre-keep-db` carries the connection string and the root password under the names AD-013 sets, and the database mounts only the root password. The AI key Secret `sre-keep-ai-env` carries the key under `fireworks.key`, and the backend reads it through an explicit secret reference. That wiring and the key name are a proposed exception to AD-008, pending Architect acceptance (AD-016). (SC-006, SC-009)
- **FR-007.** Removing Keep leaves our own secrets in place. (US2.2)
- **FR-008.** Running the command again changes nothing and restarts nothing. (US2.1)
- **FR-009.** With the AI key file missing, the command on its own stops before changing the cluster and names the file; inside the full Azure setup it skips Keep with a message. (US3)
- **FR-010.** Keep's page opens through a temporary connection, with no login. (US1.1)
- **FR-011.** The existing setups, the other monitoring pods and the lint check keep working. (US1.5, Must keep working)

**Success criteria**

- **SC-001.** All four Keep parts are Running within 5 minutes of the command starting.
- **SC-002.** A second run changes 0 resources and restarts 0 parts.
- **SC-003.** After start, the server logs 0 usage reports, and the Keep page makes 0 calls to the makers' servers in a 25-second page load.
- **SC-004.** 0 images use a floating tag, and 0 images are unpinned. The rendered manifests show each image with its tag, and the three digest-pinned images with their digest (research.md Findings 9 to 13).
- **SC-005.** A database login with no password is refused, and one with the generated password works, both before and after a remove and reinstall.
- **SC-006.** After removing Keep, both of our secrets still exist. After the reinstall, Keep is Running with an empty database.
- **SC-007.** With the key file missing, the command exits before any change to the cluster, and its message names the file.
- **SC-008.** The database volume is on the stack's standard storage, shown by listing the volume after install.
- **SC-009.** None of the files this story adds contains a secret value, and the repo's secrets check passes with them.

## Edge Cases

- **The AI key file exists but is empty.** It counts as missing: same message, same behavior as US3.
- **The cluster is stopped or cannot be reached.** The command stops with a clear message and changes nothing.
- **The install is cut off halfway** (the laptop loses its connection). Running the command again finishes the job. It does not fail on what the first run already made.
- **The cluster was rebuilt but the local password file is still there.** The command reuses the file's password, and Keep starts with an empty database.
- **Someone makes their own secret whose name starts with `keep-`.** It is deleted when Keep is removed. Our own secrets avoid that prefix for this reason.
- **A Keep part cannot start** (for example the monitoring machines have no room). The command ends with an error. It never prints a success message.

## Assumptions and open questions

**Research.** The research of 2026-10-29 ran on the real Azure demo cluster and is in [research.md](research.md). It covers Keep's packaged defaults, the image versions, the removal cleanup, the database password, and the usage reports (server log and a real browser). The 2026-11-05 update is offline: rendered Helm output, registry metadata and source reads. It has not been run on the cluster (research.md, "Update 2026-11-05").

**Decisions already made by the developer (2026-10-29)**

- The login stays in story 6a, not here.

**Developer decisions after Architect consultation (not Architect approvals) (2026-11-05)**

These are developer decisions made after consulting the Architect. They are not Architect approvals. The items under "Proposed, not accepted" below have no Architect approval yet.

- The start-up wait container is pinned through a values override, `busybox:1.38.0` by digest, as AD-013 point 3 sets. The chart renders the override (research.md Finding 9). This replaces the earlier decision to leave it unpinned.
- The cleanup image is `alpine/k8s:1.34.11` by digest. Bitnami's kubectl has no version tags, and bitnamilegacy is frozen (research.md Finding 10).
- The database Secret names and keys follow AD-013, and the password is `openssl rand -hex 24`.
- The Fireworks base URL is `https://api.fireworks.ai/inference/v1`, and the model is the one named in research.md Finding 12. The backend wiring that carries the key (`OPENAI_API_KEY` from `fireworks.key`) is proposed under AD-016, not accepted.

**Proposed, not accepted**

- Keeping `fireworks.key` as the Secret key is a proposed exception to AD-008. It needs Architect acceptance (AD-016).
- The web page's AI key, its Secret, and its base URL and model settings are open (see Open questions).
- The ServiceAccount separation is open for the Architect (AD-016). No option is adopted.

**Assumptions**

- The Azure demo cluster is running and reachable when the command starts. The command does not start it.
- The local secrets folder is where the AI key file and the generated database password live (AD-008). The plan names the files.
- The monitoring machines have room for four more pods. This was seen, not measured.
- **Proven by hand in research, but not yet by the command itself:** the four parts running, the password rules, the secrets surviving removal, and the empty database after reinstall.
- **Not yet proven anywhere. Implementation must prove them:** the second run changing nothing (FR-008), the missing key file behavior (FR-009), and the first, second, third and sixth edge cases.
- **Rendered by Helm, not yet run on the cluster:** the busybox override, the cleanup image and the digests, and the Secret wiring (research.md Findings 9, 11, 13 and 14). Running them on the cluster is part of the build.
- **Registry metadata only:** the image digests, the image layer contents and the Fireworks model identifier (research.md Findings 10 and 12). The cleanup image has not been executed, because Docker was not running.
- **Source read at the pinned versions, not run:** the frontend route's SDK reads `OPENAI_BASE_URL` from the environment, and the backend's Kubernetes secret store calls the Secret API (research.md Findings 15 and 16).

**Known limits, not handled here**

- Azure can take back a monitoring machine (they are spot machines). Keep's recovery from that is untested.
- A lost password file while Keep's database still exists is not handled.
- Whether the web page sends error reports to a third party is not verified. The plan still switches that off.
- The model is thinking-only, so a small token limit returns empty answers. Keep's own AI calls on the cluster have not been tested, and the token limit they use is not yet checked (research.md Finding 12).
- The optional MySQL cleanup job is disabled by default and is not enabled by the install values. If it were enabled, its passwordless root login would be expected to fail under the AD-013 root password (research.md Finding 19; source read, not run).

**Open questions.** Three need an answer before the plan:

- **The web page's copy of the AI key.** The page's AI route reads the key on the server only, and the browser sees only a yes-or-no flag. Either a second Secret, `sre-keep-ai-frontend` with key `OPEN_AI_API_KEY`, built from the same file (recommended), or no key on the page, which turns the page's AI features off. The chart cannot read `fireworks.key` on the page (research.md Finding 11). If the key is enabled, the page also needs `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME` (research.md Finding 16). The proposal stays Proposed until the developer and the Architect accept it.
- **AD-016 (Proposed, requires Architect acceptance).** It covers the proposed exception that keeps `fireworks.key` as the Secret key, the backend key wiring, and the second Secret. Its acceptance is needed before the plan.
- **Shared ServiceAccount.** Accept the chart's single identity with Secret rights, or separate the identities by a post-render step. The chart cannot separate them (research.md Finding 15). This is recorded as open in AD-016, and no option is adopted.
