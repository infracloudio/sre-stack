---
id: SPEC-keep-alert-management
companions:
  - glossary.md
  - delivery-slices.md
  - ../../planning-artifacts/research/technical-keep-keephq-helm-on-kubernetes-for-sre-s-2026-10-23/research.md
  - ../../planning-artifacts/research/technical-keep-keephq-helm-on-kubernetes-for-sre-s-2026-10-23/tryout/keep-tryout-findings.md
sources:
  - https://github.com/infracloudio/sre-stack/issues/91
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete contract. Terms are explained in `glossary.md`. Section 5 of `research.md` records a live end-to-end run on AKS (2026-10-23): what it marks verified is fact here; what it marks failed or open stays open. Starting files from that run sit in `tryout/` next to `research.md` (`keep-values.yaml`, `prometheus-stack-keep-override.yaml`, `robot-shop-keep-tryout-rules.yaml`, `notify-slack-with-context.yaml`, `fireworks-smoke.sh`).

# Keep alert management for sre-stack (epic: issue #91)

## Why

sre-stack shows how faults are detected, but nothing happens after an alert fires. Robot-shop has no alert rules, Alertmanager is turned off, and its Slack setting is a broken placeholder. This epic adds the next step of the demo. A fault produces a burst of alerts, Keep groups them into one incident, a language model writes a summary, the summary goes to Slack, and the incident closes when the fault clears. The live try-out showed every part of this works.

## Capabilities

- **CAP-1**
  - **intent:** An operator installs Keep with one make target, `setup-keep`, which is also part of the AKS setup flow.
  - **success:** On AKS, `make setup-keep` brings the backend, frontend, websocket server and MySQL pods to Running on the `workload=o11y` pool, with the database volume on gp2 and telemetry off. Running it again changes nothing. Run on its own, it refuses with a clear message when a required secret is missing. Inside `make setup-aks`, it is skipped with a clear message when the Keep secrets are missing, and the rest of AKS setup carries on. `make setup-local` still works.
- **CAP-2**
  - **intent:** Robot-shop has Prometheus alert rules for OOM kills, container restarts, unavailable replicas, slow requests and a high share of 5xx (server error) responses.
  - **success:** During the cart OOM fault (`make aks-cart-oom-start`, load generator running), the OOM kill, restart, unavailable-replica and 5xx alerts fire. The slow-request alert fires only if latency crosses the tuned threshold. Each alert has a severity Keep recognises and `namespace` and `service` labels. With the load generator running and no fault, none fire for 30 minutes. The tuned payment latency threshold and the reason for it are recorded.
- **CAP-3**
  - **intent:** Alertmanager sends firing and resolved alerts to Keep, and to nothing else.
  - **success:** A test alert reaches Keep within one minute and shows as resolved after it clears. The Alertmanager config has no Slack receiver and no `P1 -> slack` route. Alertmanager is on for AKS only. The k3d and EKS configs do not change, apart from losing the broken Slack setting.
- **CAP-4**
  - **intent:** Keep groups robot-shop alerts that fire close together into one incident and closes it when they all clear.
  - **success:** One cart OOM fault produces exactly one incident. It resolves on its own after the fault is reverted and its last alert clears.
- **CAP-5**
  - **intent:** The Slack channel gets an AI-written summary when an incident opens, and a second message when it resolves.
  - **success:** Within two minutes of the incident opening, Slack shows a Fireworks summary that names the failing service and what to check first. When the incident resolves, exactly one resolved message appears, not one per incident update.
- **CAP-6**
  - **intent:** An operator signs in to the Keep UI, with live updates, at its own address on the cluster's existing Istio gateway. `make get-service-endpoints` lists the address.
  - **success:** The listed address shows Keep's login page. The default user signs in, and new alerts appear without a refresh, so the websocket works. A request with a made-up API key is rejected. Alertmanager still delivers using the real API key.
- **CAP-7**
  - **intent:** Keep's providers, correlation rule and workflows are files in the repo, applied by the install rather than created by hand.
  - **success:** After `helm uninstall keep` and `make setup-keep`, the Slack provider, Fireworks provider, correlation rule and both workflows exist with no manual API or UI steps. Running the install again creates no duplicate rule. No secret value is in any repo or values file.
- **CAP-8**
  - **intent:** A presenter can run the whole story in one take by following written steps.
  - **success:** The README has an alert management (Keep) section with an architecture diagram, demo steps and screenshots: the incident with grouped alerts, the Slack summary, and a workflow run. Someone new to the repo can follow it on AKS. The cart OOM scenario ends by printing where to watch Keep and Slack.
- **CAP-9** *(later, lower priority)*
  - **intent:** Grafana alerts also reach Keep.
  - **success:** A Grafana alert reaches Keep through a webhook contact point, with a recognised severity.
- **CAP-10** *(later, lower priority)*
  - **intent:** Kubernetes events reach Keep.
  - **success:** The OOM-kill event for the cart pod appears in Keep during the fault.
- **CAP-11** *(later, lower priority)*
  - **intent:** Alerts based on Loki logs reach Keep.
  - **success:** A log-based alert caused by the fault appears in Keep.
- **CAP-12** *(later, lower priority)*
  - **intent:** The cause of the failing "AI Summary" button with this model is found.
  - **success:** A written finding with the cause and either a fix or a decision to leave it. In the try-out the button ran about 40 seconds and saved nothing, and "record root cause" saved empty entries.

## Constraints

- AI uses only Fireworks, model `accounts/fireworks/models/glm-5p3-flash`, called through Keep's `litellm` workflow provider with `api_url` `https://api.fireworks.ai/inference/v1` and `max_tokens` 10000. The model always spends tokens on hidden reasoning first, so a small budget returns nothing. `OPENAI_MODEL_NAME` is set on both backend and frontend.
- Keep's enterprise tier stays off (`EE_ENABLED` unset). Its built-in summary code is not open source.
- Slack only through one incoming webhook bound to one channel. No bot token or Slack app scopes beyond the webhook.
- Alertmanager's only receiver is Keep: `http://keep-backend.keep.svc.cluster.local:8080/alerts/event/prometheus`, basic auth username `api_key`, password read from a mounted Secret through `password_file`, `send_resolved: true`. Because Helm merges maps, `routes: []` has to be set explicitly to drop the old sub-route.
- Alert severity labels use Keep's names: critical, error, high, warning or info. The repo's `P1` would show as info. Rules carry `release: prometheus-stack` so Prometheus picks them up. Metrics come from kube-state-metrics and Beyla (`http_server_request_duration_seconds`). `istio_requests_total` has too few robot-shop series to use.
- Keep's login: `AUTH_TYPE=DB` (uppercase; lowercase caused a redirect loop). `KEEP_DEFAULT_USERNAME`, `KEEP_DEFAULT_PASSWORD` and `KEEP_JWT_SECRET` come from a Secret. Alertmanager uses a real Keep API key, seeded from a Secret with `KEEP_DEFAULT_API_KEYS`, a comma-separated list of `name:role:secret` (`keep/api/core/db_on_start.py:103-125`). `POST /settings/apikey` is the fallback only if the live check fails. The default `NOAUTH` accepts any key as admin, so Keep gets no route through the gateway until the login is on. The try-out never tested this login.
- The UI and websocket get their own address on the existing gateway, never a sub-path: `http://keep.demo.local`, host-matched as AD-005 does for HotROD (AD-010). The published frontend image has no `basePath`, and Next.js fixes `basePath` when the image is built.
- Provider secrets never reach repo or values files. Keep's `KEEP_PROVIDERS_DIRECTORY` loader does no environment-variable substitution (`keep/providers/providers_service.py:609-660`), and the chart's `backend.provision.providers` renders values straight into a Secret. So `setup-keep` builds the `KEEP_PROVIDERS` JSON at install time from `~/.secrets/keep/` into our own Secret, loaded with `backend.envFromSecrets`. The repo keeps only a template with the non-secret fields. Start-up provisioning is on by default (`config.py:20`, AD-011).
- Both workflows are repo files loaded by start-up provisioning; they hold no secrets. The correlation rule is created by a small idempotent script that calls `POST /rules`. Keep's provisioning (`keep/api/config.py:26-44`) covers providers, workflows, dashboards, deduplication and mapping rules, but not correlation rules.
- Keep has no "incident resolved" trigger, only created, updated and deleted. The resolved message triggers on updated, with a condition on the incident's status being resolved.
- Alertmanager is turned on in `infra/azure/chart-values/prometheus-stack.yaml` (AKS only). The broken Slack setting is removed from the shared `monitoring/chart-values/prometheus-values.yaml`.
- Telemetry off: `POSTHOG_DISABLED=true` on backend and frontend, `SENTRY_DISABLED=true` on frontend.
- Our own Secrets are never named `keep-*`. The chart's uninstall hook deletes every Secret with that prefix.
- The Fireworks key, Slack webhook URL, Keep API key, Keep login password and JWT secret (the key that signs login sessions) never appear in the tracked `.env`, in values files or in manifests. They are read from an untracked file or shell variables; the Fireworks key and Slack webhook are supplied by the operator and `setup-keep` stops without them; the rest are generated once (AD-008).
- Chart `keephq/keep` is pinned to 0.1.97 (Keep 0.54.3), with values in a chart-values file. `backend.env` and `frontend.env` are lists, so the values file restates the chart defaults it keeps. The frontend accepts plain values only, so secrets reach it through `envFromSecret`.
- Images the chart leaves unpinned (`mysql:latest`, `busybox`, `bitnami/kubectl:latest`) are pinned through values to the newest exact versions, looked up when the story is built (busybox through our own init container, AD-013).
- Database: the chart's bundled MySQL, with `database.pv.enabled: false` (no hostPath volume) and the PersistentVolumeClaim on `gp2`, with a generated root password (AD-013).
- All Keep pods run on the `workload=o11y` pool and tolerate the o11y and spot taints (AD-003).
- AKS first. `make setup-local` (k3d) and the EKS path keep working.
- Delivery: issue #91 is the epic in a GitHub Project. Each story is a sub-issue sized at 1 to 2 days, with Problem, Outcome, Out of scope and Must keep working (AGENTS.md), and can be demoed on its own. The order is in `delivery-slices.md`.

## Non-goals

- Jira tickets, PagerDuty pages, and automatic remediation (no `kubectl rollout restart` workflow).
- Ollama, OpenAI, Anthropic or any AI provider other than Fireworks. Keep's enterprise tier.
- Single sign-on or user roles in Keep (one default user only).
- PostgreSQL for Keep. The bundled MySQL is used, not Grafana's PostgreSQL.
- Fixing Keep itself. Known limits stay as they are: a resolved incident's `end_time` stays empty, so time-to-resolve may read zero, and the UI labels rule-grouped alerts "Manually".
- Replacing Alertmanager. It stays and forwards to Keep.
- Grafana panel or Tempo trace links in the Slack message. The issue proposed them; this epic's workflow is the summary only.

## Success signal

- On AKS, after `make setup-aks`, a presenter starts the cart OOM fault with the load generator running. Within about two minutes, Keep shows one incident holding the OOM, restart, unavailable-replica, 5xx and slow-request alerts, and Slack shows an accurate Fireworks summary. After `make aks-cart-oom-revert`, the incident closes on its own and Slack gets a resolved message. Nothing is clicked or configured by hand.

## Assumptions

- Keep is installed on AKS only in this epic. k3d and EKS get no Keep install and must not break.
- Hotrod alert rules are not in this epic. Decision 6 names robot-shop only.
- Untracked secrets live in `~/.secrets/keep/`, as in the try-out.
- Until story 6a, Keep runs under `NOAUTH` and is reached only by port-forward. Stories 3 to 5b read the API key from the same untracked file and Secret that story 6a makes real, and 6a proves Alertmanager still delivers with it. (Accepted by review.)
