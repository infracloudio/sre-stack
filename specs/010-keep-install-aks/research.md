# Research: Install Keep on AKS (story #123)

Run 2026-10-29 against AKS `sre-stack-452138` (resource group
`rijo-john-improving-com-aks-452138`, Kubernetes 1.34.11), started from the
stopped state with `az aks start`. Keep was not installed before this research.

**Status note (2026-11-06).** The Architect agreed to remove the Kubernetes cleanup hook container that used `alpine/k8s:1.34.11` (Finding 20). Findings that describe that hook (Findings 2, 6, 10, 15, 17 and 18) are kept as historical evidence or analysis. They no longer describe the implementation.

## Finding 1: three chart images are not pinned

Command: `helm template keep keephq/keep --version 0.1.97`, then grep for `image:`.
Chart 0.1.97 is the newest (`helm search repo keephq/keep --versions`), app 0.54.3.

| Component | Image in chart 0.1.97 | Pinned? |
|---|---|---|
| Backend | `us-central1-docker.pkg.dev/keephq/keep/keep-api:0.54.3` | yes |
| Frontend | `us-central1-docker.pkg.dev/keephq/keep/keep-ui:0.54.3` | yes |
| Websocket | `quay.io/soketi/soketi:1.4-16-debian` | yes |
| MySQL | `mysql:latest` | no |
| Init container | `busybox` (no tag) | no |
| Uninstall hook | `bitnami/kubectl:latest`, pull policy Always | no |

The chart's database values also hold a `postgres:latest` block (unused with MySQL).
Chart defaults for the database volume: `pv.enabled=true` (hostPath),
`storageClass: ""`. Default MySQL env: `MYSQL_ALLOW_EMPTY_PASSWORD=true`.
Source for hook and database keys: context7 `/keephq/helm-charts`.

## Finding 2: the hook needs a shell, and `bitnami/kubectl` has no version tags

The hook runs `/bin/sh -c` with `grep '^secret/keep-'` and `xargs kubectl delete`.
`registry.k8s.io/kubectl` is distroless (no shell), so it cannot be used.
Docker Hub tag listing (`hub.docker.com/v2/repositories/<repo>/kubectl/tags?name=1.3`):
- `bitnami/kubectl`: 0 versioned tags (only `latest` and digest tags).
- `bitnamisecure/kubectl`: 0 versioned tags.
- `bitnamilegacy/kubectl`: 125 tags, newest `1.33.4` (2025-08-22). Repo is labelled
  "Legacy Bitnami images (no longer updated)", so it gets no security fixes.

Candidate: `bitnamilegacy/kubectl:1.33.4`. Kubernetes 1.33 client against a 1.34
server is inside the supported one-minor skew. Trade-off: frozen image. Not yet
proven: that the hook really deletes the `keep-*` Secrets (check 2).

## Finding 3: candidate tags pull and run on the o11y pool

Docker Hub tags: `mysql:8.4.13` (newest 8.4 patch, 2026-10-28), `busybox:1.38.0`
(2026-10-28; `1.37.0` same day). Test pods in `default`, nodeSelector
`workload=o11y`, tolerating the `o11y` and spot taints (both are on that pool):

```
=== t-kubectl  Succeeded image=bitnamilegacy/kubectl:1.33.4 node=aks-o11y-41769888-vmss00000u
/usr/bin/sh
/usr/bin/grep
/usr/bin/xargs
/opt/bitnami/kubectl/bin/kubectl
Client Version: v1.33.4
Kustomize Version: v5.6.0
=== t-mysql  Succeeded image=mysql:8.4.13 node=aks-o11y-41769888-vmss00000u
/usr/sbin/mysqld  Ver 8.4.13 for Linux on x86_64 (MySQL Community Server - GPL)
=== t-busybox  Succeeded image=busybox:1.38.0 node=aks-o11y-41769888-vmss00000u
BusyBox v1.38.0 (2026-05-13 02:21:49 UTC) multi-call binary.
/bin/sh
```

Proves: the images pull and the hook image has `sh`, `grep`, `xargs`, `kubectl`.
Does not prove: MySQL honours `MYSQL_ROOT_PASSWORD_FILE` (check 4), or the hook
works with the chart's service account (check 2).

## Finding 4: `bitnami/kubectl` is customer-only and cannot be pinned

Docker Hub page `hub.docker.com/r/bitnami/kubectl` (read via WebFetch, so a
summary, not verbatim): the image is "only available to" Bitnami Secure Images
customers; packaging is Apache-2.0 (copyright Broadcom 2026); the only tag is
`latest`. Third-party coverage and the Bitnami catalog-change issue
(github.com/bitnami/charts/issues/35164) agree: free access is `latest` only,
for development; versioned images moved to the unsupported `bitnamilegacy`
repo. I did not find a current Broadcom page, so terms are unconfirmed.

Anonymous pull test from the o11y pool (pod `t-bitnami`, then deleted):
`bitnami/kubectl:latest` pulled, digest `sha256:bedd34c9...e660c5`, client
`v1.37.2`. So it works today, but: no version tag to pin (only a digest),
access terms say customers only, and a 1.37 client is three minors ahead of our
1.34 server (unsupported skew). Decision pending with the developer; current
recommendation is `bitnamilegacy/kubectl:1.33.4`.

**Superseded 2026-11-05 by Finding 10.** Neither option is selected: the chosen image is `alpine/k8s:1.34.11` pinned by its full digest.

## Finding 5: the chart cannot pin its busybox image

`grep -rn busybox` over chart 0.1.97: only `templates/backend.yaml:173`,
`image: busybox`, in the `wait-for-database` init container. No values key.
The only switch is `backend.waitForDatabase.enabled`. So "every chart image is
pinned" cannot be met by values alone; options are a post-render step, turning
the init container off, or narrowing the promise. Developer to decide.

## Finding 6: live check 2 passed (hook removes `keep-*` Secrets)

Throwaway `helm install keep keephq/keep --version 0.1.97 -n keep-research`
with values pinning `mysql:8.4.13` and `bitnamilegacy/kubectl:1.33.4`, o11y
selector and both tolerations, `database.pv.enabled=false`,
`database.pvc.storageClass=gp2`:

```
pod/keep-backend-569bf9b4dc-52b5k     1/1  Running  aks-o11y-41769888-vmss00000u
pod/keep-database-5c589c8588-vkgmm    1/1  Running  aks-o11y-41769888-vmss00000u
pod/keep-frontend-6d4459dc7c-ln84c    1/1  Running  aks-o11y-41769888-vmss00000u
pod/keep-websocket-5db4c9f6d6-rwnnj   1/1  Running  aks-o11y-41769888-vmss00000u
persistentvolumeclaim/keep-pvc  Bound  pvc-d5ec6754-...  5Gi  RWO  gp2
```

Then, with decoy Secrets `keep-decoy` and `sre-keep-decoy` created, a real
`helm uninstall keep -n keep-research --wait`:

```
release "keep" uninstalled        (exit 0)
pod/delete-keep-secrets-qmg67   0/1   Completed
--- secrets after:
sre-keep-decoy   Opaque   1      89s
```

Proves: the hook image runs the chart's script to completion, deletes
`keep-decoy`, and leaves `sre-keep-decoy` (naming rule holds). Side effect seen:
`keep-pvc` and its data were removed by the uninstall (`pvc.retain` defaults to
false). The namespace was deleted afterwards. The image used in this run was `bitnamilegacy/kubectl:1.33.4`, which is no longer the selected image. The selected `alpine/k8s:1.34.11` has not been run on the cluster (Finding 10). Not yet proven: check 3 reinstall
with the same generated password, and check 4 (`MYSQL_ROOT_PASSWORD_FILE`).

## Decision on Finding 5 (developer, 2026-10-29)

Narrow the promise: the busybox init image stays unpinned in the chart. The
spec says every image the values file can set is pinned, and names busybox as
the one exception the chart does not allow us to set.

**Superseded 2026-11-05 by Finding 9.** Chart 0.1.97 does accept a pinned busybox through values (`backend.waitForDatabase.enabled: false` plus `backend.extraInitContainers`), as AD-013 point 3 already set out. No exception is needed.

## Finding 7: live checks 3 and 4 passed

Key names in this finding (`root-password`, `connection-string`) and the 32-character password length are superseded by AD-013 and AD-008 (`mysql-root-password`, `DATABASE_CONNECTION_STRING`, `openssl rand -hex 24`). The live result still holds. See Finding 14 for the wiring.

Second throwaway install in `keep-research`, same pins as Finding 6, plus:
Secret `sre-keep-db` (keys `root-password` and `connection-string`, password
generated with `openssl rand -hex 16`, not shown here), the backend login read
through `backend.databaseConnectionStringFromSecret`, MySQL started with
`MYSQL_ROOT_PASSWORD_FILE=/run/db-secret/root-password` (Secret mounted through
`database.extraVolumes` and `extraVolumeMounts`), and `database.mysql.env`
replaced so the default `MYSQL_ALLOW_EMPTY_PASSWORD=true` is gone. Four pods
Running, `keep-pvc` Bound on `gp2`.

Check 4 (password file honoured), run with `kubectl exec` in the database pod:

```
env (values hidden): MYSQL_MAJOR, MYSQL_VERSION, MYSQL_SHELL_VERSION,
                     MYSQL_DATABASE, MYSQL_ROOT_PASSWORD_FILE
--- login, generated credential:   who = root@%   tables_in_keep = 51
--- login, empty credential:   ERROR 1045 (28000): Access denied for user 'root'@'127.0.0.1' (using password: NO)
--- login, wrong credential: ERROR 1045 (28000): Access denied for user 'root'@'127.0.0.1' (using password: YES)
--- backend logs: Running migrations... Running upgrade  -> 54c1252b2c8a, First migration
    ... -> c37ec8f6db3e -> 37019ca3eb2e -> dcbd2873dcfd -> 9ba0aeecd4d0 ...
```

The backend is Ready and 51 tables exist, so migrations completed.

Check 3 (uninstall, reinstall, same password):

```
release "keep" uninstalled
secret/sre-keep-db   Opaque   2   116s        (pods and PVC gone)
helm install ... STATUS: deployed   (backend, database, frontend, websocket 1/1 Running)
--- same credential login:  who = root@%   tables_in_keep = 51
--- empty credential:       ERROR 1045 (28000): Access denied ... (using password: NO)
Secret creationTimestamp unchanged: 2026-10-29T15:33:09Z
```

Proves: `sre-keep-db` survives the hook, the same generated password works after
reinstall, and an empty password is refused. The reinstall starts from an empty
volume (Finding 6), so the migrations ran again and the 51 tables are new.
Namespace and the local password file were deleted afterwards.

## Finding 8: Keep sends usage data by default (verified live)

Third throwaway install in `keep-research` with chart defaults plus placement
values only (no telemetry settings). Docs (context7 `/keephq/keep`,
`docs/deployment/configuration.mdx`): `POSTHOG_DISABLED` default "false", with a
built-in public PostHog key. Chart 0.1.97 sets none of these (`grep -i
posthog|telemetry|analytics|sentry` over `values.yaml` and `templates/`: only
`FRIGADE_DISABLED=true`).

Backend, defaults, `kubectl logs deploy/keep-backend` (properties as printed):

```
"message": "Uptime Reporting to Posthog launched."
"message": "Uptime reported to PostHog.", "status": "up", "keep_version": "0.54.3",
"tenants_count": 1, "providers_count": 0, "users_count": 1, "rules_count": 0,
"last_24_hours_incidents_count": 0, "last_24_hours_alerts_count": 0,
"last_24_hours_rules_created": 0, "last_24_hours_workflows_created": 0,
"last_24_hours_workflows_executed": 0, "db_request_duration_ms": 69,
"uptime_hours": 0, "$lib": "posthog-python", "$lib_version": "3.7.4", "$geoip_disable": true
```

Code (`keep/api/core/posthog.py`): `POSTHOG_DISABLED = os.getenv("POSTHOG_DISABLED",
"false").lower() == "true"`; `report_uptime.py` repeats the report every hour
(`UPTIME_REPORTING_CADENCE = 60 * 60`). `env` in the backend pod had no
`POSTHOG_DISABLED`.

Switch test: `kubectl set env deploy/keep-backend POSTHOG_DISABLED=true`, new
pod log: `"message": "Posthog reporting is disabled so no uptime reporting."`
and no "Uptime reported" line.

Frontend defaults (`env` in the pod): `POSTHOG_KEY=phc_...` (public key),
`POSTHOG_HOST=https://ingest.keephq.dev`, `FRIGADE_DISABLED=true`,
`NEXT_PUBLIC_SENTRY_DSN=https://...@o4505515398922240.ingest.us.sentry.io/...`.
Built code starts PostHog in the browser only when `POSTHOG_DISABLED` is not
"true" and a key is set, and skips Sentry user and `captureException` when
`SENTRY_DISABLED` is "true".

Frontend on the wire (Playwright browser, UI through `kubectl port-forward`,
`http://localhost:13000/`; `127.0.0.1` was refused by the browser, `localhost`
worked; no login screen). Requests outside `localhost`, defaults, after 25 s:

```
78. [GET]  https://ingest.keephq.dev/array/phc_muk9qE3T.../config.js => [200]
79. [POST] https://ingest.keephq.dev/decide/?v=3&ip=1&...&ver=1.230.1&compression=base64 => [200]
81. [POST] https://ingest.keephq.dev/e/?ip=1&...&ver=1.230.1&compression=gzip-js => [200]
99. [GET]  https://ingest.keephq.dev/static/posthog-recorder.js?v=1.230.1 => [200]
100. [GET] https://ingest.keephq.dev/static/web-vitals.js?v=1.230.1 => [200]
```

Same page after `kubectl set env deploy/keep-frontend POSTHOG_DISABLED=true
SENTRY_DISABLED=true` (pod env confirmed), 25 s: the same filter returned no
requests; only `localhost:13000` calls (`/incidents`, `/api/auth/session` x2).

Not observed: Sentry. No request to `*.sentry.io` appeared in either run, even
though the page logged a TypeError; Sentry sends on errors, so I cannot say it
sends or does not. Console errors in both runs were websocket failures (the
port-forward has no websocket route) and that TypeError; none are telemetry.

Backend Sentry: `sentry-sdk 1.45.1` is installed, but the only `keep` code
mentioning Sentry is the Sentry alert-source provider and mentions in rule
comments and demo data; no reporting setup found. Not tested on the wire.

Namespaces deleted afterwards; port-forward stopped.

## Other facts

- Alert rules (`robot-shop-alerts`, 6 alerts) were already applied; `kubectl diff`
  against `infra/azure/alert-rules/robot-shop-alerts.yaml` showed no difference.
- Keep is not installed. All four live checks from the issue are done (Findings 3, 6, 7).

## Update 2026-11-05: image and wiring verification

**Method.** Offline only. The Docker daemon was not running, so no image was started and nothing was applied to AKS. Renders used `helm template keep keephq/keep --version 0.1.97 -n keep` with dummy values in a scratch directory outside the repo. No real key or password was read or created. Registry facts came from the Docker Hub API and the registry's manifest and blob endpoints (anonymous pull tokens). Each finding is labelled **Rendered** (Helm output), **Registry** (registry metadata or image contents), or **Runtime pending** (needs the cluster or a running container).

### Finding 9: busybox override (AD-013 point 3). Rendered and Registry.

- Default render: `image: busybox` with no tag, on the `wait-for-database` init container (`templates/backend.yaml:171-174`, rendered line 323). This is the unpinned image the decision replaces.
- Override values: `backend.waitForDatabase.enabled: false`, and one `backend.extraInitContainers` entry named `wait-for-database` with `image: busybox:1.38.0@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4`, `imagePullPolicy: IfNotPresent`, and `command: ['sh', '-c', 'until nc -z keep-database 3306; do sleep 1; done;']`.
- Rendered result: one init container, pinned to that digest. No untagged `busybox` remains in the output. Template: `templates/backend.yaml:176` renders `extraInitContainers`.
- Digest: `sha256:a46257e0…586e5fa4` is the multi-platform index digest. The amd64 manifest is `sha256:f97baa533a26513c453a362be331a43eb60214302f449c16571b23cea141dce4`. Config: `architecture: amd64`, `os: linux`, user unset (runs as root), cmd `sh`. One layer, 2.1 MB. The layer contains `bin/sh`, `bin/grep`, `bin/xargs` and `bin/nc`.
- **Runtime pending.** The init container has not waited on the cluster's `keep-database`. The service name is hard-coded in the command and matches release name `keep`. The plan must render with the real release name.

### Finding 10: uninstall hook image (AD-013 point 3). Registry and Rendered. Evaluated; not selected (hook removed, Finding 20).

| Candidate | Registry evidence | Decision |
|---|---|---|
| `bitnami/kubectl` (official) | 786 tags. Filtering by name for 1.33 through 1.38 returns 0 versioned tags. Only `latest` and digest tags exist. Anonymous pull of `latest` succeeds; its index digest is `sha256:8f59408f9e896fc8992a0660a56687545bd06751f26531b4a26fca6d5dc7562d`. The `latest` digest recorded in Finding 4 is different, so `latest` has moved. | Rejected. A digest pins immutable image content, so `latest` could be pinned that way. The official repository still has no versioned tag for Kubernetes 1.34.11, which is the required version, so no tag-based pin is available. The October client (v1.37.2) was three minors above the 1.34.11 server (unsupported skew). Because `latest` has changed since October, its client version would need checking before any digest is chosen. Access terms are customer-only (Finding 4), not re-checked here. |
| `bitnamilegacy/kubectl:1.33.4` | Anonymous manifest read succeeds. Index digest `sha256:ed0b31a0508da84ee655c5c6e01bd3897fc56ad6cf69debb27fa1893a06d2246`. The repository is labelled no longer updated. | Rejected. Frozen, no security fixes. |
| `alpine/k8s:1.34.11` | Versioned tag that matches the cluster's Kubernetes 1.34.11 (Finding 1 header). Index digest `sha256:0382123ab8ae17d8da5d43cc299242933eb012cfbe56787b43731c942c3eed80`. amd64 manifest `sha256:9ec4a7d9720f07c2f4ff20025bc9798918a4b2a050fb62226dd4f3e904e59121`. 17 layers, 302.4 MB compressed. Config: `architecture: amd64`, `os: linux`, user unset (runs as root), entrypoint none, cmd `/bin/sh`. Layer listing (17,340 entries) includes `bin/sh`, `bin/grep`, `usr/bin/xargs` and `usr/bin/kubectl`. | **Evaluated; rejected for implementation (Finding 20).** |

- Rendered (historical; not part of the implementation): `image: alpine/k8s:1.34.11@sha256:0382123ab8ae17d8da5d43cc299242933eb012cfbe56787b43731c942c3eed80` with `imagePullPolicy: IfNotPresent`, from `deleteSecretJob.image` (`templates/delete-secret-job.yaml:17`).
- Hook requirements, from the template (historical; the hook is removed, Finding 20): `/bin/sh -c` runs `kubectl get secrets -n <namespace> -o name | grep '^secret/keep-'`, then `xargs kubectl delete`. The shell, grep, xargs and kubectl are present in the layer listing.
- Hook permissions, from the templates (historical): the hook's pod uses ServiceAccount `keep`. Role `secret-manager-role` (`templates/role-secret-manager.yaml`) grants `create`, `delete`, `get`, `list` and `patch` on Secrets in the namespace. RoleBinding `secret-manager-rolebinding` binds it to `keep`. The rendered output shows that backend, database, frontend, websocket and the hook pods all run as `keep`. So every Keep pod holds the same Secret rights, which is broader than the hook needs. This was recorded as a risk. The hook's permissions no longer apply to the implementation (Finding 20).
- **Runtime pending.** kubectl was not executed inside `alpine/k8s:1.34.11`, because Docker was unavailable. The kubectl version was not checked with `kubectl version --client`. The hook has not been re-run on the cluster. The hook is removed (Finding 20), so this test is no longer required for the implementation.
- **Status (2026-11-06).** The cleanup image is not used. The Architect agreed to remove the cleanup hook container (Finding 20). The earlier request for Architect acknowledgement of this image's risk is withdrawn, because the image will not be deployed. The root-user fact recorded above is kept as historical evidence.

### Finding 11: AI key and frontend wiring. Rendered and source read.

**Backend.** A `backend.env` entry named `OPENAI_API_KEY` with the chart's `secretKeyRef` form (`secretName: sre-keep-ai-env`, `secretKey: fireworks.key`) renders as `valueFrom.secretKeyRef`. The Kubernetes-style `valueFrom:` block renders `value: "<nil>"`, so only the chart's own form works (test render). Loading the Secret through `envFromSecrets` would expose each key as a variable named after the key. `fireworks.key` is not a valid variable name. Kubernetes skips invalid names with an event; that is Kubernetes behaviour, not run here. This is the reason for AD-016.

**Frontend source.** Read at Keep tag `v0.54.3` (commit `118b2dc0c7a45f8a22b6317b983cdba6f5b54b5e`):
- `keep-ui/app/api/copilotkit/route.ts` is a route handler. It builds `new OpenAI({ organization: process.env.OPEN_AI_ORGANIZATION_ID, apiKey: process.env.OPEN_AI_API_KEY })` and passes `model: process.env.OPENAI_MODEL_NAME`. So the frontend needs `OPEN_AI_API_KEY` specifically. `OPENAI_API_KEY` alone would not reach this route.
- `keep-ui/shared/lib/server/getConfig.ts` runs on the server and returns only `OPEN_AI_API_KEY_SET: !!process.env.OPEN_AI_API_KEY || !!process.env.OPENAI_API_KEY`.
- Client components (`incident-overview.tsx`, `alert-actions.tsx`, `create-or-update-preset-form.tsx`, `PostHogPageView.tsx`) read only that boolean.
- A code search at `v0.54.3` found no `NEXT_PUBLIC_OPEN*` variable.
- **Conclusion.** The key is needed server-side only, and browser code never receives its value. Scope: a code search plus reads of the files above. This is not a full audit of every file.

**Chart.** Frontend env (`templates/frontend.yaml:67-76`) renders only `value:` entries, so the `secretKeyRef` form does not work for the frontend. `envFromSecrets` loads keys as variable names, so the frontend needs a Secret whose key is literally `OPEN_AI_API_KEY`. Rendered: `frontend.envFromSecrets` with `sre-keep-ai-frontend` renders a `secretRef` (`optional: false`).

**Proposed configuration (developer, 2026-11-06; requires Architect acceptance).** Secret `sre-keep-ai-frontend`, key `OPEN_AI_API_KEY`, populated by the install script from the same local Fireworks key file (`fireworks.key`) used to create `sre-keep-ai-env`, and loaded through the chart's `frontend.envFromSecrets` mechanism (`templates/frontend.yaml:91`). This is the copy pattern AD-008 already uses for Alertmanager. Both Secrets must be rotated together. No credential value is written to a tracked file, displayed or logged. The alternative, if the Architect does not accept this configuration, is no key on the frontend, which makes the page's AI features report disabled. Runtime behaviour is not yet tested.

**Shared settings.** `OPENAI_MODEL_NAME` is read by both the backend and the frontend route (Finding 12). `OPENAI_BASE_URL` is read by the OpenAI SDK. The route does not pass a base URL, so the SDK falls back to the environment (Finding 16). Both are **runtime pending**. Rendered: `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME` appear on the backend, and `OPENAI_MODEL_NAME` on the frontend. The frontend's `OPENAI_BASE_URL` is not yet in the values. Finding 16 shows the route needs it, so the plan must add it to the frontend env.

**Why the backend Fireworks Secret needs the exception to AD-008.** The backend chart's explicit `secretKeyRef` form supports the key `fireworks.key` (rendered, see the `backend.env` render above). The `envFromSecrets` mechanism loads each key as an environment variable named after the key, and a key containing a period cannot be exposed as a valid environment variable name. So the backend exception is needed. It is specific to the Fireworks Secret wiring and is recorded as a proposed exception in AD-016. The frontend Secret uses `envFromSecrets` with the key `OPEN_AI_API_KEY`, which is a valid variable name, so it does not need the exception.

### Finding 12: Fireworks model, base URL and token limit. Prior evidence, not re-run.

- **Model `accounts/fireworks/models/glm-5p3-flash`.** Verified by a live smoke test in October 2026, recorded in `_bmad-output/planning-artifacts/research/technical-keep-keephq-helm-on-kubernetes-for-sre-s-2026-10-23/tryout/keep-tryout-findings.md` (section "Fireworks smoke test"). Plain chat, `json_schema` output and tool calling all returned HTTP 200. The model page is cited there too. No key was read or used in this step.
- **Thinking-only.** With `max_tokens` 200, the same test returned empty content. `reasoning_effort: none` was rejected with HTTP 400. Keep's LiteLLM provider sends `max_tokens` with a default of 1024. The token limit used by the backend's OpenAI path is not checked. **Runtime pending.**
- **Base URL `https://api.fireworks.ai/inference/v1`.** From line 27 of the BMAD research document (`_bmad-output/planning-artifacts/research/technical-keep-keephq-helm-on-kubernetes-for-sre-s-2026-10-23/research.md`). The SDK reads `OPENAI_BASE_URL` (BMAD research, citations 7 and 8). Fireworks' docs name `OPENAI_API_BASE`, which the pinned SDKs do not read. Use `OPENAI_BASE_URL`. **Runtime pending.**

### Finding 13: MySQL digest. Registry and Rendered.

- `mysql:8.4.13` index digest `sha256:a81d043930e51745522bd5c430961cf8286f0a23f0a9a2a6e0108f7ea71b0902`.
- Rendered: `image: "mysql:8.4.13@sha256:a81d043930e51745522bd5c430961cf8286f0a23f0a9a2a6e0108f7ea71b0902"` (`templates/db.yaml:51`), from `database.mysql.image.tag`.
- Findings 6 and 7 ran `mysql:8.4.13` by tag on AKS: migrations completed and the root password file was honoured. **The digest form has not been run on the cluster.**

### Finding 14: database Secret wiring. Rendered.

- `backend.databaseConnectionStringFromSecret` with `sre-keep-db` and `DATABASE_CONNECTION_STRING` renders `valueFrom.secretKeyRef` with those names.
- `database.extraVolumes` with an `items` list containing only `mysql-root-password` mounts that one key at `/run/db-secret/mysql-root-password`. The rendered volume shows `items` and no other key.
- `database.mysql.env` sets `MYSQL_ROOT_PASSWORD_FILE=/run/db-secret/mysql-root-password`.
- Without `items`, the mount would include the whole Secret, including the connection string, which contains the root password.
- The password is generated by `openssl rand -hex 24` in the install step (AD-008). That step has not run here. **Runtime pending.**

### Finding 15: ServiceAccount separation for the cleanup hook and Keep pods. Rendered and source read.

**Chart structure.** Chart 0.1.97 has one ServiceAccount name for the whole release. The helper `keep.serviceAccountName` (`templates/_helpers.tpl:60-66`) is the only source, and every workload calls it: backend (`templates/backend.yaml:48`), database (`db.yaml:43`), frontend (`frontend.yaml:41`), websocket (`websocket-server.yaml:33`), the cleanup hook (`delete-secret-job.yaml:14`), and the MySQL cleanup cronjob (`db-cleanup-cronjob.yaml:22`, off by default). `grep serviceAccount` over the templates and `values.yaml` finds only `create`, `annotations` and `name`. The chart has no per-component ServiceAccount value.

**Role and binding.** `templates/role-secret-manager.yaml` grants `create`, `delete`, `get`, `list` and `patch` on Secrets in the namespace. `templates/role-binding-secret-manager.yaml` binds it to the shared ServiceAccount. Neither file, nor the cleanup hook, has an `if` gate, so both render in every configuration.

**Rendered configurations** (dummy values, `helm template keep keephq/keep --version 0.1.97 -n keep`):

| Configuration | Pods and hook use | RoleBinding subject | Result |
|---|---|---|---|
| Default (`serviceAccount.create: true`, name empty) | `keep` (5 of 5 workloads) | `keep` | One shared identity with Secret rights. |
| `serviceAccount.create: true`, `name: keep-app` | `keep-app` (5 of 5) | `keep-app` | Still one shared identity. The name changes, the sharing does not. |
| `serviceAccount.create: false`, name empty | `default` (5 of 5) | the namespace's `default` ServiceAccount | Gives Secret rights to `default`, which any pod without its own ServiceAccount also uses. Must not be used. |

**Why Secret rights cannot be removed from the backend.** The chart sets `SECRET_MANAGER_TYPE` to `k8s` on the backend (`values.yaml` env block; rendered `value: "k8s"`). Keep at `v0.54.3` uses the Kubernetes secret manager (`keep/secretmanager/kubernetessecretmanager.py`), which calls `create_namespaced_secret`, `patch_namespaced_secret`, `read_namespaced_secret` and `delete_namespaced_secret` in the namespace named by `K8S_NAMESPACE`. The factory (`keep/secretmanager/secretmanagerfactory.py`) defaults to FILE only when the variable is unset, and the chart sets it. So the backend needs read, create, patch and delete on Secrets. The calls found do not include `list`.

**Automounting.** The rendered pods do not set `automountServiceAccountToken`, so Kubernetes mounts the token by default. The chart has no value for this (no `automount` in its templates).

**Helm `--no-hooks`.** `helm uninstall --help` (Helm v4.2.4) lists `--no-hooks`, which skips the cleanup hook. The chart renders no Secret in the default configuration, so it leaves nothing of its own behind. Secrets the backend writes through the Kubernetes secret manager would survive a `--no-hooks` uninstall unless our own uninstall step removes them. Not tested.

**Conclusion.** No chart-supported setting gives the cleanup hook, or the frontend, database or websocket pods, an identity without Secret rights. The shared identity with Secret rights is how chart 0.1.97 works. Separating it requires a change outside the chart values: a post-render step that gives those pods their own ServiceAccounts with token automount off, and replaces the shared Role with separate Roles: backend (`create`, `get`, `patch`, `delete` on Secrets) and, historically, cleanup hook (`get`, `list`, `delete` on Secrets; the hook is no longer part of the intended implementation). Frontend, websocket and database would have no Secret permissions, subject to runtime validation. That is a deliberate deviation for the Architect to decide (AD-016, section "Open for Architect"). No post-render recommendation is made until the pod identities, token access and hook permissions are validated. The `list` verb question is in Finding 17. **Decision (developer, 2026-11-06):** the chart's shared ServiceAccount is retained for the initial implementation, subject to Architect review (see Finding 18). The cleanup hook is removed by the Architect's decision (Finding 20), so the hook's permissions no longer apply to the implementation. **Runtime pending:** none of this was run on the cluster.

### Finding 16: frontend AI route, OpenAI SDK base URL and model. Source read and rendered.

- **Version.** `keep-ui/package-lock.json` at `v0.54.3` resolves `openai` to 4.86.2 (`resolved: https://registry.npmjs.org/openai/-/openai-4.86.2.tgz`). The `package.json` range is `^4.86.2`.
- **SDK behaviour.** The OpenAI SDK source at tag `v4.86.2` (`src/index.ts`, lines 134, 220 and 221) reads `baseURL` from `OPENAI_BASE_URL` and `apiKey` from `OPENAI_API_KEY` when those options are not passed.
- **Route.** `keep-ui/app/api/copilotkit/route.ts` calls `new OpenAI({ organization, apiKey })` with no `baseURL`. So the SDK reads `OPENAI_BASE_URL` from the environment. If it is unset, the SDK targets the default OpenAI endpoint, not Fireworks. **The frontend therefore needs `OPENAI_BASE_URL=https://api.fireworks.ai/inference/v1` when the frontend AI key is enabled.**
- **Model.** The route reads `process.env.OPENAI_MODEL_NAME` and passes it as `model` to `OpenAIAdapter` when it is set. **The frontend therefore needs `OPENAI_MODEL_NAME` set** to the verified identifier (Finding 12).
- **Rendered.** The frontend env in the final-wiring render carries `OPENAI_MODEL_NAME` (Finding 11). The frontend `OPENAI_BASE_URL` entry is not yet in the values. It must be added with the frontend key.
- **Browser exposure.** Neither variable has the `NEXT_PUBLIC_` prefix, and a code search at `v0.54.3` found no `NEXT_PUBLIC_OPEN*` variable, so these values are not placed in browser code.
- **Runtime pending.** The route has not been called against Fireworks. The SDK behaviour is verified from source at the pinned version, not by a request.

### Finding 17: can the `list` verb be removed from the Role? Rendered and source read. Not run.

**Superseded in part (2026-11-06, Finding 20).** The cleanup hook is removed, so the hook's `list` requirement no longer applies to the implementation. The chart's Role still grants `list`, and the chart offers no setting to remove it. The backend source does not appear to need `list` (source read, not run). The rest of this finding is kept as historical analysis.

- **The Role.** `templates/role-secret-manager.yaml` grants `create`, `delete`, `get`, `list` and `patch` on Secrets.
- **Backend (source read, Keep `v0.54.3`).** `keep/secretmanager/kubernetessecretmanager.py` calls `create_namespaced_secret` (line 74), `patch_namespaced_secret` (line 83), `read_namespaced_secret` (line 108) and `delete_namespaced_secret` (line 129). The file has no Secret list call. The Kubernetes and Flux providers make no Secret calls. Their list calls cover pods, nodes, events, deployments and custom objects, which this Role does not grant.
- **Cleanup hook (rendered).** `templates/delete-secret-job.yaml:23` runs `secrets=$(kubectl get secrets -n <namespace> -o name | grep '^secret/keep-');`. Under standard Kubernetes RBAC, a collection `get` is a `list` request. This is not run here.
- **Silent failure.** The hook's script has no `set -e` (`grep -c 'set -e'` returns 0). If the list is refused, `secrets` is empty and the `if [ -n "$secrets" ]` branch (line 24) prints "No matching secrets found to delete." Source reading indicates that the job would then exit successfully and delete nothing. Not run.
- **Conclusion.** The backend source does not appear to require `list`. The cleanup hook required it before its removal (historical; see the superseded note above). The chart exposes no values setting for the Role, so a shared Role without `list` cannot be produced through values. A post-render customization could give the backend and the hook separate Roles (AD-016, option 2). That has not been tested. Removing `list` from one shared Role is therefore not the only possible approach, and no approach is chosen. The decision stays open in AD-016. **Runtime pending:** run the existing hook in a throwaway namespace with a ServiceAccount lacking `list`, then check whether `keep-*` Secrets survive and whether the job reports success.

### Finding 18: residual cleanup-hook and backend Secret access. Rendered, source read, and RBAC documentation. Not run.

**Scope of the grants.** The Role `secret-manager-role` has no `resourceNames`, so `create`, `delete`, `get`, `list` and `patch` apply to every Secret in the namespace, including `sre-keep-db` and `sre-keep-ai-env`. The hook's ServiceAccount, `keep`, is the one bound to it (Finding 15). Under the proposed separation (AD-016 option 2), the hook's Role would be `get`, `list` and `delete` with the same namespace-wide scope. Update 2026-11-06: the hook is removed (Finding 20), so that requirement no longer applies. The backend's `create`, `get`, `patch` and `delete` remain namespace-wide.

**Decision (developer, 2026-11-06; not an Architect approval).** The chart's existing shared ServiceAccount is retained for the initial implementation, subject to Architect review. Post-render separation is not implemented, and no separate Roles or RoleBindings are introduced at this stage. The backend's Secret permissions are kept as the chart defines them: `create`, `get`, `patch` and `delete`. The cleanup hook's `get`, `list` and `delete` permissions are no longer required by the intended implementation, because the Architect agreed to remove the hook (Finding 20). Retaining the shared ServiceAccount does not mitigate the residual namespace-wide Secret risk. The Architect's explicit acknowledgement of that risk is outstanding.

**Can RBAC restrict the hook to `keep-*` names? No.** Kubernetes RBAC documentation (read through context7, library `/websites/kubernetes_io`, page `reference/access-authn-authz/rbac`; not re-fetched from the live site):
- `resourceNames` cannot restrict `deletecollection` or a top-level `create`.
- `list` or `watch` can be restricted only when the client includes a `metadata.name` field selector that matches a named resource. The documentation's example is `kubectl get configmaps --field-selector=metadata.name=my-configmap`.
- The documented examples use exact names. No prefix or wildcard form appears.

The hook's targets are Secrets that Keep's backend writes with names it supplies at run time (source read: `keep/secretmanager/kubernetessecretmanager.py`, `write_secret(secret_name)`). These names are not known at install time, so an exact-name Role cannot list them. A label or prefix selector would need `list` or `deletecollection`, and neither can be narrowed by name. So RBAC alone cannot restrict the hook to `keep-*`.

**Redesign options considered.**
- *Name-based deletion from a list gathered before uninstall.* The names still need a namespace-wide `list` or some other source. It does not remove the broad grant.
- *Operator-run cleanup outside the cluster.* Run `helm uninstall --no-hooks`, then delete the `keep-*` Secrets with the operator's own kubeconfig. This removes the hook's in-cluster Secret grant. It moves the permission to the operator, whose access to the namespace is already broad. Chosen as the operational approach on 2026-11-06 (Finding 20); the procedure has not been run.
- *Keep the chart's hook and accept the risk.* This was the chart's behaviour before the 2026-11-06 decision to remove the hook (Finding 20).

**Residual risk for Architect review.** The backend requires `create`, `get`, `patch` and `delete` permissions on namespace Secrets for its Kubernetes Secret manager. The cleanup hook's `get`, `list` and `delete` permissions are no longer required by the intended implementation because the Architect agreed to remove the hook (Finding 20). These backend permissions are namespace-wide, not restricted to Secrets beginning with `keep-`. A compromised Keep pod sharing this ServiceAccount could potentially access or modify Secrets belonging to other components, including `sre-keep-db` and `sre-keep-ai-env`. A compromised backend could potentially read (`get`), create, patch or delete them. Any identity that can create pods in the namespace can use these ServiceAccounts. Separation reduces which pods hold the grants, but it does not remove the namespace-wide backend permissions. Retaining the shared ServiceAccount does not mitigate this risk. The Architect's explicit acknowledgement is requested and is outstanding. **Runtime pending:** none of this has been tested.

### Finding 19: optional MySQL cleanup CronJob. Rendered default and template read. Not run.

- **Gating.** `templates/db-cleanup-cronjob.yaml` renders only when `database.enabled` and `database.cleanup.enabled` are both true (`values.yaml:419-420`, default `enabled: false`). The default render and the final-wiring render both contain no `kind: CronJob` (`grep -c` returns 0).
- **ServiceAccount and API use.** It uses `keep.serviceAccountName`, the same shared ServiceAccount (`db-cleanup-cronjob.yaml:22`). The template contains no `kubectl` call, so it does not need the token. Under separation it could run with token automount off.
- **Authentication.** The job runs `mysql -h keep-database -u root --skip-column-names` with no `-p` option (`db-cleanup-cronjob.yaml:34`). It has no password source. With AD-013's `MYSQL_ROOT_PASSWORD_FILE`, this login is expected to fail. This is a source-read expectation, not a runtime result.
- **Decision.** The job is not enabled. Enabling it needs a credential change first, which is not in the current decisions.

### Finding 20: Architect decision to remove the cleanup hook; manual Secret cleanup. Decision record. Not run.

**Decision.** The Architect has explicitly agreed (recorded 2026-11-06) to remove the Kubernetes cleanup hook container that used `alpine/k8s:1.34.11`. Consequences:
- The cleanup hook must not execute. The chart still renders it, and the documented uninstall command `helm uninstall keep -n <namespace> --no-hooks` prevents its execution. No third-party cleanup image runs during the documented uninstall.
- `helm uninstall` with `--no-hooks` does not automatically delete the dynamically created Keep Secrets. A plain `helm uninstall` runs the hook, which deletes them.
- Secret cleanup becomes an explicit administrator-operated manual task after uninstall.
- The image evaluation in Finding 10 is kept as history. The image is not selected.
- The earlier request for Architect acknowledgement of the cleanup image risk is withdrawn, because the image will not be used.

**Uninstall mechanism (Architect decision, recorded 2026-11-06; decision on the mechanism only).** The documented uninstall command is `helm uninstall keep -n <namespace> --no-hooks`. The facts behind it:
- **The hook remains in chart version 0.1.97.** The chart is unchanged. `templates/delete-secret-job.yaml` still renders the pre-delete Job, and `values.yaml` still has no switch for it (`deleteSecretJob` sets only the image). The upstream chart is not forked or modified, and no Helm post-renderer is introduced.
- **`--no-hooks` suppresses hook execution.** The Helm documentation describes the flag as "prevent hooks from running during uninstallation" (Helm `helm uninstall` CLI reference). The local CLI help (Helm v4.2.4) lists it.
- **Helm 3 and Helm 4 both support the flag**, per the documentation. The project installs Helm 3 (`infra/scripts/dev/install-deps.sh`, `get-helm-3`). The local binary is Helm 4.2.4. The Helm 3 behaviour rests on the documentation and was not run locally.
- **Not tested against AKS.** No uninstall has been run against any cluster. Expected behaviour (from the Helm hook documentation, not run): a pre-delete hook creates its Job at delete time, so with `--no-hooks` the Job is not created and the `alpine/k8s` image is not pulled.
- **Procedural risk.** A plain `helm uninstall keep -n <namespace>` runs the hook. The chart's script deletes every Secret in the namespace whose name begins with `keep-`, including Keep-generated Secrets that the manual procedure exists to review. Nothing in the chart or the tooling prevents this. The control is procedural: the documented command, the scripts and the runbook must always pass the flag. The hazard is not technical.
- **Why not a post-renderer.** The Helm 3 documentation states that hooks were never sent to post-renderers under Helm 3. A post-renderer therefore could not remove this hook under the project's Helm 3 install, and it is not introduced.
- **Where the command must be enforced or documented (not yet implemented).** (1) The planned Keep install and teardown script under `infra/azure/keep/` (AD-011 layout). (2) A future make target for the Keep uninstall; no such target exists yet. The existing `cleanup` and `cleanup-cluster` targets delete the AKS cluster itself and do not run `helm uninstall`. (3) The operational runbook, which does not exist yet. (4) AD-011's "Why" bullet, which says that after `helm uninstall keep` and `make setup-keep`, "everything is back with no manual step", now conflicts with manual cleanup and needs revising in a later pass.

**RBAC reassessment.**
- Backend, still required: `create`, `get`, `patch` and `delete` on namespace Secrets (source read; Finding 15). These remain, and this decision does not change them.
- Cleanup hook, no longer required: `get`, `list` and `delete` (Finding 17).
- Still granted by the chart Role: `list`. The backend source does not appear to need it (source read, not run). The chart offers no values setting to remove it (Finding 15), so removing it is not part of this decision.
- Removing the hook does not remove the backend's namespace-wide Secret permissions, and it does not eliminate the residual risk (Finding 18).

**Documented uninstall command.** Run `helm uninstall keep -n <namespace> --no-hooks`, not a plain `helm uninstall`. Step 1 below confirms the result.

**Manual cleanup procedure.** This is administrator-operated and is never run automatically. Replace `<namespace>` with the target namespace. Do not run any deletion command until steps 1 to 3 are complete for that namespace.

1. **Confirm the uninstall.** Confirm the cluster context with `kubectl config current-context`. Then confirm Keep is gone with `helm status keep -n <namespace>`, which should report that the release is not found.
2. **Inspect the names.** List Secrets whose names begin with `keep-`. `-o name` prints names only, not values:
   ```bash
   kubectl get secrets -n <namespace> -o name | grep '^secret/keep-'
   ```
   Our own Secrets (`sre-keep-db`, `sre-keep-ai-env`, `sre-keep-ai-frontend`) begin with `sre-keep-`, so they are not matched.
3. **Review before deleting.** The administrator confirms each matching name is a Keep-generated Secret, and not one of our own or another component's. If the list is empty, stop: nothing needs deleting. **Warning:** verify the namespace and every Secret name before deleting. Deletion cannot be undone.
4. **Delete only the reviewed names.** The pipeline below deletes every name it matches, so run it only after step 3 is complete for the same namespace:
   ```bash
   kubectl get secrets -n <namespace> -o name \
     | grep '^secret/keep-' \
     | xargs -r kubectl delete -n <namespace>
   ```
   `xargs -r` is a GNU option and may not exist on macOS. On macOS, delete each reviewed name explicitly: `kubectl delete secret <reviewed-name> -n <namespace>`. To preview without deleting, add `--dry-run=server` to the `kubectl delete` command.
5. **Verify.** Rerun step 2. It should print nothing. Then confirm our Secrets remain: `kubectl get secret sre-keep-db sre-keep-ai-env -n <namespace> -o name`.

**Do not expose values.** Do not use `-o yaml`, `-o json`, `describe` or `-o jsonpath` on these Secrets. Those output forms show data fields.

**Naming basis for the `keep-*` prefix (source review, Keep v0.54.3; read-only; 2026-11-06).** The prefix is justified here by the Secret names that the code creates. It is not justified by the old hook's matching rule (Finding 6 is historical evidence only).

*Chart-created Secrets.* The chart creates these only when the named value is enabled. In the intended install values none is enabled, and the final render contains no Secret.
- `keep-backend-env-secret`, created by `templates/backend-configs.yaml` when `backend.envRenderSecret` is set.
- `keep-providers`, created by `templates/backend-provision.yaml` when `backend.provision.providers` is set.
- `keep-frontend-env-secret`, created by `templates/frontend-configs.yaml` when `frontend.envRenderSecret` is set.

These names are built from `keep.fullname`. They assume the Helm release is named `keep` (and no `fullnameOverride`). A different release name changes the prefix, and the cleanup filter would then need to change with it.

*Backend-created Secrets.* The backend writes these through the Kubernetes secret manager, which replaces `_` with `-` and lowercases names (`keep/secretmanager/kubernetessecretmanager.py`, line 66). The single-tenant ID is the literal `keep` (`keep/api/core/dependencies.py`, line 14), so names built from `tenant_id` begin with `keep-`. The call sites are:
- `keep-<unique_api_key_id>`: API key Secrets, written as `{tenant_id}-{unique_api_key_id}` (`keep/api/utils/tenant_utils.py`, lines 86 and 135).
- `keep-<api_key_name>`: default API key Secrets, written as `{tenant_id}-{api_key_name}` (`keep/api/core/db_on_start.py`, line 146).
- `keep-smtp`: SMTP settings, written as `{tenant_id}_smtp`, which the manager stores as `keep-smtp` (`keep/api/routes/settings.py`, line 97).
- `keep-<provider_type>-<id>`: provider configurations, written as `{tenant_id}_{provider_type}_{id}` (`keep/providers/providers_service.py`, lines 191 and 292 to 293, and 466; `keep/api/routes/providers.py`, line 581; `keep/providers/providers_factory.py`, line 139). The `configuration_key` stored with a provider is the same name.
- `keep-<workflow_id>-secrets`: workflow secrets, built as `{tenant_id}_{workflow_id}_secrets` (`keep/api/routes/workflows.py`, lines 1231, 1243 and 1311).

Each name above matches the cleanup filter `^secret/keep-` in single-tenant mode.

*Exceptions.* Two cases fall outside the intended targets:
- **Temporary `none-*` Secret.** `keep/providers/providers_service.py` `prepare_provider` (lines 94 to 144) sets `tenant_id = None` and writes a Secret named `None_<type>_<uuid>`, which the manager stores as `none-<type>-<uuid>`. The same function deletes it immediately. If that delete fails, the error is logged and the Secret remains. Such a Secret does not match `keep-*` and would not be listed by the procedure. The only caller found is in the same file.
- **Alertmanager Secret in the `monitoring` namespace.** AD-008 names the Secret `alertmanager-keep-auth`. It lives in the `monitoring` namespace, outside the Keep namespace, so the procedure (which is namespace-scoped) does not cover it. This name comes from AD-008, not from the Keep source.

*Intended cleanup targets versus exceptions.* The intended targets are the Secrets in the Keep namespace whose names begin with `keep-` and that an administrator has reviewed. The exceptions above are not targets. The `none-*` leftover must be handled separately if it is ever found. The Alertmanager Secret must be managed in its own namespace.

*Limitations.* The review covered the `write_secret` and `create_namespaced_secret` call sites found by code search at v0.54.3, and the files listed above. Indirect callers, or other secret-writing paths the search did not reach, may exist and were not enumerated. This review does not prove that every dynamically generated Secret is covered. A throwaway-namespace test that creates each kind of Secret and runs the procedure remains outstanding.

*Operational rules for the procedure.* Keep administrator review before deletion (steps 2 and 3). Never print Secret values (`-o name` only). Before deleting, check the reviewed list for any `keep-*` Secret that is not one of the names above, because that would show a write path this review did not cover.

**Runtime pending.** The procedure has not been run, and a throwaway-namespace test is outstanding. No deletion command was executed in preparing this documentation.

### Evidence summary

| Claim | Status |
|---|---|
| The busybox override replaces the unpinned init container (Finding 9) | Rendered. Runtime pending. |
| `alpine/k8s:1.34.11` digest exists and has the required utilities (Finding 10) | Registry and layer listing. Not executed. Historical: the image is not used (Finding 20). |
| The removed hook's ServiceAccount had Secret create, patch, delete, get and list (Finding 10) | Rendered (templates). Not run. Historical (Finding 20). |
| The Architect agreed to remove the cleanup hook container (Finding 20) | Recorded decision, 2026-11-06. Not implemented. |
| `helm uninstall --no-hooks` suppresses pre-delete hook execution (Finding 20) | Helm documentation and local CLI help. Helm 3 rests on documentation. Not run against AKS. |
| The chart renders the pre-delete hook unconditionally; the documented uninstall command `--no-hooks` prevents its execution (Finding 20) | Rendered template and values read; hook present in the final override render. The flag is documented and in the local CLI help. Not run against AKS. |
| The manual cleanup procedure lists names before deletion and prints no values (Finding 20) | Documentation check only. Procedure not run. |
| Every Keep-generated Secret begins with `keep-` (Finding 20) | Assumption. Not verified for every name the backend writes. |
| The backend's `OPENAI_API_KEY` secret reference renders (Finding 11) | Rendered. Runtime pending. |
| The frontend key is server-side only (Finding 11) | Source read at v0.54.3. Browser behaviour not tested. |
| The frontend `secretKeyRef` form is unsupported (Finding 11) | Rendered (template). |
| The database Secret wiring and the `items` restriction render (Finding 14) | Rendered. Runtime pending. |
| MySQL 8.4.13 digest (Finding 13) | Registry and rendered. Digest form not run on the cluster. |
| The Fireworks model identifier (Finding 12) | October smoke test (prior evidence). Not re-run. |
| The frontend route reads `OPENAI_BASE_URL` and `OPENAI_MODEL_NAME` from the environment (Finding 16) | Source read at the pinned SDK version and rendered. Not called. Runtime pending. |
| `OPENAI_BASE_URL` reaches Fireworks end to end (Finding 12, 16) | Not verified. Runtime pending. |
| A separate ServiceAccount for the cleanup hook or the non-backend pods (Finding 15) | Not supported by chart 0.1.97 values. Rendered. Post-render would be needed, not tested. |
| Secret rights cannot be removed from the backend (Finding 15) | Source read (`SECRET_MANAGER_TYPE: k8s`). Not run. |
| The backend's Secret code does not appear to call list (Finding 17) | Source read at v0.54.3. Not run. |
| The existing (now removed) cleanup hook needed `list`, and a shared Role without it would likely have made the hook fail without a failed job (Finding 17; historical, Finding 20) | Rendered template, standard Kubernetes RBAC behaviour, and source reading. Not run. |
| Separate Roles through post-render avoid the shared-Role conflict (Finding 15, 17; AD-016 option 2) | Design only. Not tested. |
| RBAC cannot restrict the backend's Secret grants to `keep-*` names (Finding 18) | RBAC documentation (context7) and source read. Not run. |
| The backend keeps namespace-wide Secret access under any design considered (Finding 18) | Rendered Role and source read. Not run. |
| The optional MySQL cleanup CronJob is off by default and absent from the install render (Finding 19) | Rendered default and final-wiring render. |
| The MySQL cleanup CronJob's root login would fail under the AD-013 root password (Finding 19) | Source read. Not run. |
| The developer selected retaining the chart's shared ServiceAccount for the initial implementation (Finding 18) | Developer decision, 2026-11-06. Not Architect-approved. Not implemented. |
| Retaining the shared ServiceAccount does not mitigate the namespace-wide Secret risk (Finding 18) | Analysis from the rendered Role and source read. Architect acknowledgement outstanding. Not run. |
| The backend Fireworks Secret reference (`sre-keep-ai-env`, key `fireworks.key`, env `OPENAI_API_KEY`) renders (Finding 11) | Rendered (test render). Runtime pending. |
| The frontend Fireworks Secret (`sre-keep-ai-frontend`, key `OPEN_AI_API_KEY`) renders through `frontend.envFromSecrets` (Finding 11) | Rendered (test render). Runtime pending. |
| The thinking-only token limit is adequate for Keep's AI calls (Finding 12) | Not verified. Runtime pending. |
| The `sre-keep-ai-env` Secret survives `helm uninstall` (issue live check) | Not tested. Runtime pending. |
