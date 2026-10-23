---
title: 'technical research: Keep (keephq) on Kubernetes for sre-stack alert management'
type: 'technical'
topic: 'Keep (keephq) on Kubernetes for sre-stack alert management'
decision: 'Is the Keep + Postgres + Fireworks LLM + Alertmanager/Grafana webhooks + Slack design in sre-stack issue #91 buildable as specified'
source: 'native run'
status: draft
preset: 'standard'
validation: 'normal'
created: '2026-10-23'
updated: '2026-10-24'
---

# Technical research: Keep (keephq) on Kubernetes for sre-stack alert management

**Decision this research serves:** is the design in sre-stack issue #91 buildable as written: Keep via Helm, Postgres, Fireworks "GLM-5.3 Flash" as the AI backend, Alertmanager and Grafana webhooks in, Slack out (channel notifications only).

All sources accessed 2026-10-23. "Verified in code" means the lead read the file in a shallow clone of `keephq/keep` at commit `e5cd869` (2026-10-22) or `keephq/helm-charts` at `734018e` (2026-09-09), kept under `imports/`. Other claims come from subagent digests in `digests/` (web fetch summaries, so second-hand).

## Executive summary

> **Update after the manual try-out (same day, section 5).** The design was run end to end on the AKS cluster: an OOM fault produced 6 alerts, Keep grouped them into one incident, a workflow got a Fireworks summary into Slack in 8 seconds, and the incident closed itself when the fault cleared. All four open questions are answered (below). Two claims in this summary were wrong and are corrected in place: item 1 (the workflow-side AI path) and item 5 (the enterprise tier). New blockers the issue did not know about: Alertmanager is off in this stack and no robot-shop alert rules exist, so both must be built.

**Yes, buildable, with five things the issue should state explicitly.**

1. **Base URL override: yes, but only through the OpenAI SDK, not through Keep.** The string `OPENAI_BASE_URL` appears nowhere in Keep's application code. Keep calls bare `OpenAI()` in the backend [4] and `new OpenAI({organization, apiKey})` in the frontend [4]. Both pinned SDKs read `OPENAI_BASE_URL` themselves: openai-python 1.37.1 (Keep's pin) at `_client.py` lines 119 and 333 [7], and openai-node 4.86.2 (Keep UI's version) at `index.ts` line 220 [8]. Keep's docs list the variable for both services [5][6]. Confidence: high for the mechanism, medium for end-to-end behaviour, because nobody has run it against Fireworks. The Keep `openai` **workflow provider** is a different code path and has **no** base-URL option [4]. **Correction:** it builds `OpenAI(api_key, organization)` without `base_url`, so the SDK would still read `OPENAI_BASE_URL` (not tested). The cleaner path, used and **verified live** in section 5, is Keep's `litellm` workflow provider, which takes an explicit `api_url` and POSTs `{api_url}/chat/completions`.
2. **Fireworks model ID: `accounts/fireworks/models/glm-5p3-flash`.** The model exists, is serverless, and was created 2026-08-26 [9]. Base URL is `https://api.fireworks.ai/inference/v1` [10]. So the env set is `OPENAI_BASE_URL=https://api.fireworks.ai/inference/v1`, `OPENAI_MODEL_NAME=accounts/fireworks/models/glm-5p3-flash`, plus the key.
3. **The key variable has two spellings and both are needed.** The backend reads `OPENAI_API_KEY` [4]. The frontend chat route reads `OPEN_AI_API_KEY` [4]. Set both, or one half of the AI features fails.
4. **Postgres is optional, and the chart default is MySQL.** Keep supports sqlite, mysql and postgres in code [4]. The chart defaults to `database.type: mysql` [3]. Postgres is a values switch (bundled) or an external connection string. The issue should say "Postgres by choice", not "Keep requires Postgres".
5. **The headline AI feature needs the proprietary EE tier.** Incident summary and name generators are `NotImplemented` unless `EE_ENABLED=true` [4], and `ee/` carries a separate Enterprise License [4]. The AI Incident Assistant is documented as "experimental" in open source [18]. The issue's "AI summary" outcome therefore needs a licensing decision or a scope change. **Correction:** setting `EE_ENABLED=true` does not help either. The summary job `process_summary_generation` is queued in `incidents_bl.py:230-237` but defined nowhere in the public repo; its code lived in `ee/experimental/` and was deleted in commit `bdc8e52d` (PR #2578, 2024-11-25) [21]. keephq.dev lists summarisation as "Keep Enterprise only" [22]. **Decision taken:** no EE; the summary comes from a Keep workflow (litellm provider to Fireworks, then Slack), verified in section 5.

Also worth a line in the issue: Alertmanager authenticates with HTTP basic auth (username `api_key`), while Grafana uses an `X-API-KEY` header [12][13]. Chart pins no image tag for Keep's own images (they follow `appVersion` 0.54.3) but uses `:latest` for MySQL and Postgres [3].

## 1. Install and Postgres

- Repo `https://keephq.github.io/helm-charts`, chart `keephq/keep`, install `helm install keep keephq/keep -n keep --create-namespace` [1]. Latest chart **0.1.97**, appVersion **0.54.3**, created 2026-09-09 [2]. Chart.yaml has no `kubeVersion` and no dependencies, and the docs state no minimum Kubernetes version [2] (absence, so unknown).
- Workloads: backend (FastAPI, 8080), frontend (Next.js, 3000), Soketi websocket (6001), and a database Deployment [3]. Image tags for backend and frontend default to `.Chart.AppVersion` (verified in `templates/backend.yaml` line 55) [3].
- **Database switch (verified in values.yaml):** `database.enabled: true`, `database.type: mysql` with `# type: postgres  # can be 'mysql' or 'postgres'` as the alternative; bundled Postgres uses `postgres:latest`, `POSTGRES_DB=keep`, `POSTGRES_PASSWORD=mysecretpassword`, 5Gi PVC on the default StorageClass [3]. Backend env defaults to `DATABASE_CONNECTION_STRING=mysql+pymysql://root@keep-database:3306/keep` with the Postgres form commented: `postgresql+psycopg2://postgres:mysecretpassword@keep-database:5432/keep` [3]. `backend.waitForDatabase.port` defaults to 3306, with 5432 commented [3], so switching to Postgres means changing three things together (type, connection string, wait port). `backend.databaseConnectionStringFromSecret` exists for secret-based strings [3]. For an external database set `database.enabled=false` and `waitForDatabase.enabled=false` (the chart comment says so) [3].
- sre-stack fit: the chart's `backend.env` is a list. Helm replaces lists wholesale on override, so values files must restate the whole list (inference from Helm semantics, not tested). Default StorageClass: sre-stack uses `gp2`; set `database.pv/pvc.storageClass` explicitly [3].
- Auth: chart default is `AUTH_TYPE=NOAUTH`, no login [5]. Valid types include DB, KEYCLOAK, OAUTH2PROXY and others; the value is `NOAUTH`, not `NO_AUTH` [5][16]. `AUTH_TYPE=DB` needs `KEEP_JWT_SECRET`, default login `keep`/`keep` [16]. Use uppercase `DB`: lowercase caused a silent redirect loop (issue #6809, closed, fix unverified) [19]. Ingress-nginx 4.12+ needs `allow-snippet-annotations=true` and `annotations-risk-level=Critical` [1].
- Ecosystem (brief, medium confidence): MIT licence except `ee/` [4]; about 10 app releases in the last 7 months, chart releases slower (5 in 13 months) [2][19]; open issues include #3662 frontend crash on K8s 1.30 (open, maintainer could not reproduce) and #6876 workflows count query CPU-bound on MySQL (open) [19]. No acquisition or backing evidence found (inconclusive).

## 2. AI backend (Fireworks)

- **Where AI runs.** Backend: `IncidentReportsBl` and `AISuggestionBl` build `OpenAI()` with no arguments and call `chat.completions.create` with `model=OPENAI_MODEL_NAME`, `response_format={"type":"json_schema",...}`, `seed=1239` and a temperature of 0.2 unless `KEEP_AI_DISABLE_TEMPERATURE` is truthy [4]. `OPENAI_MODEL_NAME` defaults to `gpt-4o-2024-08-06` (`keep/api/consts.py:54`) [4]. Frontend: `app/api/copilotkit/route.ts` creates `new OpenAI({organization: OPEN_AI_ORGANIZATION_ID, apiKey: OPEN_AI_API_KEY})` and passes `model: OPENAI_MODEL_NAME` when set [4].
- **Base URL.** Both SDKs fall back to `OPENAI_BASE_URL` when `base_url` is not passed [7][8]. Keep documents the variable for backend and frontend [5], and its LiteLLM guide uses it the same way [6]. A GitHub discussion bot claimed the core AI path does not pass it [17]; the code above shows it does not need to, so that claim is explained, not contradicted. Fireworks docs name `OPENAI_API_BASE` instead [10]: do **not** use that name, the pinned SDKs do not read it [7] (checked: no match in `_client.py`).
- **Model ID.** `accounts/fireworks/models/glm-5p3-flash` is quoted on the model page as the full ID: serverless "Supported", function calling and image input supported, context shown as "1040k tokens", $0.15 input / $0.03 cached / $0.50 output per million tokens, created 2026-08-26 [9]. Z.ai's open-weights release (MIT, 320B/18B-active MoE) is dated 2026-08-26 by one secondary source [20] (medium). Sibling `glm-5p3` also exists [digest]. Other GLM IDs were not enumerated.
- **Compatibility risks (unverified, test first):** (a) Fireworks documents `json_schema` response_format in the OpenAI shape, but says it **disables reasoning output** [11]; fine for Keep's structured calls. (b) `seed` is not mentioned in the Fireworks structured-output page; the API reference was not checked [11]. (c) Fireworks lowers `max_tokens` rather than erroring on overflow [10]. (d) Keep pins openai-python 1.37.1, which predates json_schema typing; Keep ships it, so it works against OpenAI, but not proven against Fireworks.
- **Licensing gate.** `import_ee.py`: with `EE_ENABLED` unset, `SUMMARY_GENERATOR_VERBOSE_NAME`, `NAME_GENERATOR_VERBOSE_NAME` and `ALGORITHM_VERBOSE_NAME` are `NotImplemented`; `ee/LICENSE` is a separate Enterprise License ("Keep Alerting LTD") [4]. Docs: AI Incident Assistant is Cloud and Enterprise "available", Open Source "experimental" [18]. Bot-sourced extras (Redis, at least 5 distinct fingerprints for a summary) are low confidence [17].

## 3. Alertmanager and Grafana into Keep

- **Alertmanager (high confidence, docs + provider code [12]).** Webhook `http://<keep-backend>:8080/alerts/event/prometheus` with `send_resolved: true` and `http_config.basic_auth` username `api_key`, password = Keep API key. In-cluster service names `keep-backend` (8080) are plausible from the install page but unconfirmed end to end. Severity comes from `labels.severity` (unknown becomes INFO); fingerprint is Alertmanager's own; `lastReceived` is set at receipt time [12]. Unverified: how multi-alert groups are split, and a possible TypeError when a payload alert has an `id` key [12].
- **Grafana (high confidence [13]; auth and severity corrected in section 6).** Contact point type Webhook to `/alerts/event/grafana` with header `X-API-KEY` (**correction:** Keep's own setup uses `Authorization: digest <key>`, and the severity map has no `error`; section 6), plus a notification policy with **no matchers** or only matching alerts forward [13]. Unified alerting (Grafana 9+) is the supported path; no explicit matrix for 10/11/12 [13]. No labels required, but without a `severity` label everything is INFO; service defaults to "unknown" [13].
- **API keys.** Created in UI Settings, Users and Access, API Keys, role `webhook` [16] (medium, search-summary sourced). Declarative alternative: `KEEP_DEFAULT_API_KEYS="name:role:secret"` [5]. There is no `KEEP_API_KEY` variable [5]. With NOAUTH any `x-api-key` value is accepted [16]. `KEEP_ALLOW_MESH_ALERT_INGESTION=true` allows unauthenticated posts and needs network controls [5].

## 4. Slack (notifications only)

- An incoming-webhook URL is enough: config `webhook_url`, no scopes, no OAuth app; the webhook is bound to one channel [14]. The bot-token path (`chat:write`, `channel` required, `SLACK_CLIENT_ID/SECRET` for the OAuth flow) is only needed for threads, message updates and reactions [14]. Avoid it. If both are set the webhook wins [14].
- Workflow step `with` keys: `message`, `blocks`, `channel`, `attachments`, ...; at least one of message, blocks, attachments [14]. Keep did not show a Slack workflow YAML example in the fetched text [14] (gap).
- **Declarative provisioning:** `KEEP_PROVIDERS` (JSON) or `KEEP_PROVIDERS_DIRECTORY` (YAML, recommended), not both; providers missing from config are removed on restart [15]. Workflows: `KEEP_WORKFLOWS_DIRECTORY`, reconciled on restart [15]. The chart has `backend.provision.providers` and a `backend-provision.yaml` template [3], so provisioning is chart-native (template body not read).

## 5. Manual try-out on AKS (2026-10-23)

Run by hand on cluster `sre-stack-452138` (AKS, Kubernetes 1.34) with chart `keephq/keep` 0.1.97 (Keep 0.54.3) [23]. Nothing was committed to the repo; what the try-out left on the cluster is listed at the end of this section. The exact files used are in `tryout/` next to this document: `keep-values.yaml`, `prometheus-stack-keep-override.yaml`, `robot-shop-keep-tryout-rules.yaml`, `notify-slack-with-context.yaml`, `fireworks-smoke.sh`, and the line-by-line log `keep-tryout-findings.md`. Secrets lived in `~/.secrets/keep/` and Kubernetes Secrets only; none are in these files.

**What was proven end to end.** The OOM fault (scenario 02, `make aks-cart-oom-start`) with loadgen running:

| Time (UTC) | Event |
|---|---|
| 16:53:17 | Fault started; cart OOM-killed within 60s |
| 16:54:44 | Keep opened **one** incident "Robot-shop degradation" (critical) from 5 alerts (cart OOM, cart restarting, cart replicas unavailable, web 5xx, payment slow), 6 alerts later |
| 16:55:15 | Workflow ran (8.0s): Fireworks GLM-5.3 Flash summary, accurate (cart OOM causing web 19.4% 5xx and payment p95 1.89s, names the pod, says what to check first), posted to Slack. 4,400 input / 697 output tokens |
| 17:02:19 | Fault reverted |
| 17:10:17 | Incident auto-resolved after its last alert cleared (`resolveOn: all_resolved`) |

**Fireworks (laptop curl first, then in Keep).**
- Plain chat, `json_schema` + `seed=1239` + temperature 0.2 (the incident report's request shape), and tool calling all return HTTP 200 with valid output.
- **GLM-5.3 Flash is thinking-only.** With `max_tokens: 200` a one-sentence question spent all 200 tokens reasoning and returned empty content (`finish_reason: length`). `reasoning_effort: "none"` is rejected (HTTP 400, "thinking-only model"); `"low"` works, but Keep's `litellm` provider cannot send it (it sends only model, messages, `max_tokens`, temperature). Decision: the workflow sets `max_tokens: 10000`, verified accepted. The provider raises a clear error on empty content (`litellm_provider.py:121-131`), so a small budget fails loudly.
- `OPENAI_MODEL_NAME` must be set on backend **and** frontend; without it Keep asks for `gpt-4o-2024-08-06` (`keep/api/consts.py:54`).

**Install findings (chart 0.1.97).**
- `backend.env` and `frontend.env` are lists, so overriding them replaces the chart defaults; the values file restates them (confirms the inference in section 1).
- `backend.env` supports `secretKeyRef`; **`frontend.env` renders plain `value` only.** The key reaches both via `envFromSecret` on a Secret whose keys are the env var names (`OPENAI_API_KEY`, `OPEN_AI_API_KEY`). This answers open question 3 for the AI vars.
- The chart's default `database.pv` is a **hostPath** PersistentVolume; set `database.pv.enabled: false` and `database.pvc.storageClass: gp2` (bound a 5Gi Azure disk).
- **Keep sends telemetry to PostHog by default** ("Uptime reported to PostHog"). Turn off with `POSTHOG_DISABLED=true` (backend and frontend) and `SENTRY_DISABLED=true` (frontend).
- **Pre-delete hook** `delete-keep-secrets` deletes every Secret named `keep-*` in the namespace on `helm uninstall` (Keep stores provider credentials as Secrets). Our own Secrets must use another prefix. The hook uses `bitnami/kubectl:latest`; `mysql:latest` and `busybox` are also unpinned.
- All four pods ran on the `workload=o11y` pool with the o11y and spot tolerations (AD-003). One readiness probe failed at boot, then healthy.
- **Kubernetes 1.34: the frontend does not crash** (issue #3662 not reproduced).
- With ingress disabled the UI works through a port-forward on 3000 (`API_URL_CLIENT` becomes `/backend`), but the **realtime websocket fails**; pages need a manual refresh. The real story needs a route for the websocket server. The browser console showed the connection path `ws://localhost:3000/websocket/app/keepappkey?protocol=7&client=js&version=8.4.0`: the page origin, the chart's `/websocket` prefix, then the Pusher path `/app/<app key>`.

**Auth and API keys.**
- Under `NOAUTH`, Keep **accepts any API key** (or an unknown one) as single-tenant admin (`noauth_authverifier.py`). Keep must stay cluster-internal, or use `AUTH_TYPE=DB`.
- The UI's "Create API key" button is **disabled** under `NOAUTH`. `POST /settings/apikey {"name","role":"webhook"}` works.

**Alerts into Keep: two blockers in this repo, not in Keep.**
- **Alertmanager is off** (`monitoring/chart-values/prometheus-values.yaml:42-43`), `defaultRules.create: false`, and the only rule group alerts on **Bookinfo**, which is not deployed. So robot-shop and hotrod have **no alerts today**. The try-out enabled Alertmanager with an override (diffed first: 0 removed lines, adds 5 Alertmanager objects and an `alerting` block) and added 5 temporary rules.
- The repo's Alertmanager config carries a **broken Slack setting** (placeholder `slack_api_url: "slack-webhook-url"`, a `P1 -> slack` sub-route). Decision: remove it in the implementation. Because Helm merges maps, overriding `route` leaves that sub-route in place; `routes: []` must be set explicitly.
- Webhook verified: `http://keep-backend.keep.svc.cluster.local:8080/alerts/event/prometheus`, basic auth username `api_key`, password from a mounted Secret via `password_file` (`alertmanagerSpec.secrets`), `send_resolved: true`. A test alert arrived in 15s (HTTP 202) and flipped to resolved after 5 minutes. Severity must be one of critical/error/high/warning/info; the repo's existing `P1` label shows as INFO.
- Usable robot-shop metrics: kube-state-metrics restarts and unavailable replicas, and **Beyla** `http_server_request_duration_seconds` with `service_name` and `http_response_status_code`. `istio_requests_total` has only 4 series here. Rules need the label `release: prometheus-stack`. Keep flattens Prometheus labels to top-level fields, so a correlation rule can match `namespace == "robot-shop"`.

**Keep configuration through its API (no UI needed).** `POST /providers/install` (Slack `webhook_url`; litellm `api_url` + `api_key`), `POST /rules` (needs `sqlQuery` alongside `celQuery`; used grouping by namespace, 600s window, threshold 3, `resolveOn: all_resolved`), `POST /workflows` (multipart file). Workflow templates reference providers by name (`{{ providers.fireworks }}`) and can read `{{ incident.alerts }}`; step output is `{{ steps.<name>.results.response }}`.

**What did not work, or is left open.**
- **"AI Summary" button: failed.** It ran about 40s and saved nothing (`user_summary` stayed null). The chat's "record root cause" action saved three empty entries. Chat text answers were correct. So CopilotKit's actions get empty arguments with this model, although tool calling via curl worked. Cause not proven (likely CopilotKit's streaming adapter with this model's tool-call chunks). Not debugged; follow-up.
- No "resolved" Slack message: the workflow triggers on incident created only. Demo step 5 needs a second trigger.
- The resolved incident has `end_time: null`; Keep's report computes time-to-resolve only from incidents with an end time, so auto-resolved incidents may count as zero (seen on one incident only).
- The payment p95 > 1s rule cleared last, 8 minutes after the fix; the threshold may sit near payment's normal latency under loadgen. Tune it.
- The UI labels rule-correlated alerts "Manually" in its Correlation column.
- Grafana into Keep, Kubernetes events and Loki were not tried (happy path only). Section 6 covers what the source says about each.

## 6. Source checks during story review (2026-10-24)

While the 13 stories for epic #91 were reviewed (`_bmad-output/specs/spec-keep-alert-management/stories.yaml`), the open points below were settled by reading Keep's source at `e5cd869` [4], rendering the pinned charts, and reading the repo. None of it was run live; each story's live checks prove it. Story ids are the ids in `stories.yaml`.

**Resolved message, exactly once (story 5b) [24].**
- Incident triggers take only an `events` list (`created`, `updated`, `deleted`); unlike alert triggers they have no `cel` or `filters` (`keep/workflowmanager/workflowmanager.py:147-154`). A "status is resolved" condition therefore goes on the action as `if:`, not on the trigger.
- The rules engine sends `updated` for every alert event it adds to a visible incident, including the one that resolves it (`keep/rulesengine/rulesengine.py:197-208`); `IncidentBl.resolve_incident_if_require` also sends `updated` when it resolves (`keep/api/bl/incidents_bl.py:455-466`). So a status condition alone can post more than once.
- Keep's own example `examples/workflows/incident-tier-escalation.yml` shows the fix: the action's `if:` checks a marker and the action sets it with `enrich_incident`. Keep loads incident enrichments onto the incident before each run (`workflowmanager.py:159-162`), so the next run sees the marker. Untested risks: two near-simultaneous updates both passing before the marker is written, and a reopened incident keeping its marker.

**Grafana into Keep (story 8) [25].** Two claims in section 3 were second-hand and are corrected here.
- Keep's Grafana severity map has only `critical`, `high`, `warning`, `info` (`keep/providers/grafana_provider/grafana_provider.py:120-125`); anything else becomes info (`:413`). The Prometheus provider also accepts `error`; Grafana does not.
- Authentication: `X-API-KEY` is only the manual instruction in the provider's docs (`:85`). Keep's own setup code, for Grafana newer than 9.4.7, sets the contact point's `authorization_scheme: digest` and `authorization_credentials: <api key>` (`:574-581`), and Keep's auth checker accepts the Digest scheme (`keep/identitymanager/authverifierbase.py:320`).
- kube-prometheus-stack 52.0.0 depends on Grafana chart `6.60.*` (`helm show chart`), so Grafana 10, newer than 9.4.7.
- Decision recorded in AD-012 rule 3: Grafana reads the existing Secret `alertmanager-keep-auth` (same `monitoring` namespace, same release) through an environment variable, so the key gets no new copy.

**Kubernetes events (story 9) [24].**
- Keep cannot take Kubernetes events in as alerts. `keep/providers/kubernetes_provider/kubernetes_provider.py` has no `_get_alerts`, no `_format_alert` and no webhook. It is a query and action provider with commands including `get_events` for a namespace or pod (`:150`, `:170`, `:332-360`), and it can use in-cluster credentials (`use_in_cluster_config`, `:46`, `:109`). No event exporter appears in Keep's code or docs.
- So CAP-10 was reshaped: the opened-incident workflow queries `get_events` for `robot-shop` and passes them into the Fireworks prompt. Events never become alerts, so the one-incident rule is not at risk.
- Chart 0.1.97 renders `serviceAccountName: keep` on every Keep pod, already bound to the chart's Role `secret-manager-role` (Secrets in `keep`). A RoleBinding in `robot-shop` for service account `keep` (namespace `keep`), get and list events only, is all the provider needs.

**Loki log alerts (story 10) [26].**
- The AKS Loki is `grafana-community/loki` 18.13.7 (`makefile:218`), Monolithic mode (`infra/azure/chart-values/loki.yaml`). Its chart values have the ruler on by default (`ruler.enabled: true`), a `loki.rulerConfig` block for Loki's ruler settings including `alertmanager_url`, and a rules sidecar on by default (`sidecar.rules.enabled: true`) that loads ConfigMaps labelled `loki_rule`.
- So a log alert can go Loki ruler → the existing Alertmanager → Keep, with no new key, and with the Prometheus provider's severity list. Left for the live check: which pod runs the ruler in Monolithic mode, the tenant folder (the chart defaults auth on), and the Alertmanager Service name.

**"AI Summary" button (story 11) [24].**
- It is open-source UI code, not the enterprise tier. `keep-ui/app/(keep)/incidents/[id]/incident-overview.tsx:85-110` runs a CopilotKit `CopilotTask` asking the model to call the tool `setGeneratedSummary(summary)`; its handler saves `user_summary` through `updateIncident`.
- The request goes to the frontend's own route `keep-ui/app/api/copilotkit/route.ts:9-25` (CopilotKit `OpenAIAdapter`, `OPEN_AI_API_KEY`, `OPENAI_MODEL_NAME`, base URL from the OpenAI client's environment), then Fireworks. Keep's backend is not involved. CopilotKit runtime `^1.8.11` (`keep-ui/package.json:24`).
- With the try-out's empty tool arguments and a working non-streaming curl tool call, the likely cause is streamed tool-call chunks. The first check needs no cluster: the same tool call with `stream: true`. This repo runs upstream images, so any fix can only be configuration.

**Repo facts used by the stories.**
- AKS `make cleanup` is `cleanup-cluster` only (`makefile:456`), so anything applied with `kubectl` goes with the cluster.
- `makefile:125` installs `prometheus-stack` from the shared values alone (EKS, k3d); `makefile:213` adds the AKS overlay. The shared file's `additionalPrometheusRulesMap` holds only the unused Bookinfo rule.
- AKS-only extras are plain files under `infra/azure/` applied with `kubectl apply`, for example `makefile:167` (`infra/azure/dashboards/`). HotROD's route is `app/hotrod/istio-gateway.yaml`, applied at `makefile:345`.
- `make setup-aks` does not start the load generator; it only prints the commands (`makefile:309-310`).
- The OOM scenario's output rules are in `specs/007-aks-oom-kill/contracts/commands.md`; section 3 makes `RESULT:` the one line each run prints at the end.

**Cleanup (done 17:14 UTC, cluster left running).** All of the following were removed and verified: `keep` namespace gone; `prometheus-stack` revision 3 = rollback to 1 (no Alertmanager pod, no `alerting` block on Prometheus); only the original rule group remains; Secret gone; loadgen at 0. The uninstall hook worked (`bitnami/kubectl:latest` pulled) and deleted every `keep-*` Secret, including Keep's stored provider credentials. Kept on the laptop for the implementation: `~/.secrets/keep/` (Fireworks key, Slack webhook, an API key for a Keep install that no longer exists). The commands used, per item:
- Helm release `keep` (revision 2) in namespace `keep`, with Secrets `keep-secrets` and `keep-ai-env`. Undo: `helm uninstall keep -n keep` (its hook deletes the `keep-*` Secrets), then `kubectl delete ns keep`.
- `prometheus-stack` at revision 2 (Alertmanager on, routed to Keep). Undo: `helm rollback prometheus-stack 1 -n monitoring`.
- Secret `keep-alertmanager-auth` and PrometheusRule `keep-tryout-robot-shop` in `monitoring`. Undo: `kubectl -n monitoring delete secret keep-alertmanager-auth` and `kubectl -n monitoring delete prometheusrule keep-tryout-robot-shop`.
- Loadgen scaled to 1 replica. Undo: `kubectl -n loadgen scale deploy/load --replicas=0`.
- Fault reverted (`make aks-cart-oom-revert`).

## Contrary evidence and confidence notes

- Keep docs say `DATABASE_CONNECTION_STRING` has no default; code defaults to `sqlite:///./keep.db` (digest) and the chart sets MySQL [3][5]. Treat the chart as authoritative.
- ~~Not tested live: Keep to Fireworks calls, Alertmanager in-cluster auth, and Keep behaviour on Kubernetes 1.34 (AKS) are all unverified.~~ All three were tested live in section 5 and work. Issue #3662 (K8s 1.30 crash) is open [19] but did not reproduce on 1.34.
- Claims relying on one fetch summary (Grafana version behaviour, Slack scopes, API key UI path) are flagged medium. The API key UI path is now known to be disabled under `NOAUTH` (section 5).

## Open questions

1. ~~Does GLM-5.3 Flash return valid output for Keep's `json_schema` calls with `seed` set?~~ **Answered: yes** (section 5, curl).
2. ~~Is the EE tier acceptable for incident summaries?~~ **Answered: no EE.** The summary is produced by a workflow; verified (section 5).
3. ~~Which Helm values path injects the AI env vars?~~ **Answered for AI vars:** plain `env` entries plus `envFromSecret` on backend and frontend (section 5). `AUTH_TYPE` and `KEEP_PROVIDERS_DIRECTORY` still unread.
4. ~~Kubernetes 1.34 behaviour of Keep 0.54.3?~~ **Answered: runs, no frontend crash** (section 5). Minimum version still undocumented.
5. New: why do CopilotKit actions ("AI Summary", "record RCA") get empty arguments with GLM-5.3 Flash? **Narrowed** (section 6): the call path is frontend-only through CopilotKit; streamed tool-call chunks are the likely cause. Story 11 tests it.
6. ~~New: should the epic declare Keep providers, rule and workflow through the chart's provisioning instead of API calls?~~ **Answered in AD-011:** providers and workflows by start-up provisioning; the correlation rule by an idempotent `POST /rules` script, because provisioning does not cover rules.

## Sources

| # | Source | Publisher | Date | Note |
|---|---|---|---|---|
| 1 | https://docs.keephq.dev/deployment/kubernetes/installation | Keep | n/a | docs |
| 2 | https://keephq.github.io/helm-charts/index.yaml ; github.com/keephq/helm-charts `charts/keep/Chart.yaml` | keephq | 2026-09-09 | chart 0.1.97 / app 0.54.3 |
| 3 | github.com/keephq/helm-charts `charts/keep/values.yaml`, `templates/` @734018e | keephq | 2026-09-09 | read by lead |
| 4 | github.com/keephq/keep @e5cd869: `keep/api/bl/incident_reports.py`, `ai_suggestion_bl.py`, `consts.py`, `utils/import_ee.py`, `utils/ai_utils.py`, `keep-ui/app/api/copilotkit/route.ts`, `ee/LICENSE`, `LICENSE`, `pyproject.toml` | keephq | 2026-10-22 | read by lead |
| 5 | https://docs.keephq.dev/deployment/configuration | Keep | n/a | env vars |
| 6 | https://docs.keephq.dev/deployment/local-llm/keep-with-litellm | Keep | n/a | |
| 7 | github.com/openai/openai-python `src/openai/_client.py` @v1.37.1 | OpenAI | n/a | lines 119, 333 |
| 8 | github.com/openai/openai-node `src/index.ts` @v4.86.2 | OpenAI | n/a | line 220 |
| 9 | https://fireworks.ai/models/fireworks/glm-5p3-flash | Fireworks AI | 2026-08-26 | fetched twice |
| 10 | https://docs.fireworks.ai/tools-sdks/openai-compatibility | Fireworks AI | n/a | |
| 11 | https://docs.fireworks.ai/structured-responses/structured-response-formatting | Fireworks AI | n/a | |
| 12 | https://docs.keephq.dev/providers/documentation/prometheus-provider ; `keep/providers/prometheus_provider/prometheus_provider.py` | Keep | n/a | via subagent |
| 13 | https://docs.keephq.dev/providers/documentation/grafana-provider ; `grafana_provider.py` | Keep | n/a | via subagent |
| 14 | https://docs.keephq.dev/providers/documentation/slack-provider ; `slack_provider.py` | Keep | n/a | via subagent |
| 15 | https://docs.keephq.dev/deployment/provision/provider ; /workflow ; /overview | Keep | n/a | via subagent |
| 16 | https://docs.keephq.dev/deployment/authentication/no-auth ; /db-auth ; checkly provider page | Keep | n/a | via subagent |
| 17 | https://github.com/keephq/keep/discussions/6533 | GitHub (bot answers) | 2026-05-27 | low-medium |
| 18 | https://docs.keephq.dev/overview/ai-incident-assistant | Keep | n/a | |
| 19 | https://github.com/keephq/keep/issues (#3662, #5521, #6809, #6563, #6876) ; releases page | GitHub | 2025-2026 | via subagent |
| 20 | https://datanorth.ai/news/z-ai-releases-glm-5-3-flash | DataNorth AI | 2026-08-26 | secondary |
| 21 | github.com/keephq/keep commit `bdc8e52d` (PR #2578) deleting `ee/experimental/`; `keep/api/bl/incidents_bl.py:224-252` @e5cd869 | keephq | 2024-11-25 | read via git history |
| 22 | https://www.keephq.dev/ | Keep | 2026-10-23 | "KEEP ENTERPRISE ONLY" summarisation |
| 23 | Manual try-out on AKS `sre-stack-452138`, files in `tryout/` | this project | 2026-10-23 | live run |
| 24 | github.com/keephq/keep @e5cd869: `keep/workflowmanager/workflowmanager.py`, `keep/rulesengine/rulesengine.py`, `keep/api/bl/incidents_bl.py`, `examples/workflows/incident-tier-escalation.yml`, `keep/providers/kubernetes_provider/kubernetes_provider.py`, `keep-ui/app/(keep)/incidents/[id]/incident-overview.tsx`, `keep-ui/app/api/copilotkit/route.ts`, `keep-ui/package.json` | keephq | 2026-10-22 | read during story review |
| 25 | github.com/keephq/keep @e5cd869: `keep/providers/grafana_provider/grafana_provider.py`, `keep/identitymanager/authverifierbase.py`; `helm show chart prometheus-community/kube-prometheus-stack --version 52.0.0` | keephq, prometheus-community | 2026-10-24 | corrects section 3 |
| 26 | `helm show values grafana-community/loki --version 18.13.7`; `helm template keep keephq/keep --version 0.1.97` | Grafana community, keephq | 2026-10-24 | chart render, read during story review |
