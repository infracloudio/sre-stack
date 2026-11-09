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
- Every image Keep's install uses is pinned to an exact version tag. The start-up wait container and MySQL also carry an exact digest. No image uses `latest` or another floating tag. During install and during the documented uninstall command, no third-party cleanup image is pulled or run.
- The database has a password, created on the first run and reused after that. A login with no password is refused.
- The database files sit on the same storage as the rest of the stack.
- The AI key is kept in a secret in the cluster (`sre-keep-ai-env`, key `fireworks.key`), created at install time from a local file that is not in git. The backend reads it as its AI key. Keeping `fireworks.key` as the Secret key is a proposed exception to AD-008 and is not yet accepted (AD-016). The web page's copy of the key is a proposed configuration that needs Architect acceptance (see Open questions). Passwords never appear in git.
- Removing Keep does not delete our own secrets. After a reinstall, the same database password still works.
- The documented uninstall command, `helm uninstall keep -n <namespace> --no-hooks`, does not execute the chart's pre-delete cleanup hook, so it does not delete Keep-generated Secrets. An administrator removes them with the manual procedure after reviewing their names (research.md Finding 20).
- Running the command a second time changes nothing and restarts nothing.
- If the AI key file is missing, the command run on its own stops before touching the cluster and names the missing file. Inside the full Azure setup, it skips Keep with a message and the rest of the setup finishes.
- Keep's page opens from a laptop through a temporary connection. There is no login yet; story 6a adds it.

**Known limits.** Removing Keep deletes its saved data, so a reinstall starts empty. The Architect has agreed that the Kubernetes cleanup hook that used `alpine/k8s:1.34.11` must not execute. The documented uninstall command, `helm uninstall keep -n <namespace> --no-hooks`, prevents it from running, so no third-party cleanup image runs during the documented uninstall (research.md Finding 20). A plain `helm uninstall` without the flag would still run the hook. Keep-generated Secrets therefore remain after the documented uninstall, and their removal is an administrator-operated manual task. All Keep pods share one ServiceAccount. The chart binds that ServiceAccount to `create`, `get`, `list`, `patch` and `delete` on Secrets across the whole namespace, and offers no per-pod identity. The backend needs `create`, `get`, `patch` and `delete` for Keep's Kubernetes secret store. The chart's Role also grants `list`, which the source read does not show the backend needing, and which the removed hook was the only component to use (research.md Findings 17 and 20). A compromised Keep pod sharing this ServiceAccount, including the web page or websocket server, could potentially access or modify Secrets belonging to other components, including `sre-keep-db` and `sre-keep-ai-env`. These permissions are namespace-wide, not restricted to Secrets beginning with `keep-`. The developer has selected retaining the shared ServiceAccount for the initial implementation, subject to Architect review (AD-016; research.md Finding 15). Retaining it does not mitigate this risk. The residual risk is accepted (AD-016 decision 4; developer-reported Architect acceptance, 2026-11-09). The chart has no setting to change the Role. Removing the hook does not remove the backend's namespace-wide Secret permissions, and it does not eliminate this residual risk (research.md Findings 17 and 18). Even with separate Roles, the backend keeps namespace-wide Secret access that RBAC cannot narrow to `keep-*` names (research.md Finding 18). That residual risk is accepted, not removed.

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
2. **Given** Keep is installed, **when** someone lists the images it runs, **then** every image shows an exact version tag, the wait container and MySQL also show a digest, no image uses `latest`, and no third-party cleanup image is listed.
3. **Given** Keep is installed, **when** someone opens the Keep page and when the server's logs are checked, **then** neither sends a usage report.
4. **Given** Keep is installed, **when** someone tries to log in to its database without a password, **then** it is refused; with the generated password it works.
5. **Given** the rest of the monitoring stack is running, **when** Keep is installed, **then** every monitoring pod is still Running.

**US2: Run it again, remove it, bring it back (must have).** A person re-runs the command, or removes Keep and installs again.

1. **Given** Keep is installed, **when** the person runs the command a second time, **then** nothing changes and no part restarts.
2. **Given** Keep is installed, **when** the person removes Keep, **then** our own secrets (the AI key and the database password) are still there.
3. **Given** Keep was removed, **when** the person installs again, **then** Keep is Running again, the same database password works, and the saved data starts empty.
4. **Given** Keep was removed with Helm, **when** the administrator follows the manual cleanup procedure in research.md Finding 20, **then** only Secrets whose names begin with `keep-` and that the administrator reviewed are deleted, and `sre-keep-db` and `sre-keep-ai-env` remain.

**US3: The AI key file is missing (must have).** Example: a new teammate forgot to create the file.

1. **Given** the AI key file is missing, **when** the person runs the Keep command on its own, **then** it stops before changing the cluster and names the missing file.
2. **Given** the file is missing, **when** the person runs the full Azure setup, **then** Keep is skipped with a message and the rest of the setup finishes.

## Requirements and success criteria

**Requirements**

- **FR-001.** One command installs Keep's four parts on the Azure demo's monitoring machines. (US1.1)
- **FR-002.** Keep sends no usage reports, from the server or the web page. (US1.3)
- **FR-003.** Every image is pinned to an exact version tag. The start-up wait container and MySQL also carry a digest. No image uses `latest` or another floating tag. During install and during the documented uninstall command, no third-party cleanup image is pulled or run. (US1.2)
- **FR-004.** The database requires a password, created on the first run and reused. A login without it is refused. (US1.4, US2.3)
- **FR-005.** The database files use the stack's standard storage. (SC-008)
- **FR-006.** The AI key and the database password reach Keep as secrets in the cluster, built from local files. No secret value is in git. The database Secret `sre-keep-db` carries the connection string and the root password under the names AD-013 sets, and the database mounts only the root password. The AI key Secret `sre-keep-ai-env` carries the key under `fireworks.key`, and the backend reads it through an explicit secret reference. That wiring and the key name are an exception to AD-008 (AD-016; developer-reported Architect acceptance, 2026-11-09). The web page session secret (`NEXTAUTH_SECRET`) is generated like the database password and delivered as a Secret, and the chart default is not used. (SC-006, SC-009)
- **FR-007.** Removing Keep leaves our own secrets in place. (US2.2)
- **FR-008.** Running the command again changes nothing and restarts nothing. (US2.1)
- **FR-009.** With the AI key file missing, the command on its own stops before changing the cluster and names the file; inside the full Azure setup it skips Keep with a message. (US3)
- **FR-010.** Keep's page opens through a temporary connection, with no login. (US1.1)
- **FR-011.** The existing setups, the other monitoring pods and the lint check keep working. (US1.5, Must keep working)
- **FR-012.** The Keep web page is configured with `OPEN_AI_API_KEY` sourced from Secret `sre-keep-ai-frontend` (key `OPEN_AI_API_KEY`), `OPENAI_BASE_URL=https://api.fireworks.ai/inference/v1`, and `OPENAI_MODEL_NAME` set to the verified Fireworks model identifier documented in research.md Finding 12 (`accounts/fireworks/models/glm-5p3-flash`). The backend configuration is unchanged: Secret `sre-keep-ai-env`, key `fireworks.key`, environment variable `OPENAI_API_KEY` (FR-006). Acceptance: SC-010. (AD-016 point 2; developer-reported Architect acceptance, 2026-11-09)
- **FR-013.** The documented uninstall command, `helm uninstall keep -n <namespace> --no-hooks`, prevents the chart's pre-delete cleanup hook from executing, and it does not delete Keep-generated Secrets. The unmodified chart may still render the hook manifest. Removing Keep-generated Secrets is an administrator-operated manual task: list the Secrets whose names begin with `keep-`, review the names, and delete only the reviewed Secrets, following the procedure in research.md Finding 20. The procedure never prints Secret values. Architect agreement to remove the hook is recorded in research.md Finding 20. Acceptance: SC-011. (US2.2)

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
- **SC-010.** Pass/fail, checked in the rendered Helm output of the values file (no cluster needed): the frontend container has an `envFrom` `secretRef` to Secret `sre-keep-ai-frontend`; its `env` contains `OPENAI_BASE_URL` with value `https://api.fireworks.ai/inference/v1` and `OPENAI_MODEL_NAME` with value `accounts/fireworks/models/glm-5p3-flash`; and the Secret built by the install step has a data key named `OPEN_AI_API_KEY`. Only key names are checked, and no secret value is printed. The same values must also be present on the running frontend pod after install. That runtime check is not yet run. (FR-012)
- **SC-011.** Pass/fail, checked against the documented uninstall command and the manual cleanup procedure (FR-013), without requiring the rendered manifest to be absent: (a) the documented uninstall command is `helm uninstall keep -n <namespace> --no-hooks`, which includes `--no-hooks` and so prevents the pre-delete cleanup hook from executing during uninstall; (b) the procedure lists the matching Secret names before any deletion command is shown, and states that the administrator must review them first; (c) no procedure step prints a Secret value. Check (a) is met by the documentation (research.md Finding 20). It has not been tested against AKS, and no uninstall has been run. (FR-013)

## Edge Cases

- **The AI key file exists but is empty.** It counts as missing: same message, same behavior as US3.
- **The cluster is stopped or cannot be reached.** The command stops with a clear message and changes nothing.
- **The install is cut off halfway** (the laptop loses its connection). Running the command again finishes the job. It does not fail on what the first run already made.
- **The cluster was rebuilt but the local password file is still there.** The command reuses the file's password, and Keep starts with an empty database.
- **Someone makes their own secret whose name starts with `keep-`.** It is not deleted by Helm uninstall. The manual cleanup procedure lists it for review, and it is deleted only if the administrator confirms it. Our own secrets avoid that prefix for this reason.
- **A Keep part cannot start** (for example the monitoring machines have no room). The command ends with an error. It never prints a success message.

## Assumptions and open questions

**Research.** The research of 2026-10-29 ran on the real Azure demo cluster and is in [research.md](research.md). It covers Keep's packaged defaults, the image versions, the removal cleanup, the database password, and the usage reports (server log and a real browser). The 2026-11-05 update is offline: rendered Helm output, registry metadata and source reads. It has not been run on the cluster (research.md, "Update 2026-11-05").

**Decisions already made by the developer (2026-10-29)**

- The login stays in story 6a, not here.

**Developer decisions after Architect consultation (not Architect approvals) (2026-11-05)**

These are developer decisions made after consulting the Architect. They are not Architect approvals. The items under "Proposed, not accepted" below have no Architect approval yet.

- The start-up wait container is pinned through a values override, `busybox:1.38.0` by digest, as AD-013 point 3 sets. The chart renders the override (research.md Finding 9). This replaces the earlier decision to leave it unpinned.
- The Architect agreed (recorded 2026-11-06) that the Kubernetes cleanup hook container that used `alpine/k8s:1.34.11` must not execute. The documented uninstall command, `helm uninstall keep -n <namespace> --no-hooks`, prevents it from running (research.md Finding 20), and Secret cleanup is an administrator-operated manual task after uninstall. The image evaluation is kept as history (Finding 10). Bitnami's kubectl has no version tags, and bitnamilegacy is frozen (research.md Finding 10).
- The database Secret names and keys follow AD-013, and the password is `openssl rand -hex 24`.
- The Fireworks base URL is `https://api.fireworks.ai/inference/v1`, and the model is the one named in research.md Finding 12. The backend wiring that carries the key (`OPENAI_API_KEY` from `fireworks.key`) is proposed under AD-016, not accepted.

**Developer decisions (2026-11-06), pending Architect review**

- The chart's existing shared ServiceAccount is retained for the initial implementation, subject to Architect review. Post-render separation is not implemented, and no separate Roles or RoleBindings are introduced at this stage.
- The residual namespace-wide Secret risk is recorded, not mitigated. Architect acknowledgement of it is outstanding.

**Architect decision recorded (mechanism only; not acceptance of AD-016 or of the gate)**

- Uninstall mechanism (AD-016 decision 6, status Proposed as part of AD-016): `helm uninstall keep -n <namespace> --no-hooks`. No Helm post-renderer is introduced, the upstream Keep chart is neither forked nor modified, and Helm 3 is supported. The decision covers the mechanism only. AD-016 remains Proposed, and `gate:spec-approved` remains pending.

**Proposed, not accepted**

- Keeping `fireworks.key` as the Secret key is a proposed exception to AD-008, specific to the Fireworks Secret wiring. It needs Architect acceptance (AD-016).
- The Fireworks Secrets are a proposed configuration. The backend Secret is `sre-keep-ai-env`, with key `fireworks.key` and environment variable `OPENAI_API_KEY`. The frontend Secret is `sre-keep-ai-frontend`, with key `OPEN_AI_API_KEY`, populated from the same local key file and loaded through `frontend.envFromSecrets`. The frontend also needs `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME`. Both Secrets must be rotated together. This configuration needs Architect acceptance (see Open questions).
- Post-render ServiceAccount separation is an untested alternative and is not adopted.
- Operator-run manual cleanup is the chosen operational approach for Secret cleanup after uninstall (research.md Finding 20). Its procedure has not been run.

**Assumptions**

- The Azure demo cluster is running and reachable when the command starts. The command does not start it.
- The local secrets folder is where the AI key file and the generated database password live (AD-008). The plan names the files.
- The monitoring machines have room for four more pods. This was seen, not measured.
- **Proven by hand in research, but not yet by the command itself:** the four parts running, the password rules, the secrets surviving removal, and the empty database after reinstall.
- **Not yet proven anywhere. Implementation must prove them:** the second run changing nothing (FR-008), the missing key file behavior (FR-009), and the first, second, third and sixth edge cases.
- **Rendered by Helm, not yet run on the cluster:** the busybox override, the MySQL and busybox digests, and the Secret wiring (research.md Findings 9, 11, 13 and 14). Running them on the cluster is part of the build. The chart still renders the pre-delete cleanup hook, which the documented uninstall command does not execute (research.md Finding 20).
- **Registry metadata only:** the image digests and the Fireworks model identifier (research.md Findings 9, 12 and 13). The cleanup image is no longer used (research.md Finding 20).
- **Source read at the pinned versions, not run:** the frontend route's SDK reads `OPENAI_BASE_URL` from the environment, and the backend's Kubernetes secret store calls the Secret API (research.md Findings 15 and 16).

**Known limits, not handled here**

- Azure can take back a monitoring machine (they are spot machines). Keep's recovery from that is untested.
- A lost password file while Keep's database still exists is not handled.
- Whether the web page sends error reports to a third party is not verified. The plan still switches that off.
- The model is thinking-only, so a small token limit returns empty answers. Keep's own AI calls on the cluster have not been tested, and the token limit they use is not yet checked (research.md Finding 12).
- The optional MySQL cleanup job is disabled by default and is not enabled by the install values. If it were enabled, its passwordless root login would be expected to fail under the AD-013 root password (research.md Finding 19; source read, not run).

**Open questions.** Three Architect decisions or acknowledgements are needed before the plan:

- **The frontend Fireworks Secret.** The page's AI route reads the key on the server only, and the browser sees only a yes-or-no flag. The proposed configuration is a second Secret, `sre-keep-ai-frontend` with key `OPEN_AI_API_KEY`, populated from the same local key file and loaded through `frontend.envFromSecrets`, with `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME` set on the frontend (research.md Findings 11 and 16). The chart cannot read `fireworks.key` on the page. The Architect's acceptance is needed. If it is not accepted, the alternative is no key on the page, which turns the page's AI features off.
- **AD-016 (Proposed, requires Architect acceptance).** It covers the proposed exception that keeps `fireworks.key` as the Secret key, the backend key wiring, and the second Secret. Its acceptance is needed before the plan.
- **Shared ServiceAccount and residual Secret risk.** The developer has selected retaining the chart's shared ServiceAccount for the initial implementation, subject to Architect review. The Architect must review it and explicitly acknowledge the residual namespace-wide Secret risk, which retaining the shared ServiceAccount does not mitigate (AD-016; research.md Finding 18). Post-render separation remains an untested alternative. Manual, operator-run cleanup is the chosen approach for Secret cleanup after uninstall (research.md Finding 20). The chart cannot separate the identities through values (research.md Finding 15).
