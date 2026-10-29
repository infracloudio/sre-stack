# Research: Install Keep on AKS (story #123)

Run 2026-10-29 against AKS `sre-stack-452138` (resource group
`rijo-john-improving-com-aks-452138`, Kubernetes 1.34.11), started from the
stopped state with `az aks start`. Keep was not installed before this research.

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
false). The namespace was deleted afterwards. Not yet proven: check 3 reinstall
with the same generated password, and check 4 (`MYSQL_ROOT_PASSWORD_FILE`).

## Decision on Finding 5 (developer, 2026-10-29)

Narrow the promise: the busybox init image stays unpinned in the chart. The
spec says every image the values file can set is pinned, and names busybox as
the one exception the chart does not allow us to set.

## Finding 7: live checks 3 and 4 passed

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
