# Keep manual try-out: findings log (2026-10-23)

Feeds the "Manual try-out" section of research.md (step 13). Status per line: VERIFIED / FAILED / UNTESTED.

## Cluster
- sre-stack-452138 started 21:50 IST, 9 nodes Ready (app x3, loadgen, nodepool1, o11y x2, persistent x2), Kubernetes 1.34.
- kube-state-metrics ImagePullBackOff right after start: recheck before install.

## Slack (step 2)
- VERIFIED: Slack app "Keep SRE Stack", scope incoming-webhook only, no events, private channel keep-alerts-srestack. Webhook POST returned HTTP 200 "ok", message arrived.
- App token (xapp) and bot token (xoxb) were issued by Slack's setup wizard; not needed and not stored.

## Fireworks smoke test (laptop, curl, model accounts/fireworks/models/glm-5p3-flash)
- VERIFIED: plain chat works (HTTP 200).
- VERIFIED: json_schema response_format + seed=1239 + temperature 0.2 (Keep incident report shape) accepted; valid JSON grouping returned. Open question 1 answered: yes.
- VERIFIED: tool calling works; model returned a setGeneratedSummary tool call with finish_reason tool_calls. Open question 2 (CopilotKit) answered at API level: yes. CopilotKit itself untested.
- NEW: GLM-5.3 Flash is a thinking-only model. With max_tokens 200 a one-sentence question spent all 200 tokens on reasoning and returned empty content (finish_reason length). reasoning_tokens seen: 200, 263, 28.
- NEW: reasoning_effort "none" rejected (HTTP 400, "GLM-5.3 is a thinking-only model; disabling thinking ... is not supported"). reasoning_effort "low" accepted: 0 reasoning tokens, 38 output tokens.
- NEW: Keep's litellm provider sends only model, messages, max_tokens (default 1024), temperature (default 0.7); it cannot pass reasoning_effort. It raises a clear ProviderException when content is None (litellm_provider.py:121-131), so a too-small max_tokens fails loudly, not silently. Workflow should set max_tokens generously.
- DECISION (user, 22:01): workflow uses max_tokens 10000.
- VERIFIED: max_tokens 10000 accepted (HTTP 200); same one-sentence prompt finished normally (finish_reason stop, 180 reasoning + 41 answer tokens). Billing is on tokens actually used, so the higher cap costs nothing unless the model reasons longer.

## Install (chart keephq/keep 0.1.97, app 0.54.3), values in scratchpad keep-values.yaml
- VERIFIED: backend.env and frontend.env are lists; overriding replaces the chart defaults, so defaults must be copied over.
- VERIFIED: backend.env supports secretKeyRef; frontend.env renders plain `value` only. Key reaches both via envFromSecret on a Secret whose keys are the env var names (OPENAI_API_KEY, OPEN_AI_API_KEY).
- VERIFIED: frontend OPEN_AI_API_KEY_SET is true when OPEN_AI_API_KEY or OPENAI_API_KEY is set (keep-ui/shared/lib/server/getConfig.ts:76-77).
- VERIFIED: chart default database.pv is a hostPath PersistentVolume; disabled it, PVC on gp2 bound a 5Gi Azure disk.
- VERIFIED: all 4 pods (backend, frontend, websocket, MySQL database) Running on workload=o11y with o11y + spot tolerations, 0 restarts.
- Images: Keep images pinned to 0.54.3 via appVersion; mysql:latest, busybox (wait-for-database init) and bitnami/kubectl:latest are unpinned.
- NEW: pre-delete hook Job delete-keep-secrets deletes every Secret named keep-* in the namespace on helm uninstall (Keep stores provider creds as k8s secrets). Our own Secrets must not use the keep- prefix in the real story.
- NEW: Keep reports uptime telemetry to PostHog by default ("Uptime reported to PostHog" in logs). POSTHOG_DISABLED=true (keep/api/core/posthog.py:17) on backend + frontend, SENTRY_DISABLED=true on frontend. Applied in revision 2.
- One readiness probe failure at startup (connection refused before uvicorn listened), then /healthcheck 200. Harmless.
- VERIFIED: open question 4. Frontend runs on Kubernetes 1.34 (AKS) without crashing; UI loads, NOAUTH lands on Incidents, "Try AI Correlation" shown.
- NEW: NOAUTH accepts any API key, or an unknown one, and authenticates as single-tenant admin (keep/identitymanager/identity_managers/noauth/noauth_authverifier.py). Keep must stay cluster-internal under NOAUTH; real story: AUTH_TYPE=DB or internal-only route.
- NEW: UI "Create API key" button is disabled under NOAUTH. Created via API instead: POST /settings/apikey {"name":"alert-sources","role":"webhook"} -> HTTP 200, 36-char secret (saved ~/.secrets/keep/keep-webhook-api.key).
- NEW (blocks the issue's step 1): on this stack Alertmanager is DISABLED (monitoring/chart-values/prometheus-values.yaml:42-43 alertmanager.enabled false), defaultRules.create false, and the only PrometheusRule (kube-prometheus-stack-rule-name, GroupA) alerts on Bookinfo services (reviews/productpage/ratings/details), which are not deployed. So no Prometheus alerts exist for robot-shop or hotrod today; the "alert storm" has to be built.
- IMPLEMENTATION NOTE (user, 22:12): remove the broken Slack setting from monitoring/chart-values/prometheus-values.yaml alertmanager.config (placeholder slack_api_url "slack-webhook-url", P1 -> slack sub-route, channel #sre-stack).
- DECISION (user, 22:12): option 2, enable Alertmanager and push to Keep; happy path only, everything else logged as follow-up.

## Alertmanager -> Keep (step 7)
- Override in scratchpad prometheus-stack-keep-override.yaml, layered after the two repo values files; helm upgrade prometheus-stack (chart 52.0.0) revision 1 -> 2. Revert: helm rollback prometheus-stack 1.
- NEW: Helm merges maps, so the base P1 -> slack sub-route survives an override of route; routes: [] must be set explicitly or the config references a missing receiver.
- VERIFIED: pre-upgrade diff (helm template base vs base+override): 0 removed lines; adds 5 Alertmanager objects and a 7-line alerting block on the Prometheus CR. Live vs re-rendered base differs only by helm test hooks and a capability-dependent RBAC rule (render-time, not drift). helm-diff plugin not installed.
- Keep API key passed via password_file from Secret keep-alertmanager-auth mounted with alertmanagerSpec.secrets (no key in values). jq -r had added a trailing newline to the saved key; stripped.
- VERIFIED: Alertmanager 2/2 on o11y pool, config loaded without errors.
- VERIFIED: open question 3. Synthetic alert posted to Alertmanager API -> after group_wait 15s, POST /alerts/event/prometheus 202 -> Keep shows KeepTryoutSynthetic severity warning, firing, source prometheus.
- Keep endpoint confirmed from Keep's own webhook_template (keep/providers/prometheus_provider/prometheus_provider.py:58-74). Severity map accepts critical/error/high/warning/info; repo's existing P1 label would map to INFO.
- VERIFIED: Prometheus activeAlertmanagers lists the new Alertmanager after the operator reload (~1 min).

## Alert rules (temporary PrometheusRule keep-tryout-robot-shop, scratchpad robot-shop-keep-tryout-rules.yaml)
- Metrics available for robot-shop: kube-state-metrics restarts (13 series), kube_deployment_status_replicas_unavailable, Beyla http_server_request_duration_seconds_{count,bucket} with service_name + http_response_status_code (11 services). istio_requests_total has only 4 series (mysql), not useful. kube_pod_container_status_last_terminated_reason has 0 series until a container terminates.
- 5 rules: OOMKilled (critical), ContainerRestarting (high), ReplicasUnavailable (warning), SlowRequests p95 > 1s (warning), HTTPErrors 5xx > 5% (high). All carry namespace, service (label_replace from container/deployment/service_name) and a Keep-recognised severity. PrometheusRule needs label release: prometheus-stack (Prometheus ruleSelector).
- VERIFIED: all 5 loaded, health ok, inactive at 16:48 UTC (no fault, loadgen at 0 replicas).
- VERIFIED: send_resolved. Synthetic alert flipped firing -> resolved in Keep at 16:51:05 (resolve_timeout 5m).

## Providers, rule, workflow (steps 10-11), all via Keep API (x-api-key, NOAUTH)
- VERIFIED: POST /providers/install {provider_id:"slack", provider_name, webhook_url} -> 200; {provider_id:"litellm", provider_name:"fireworks", api_url:"https://api.fireworks.ai/inference/v1", api_key} -> 200. Secrets passed with jq --rawfile, never printed.
- Keep flattens Prometheus labels to top-level alert fields (namespace, service), so CEL `namespace == "robot-shop"` works.
- VERIFIED: POST /rules "robot-shop degradation": CEL namespace == "robot-shop", groupingCriteria [namespace], timeframe 600s, threshold 3, createOn any, resolveOn all_resolved. sqlQuery dict is required by the API alongside celQuery.
- VERIFIED: POST /workflows (multipart file=) -> 201. Workflow notify-slack-with-context (scratchpad notify-slack-with-context.yaml): trigger incident created -> litellm step (model glm-5p3-flash, max_tokens 10000, temperature 0.2, prompt includes {{ incident.alerts }}) -> slack action with {{ steps.summarize.results.response }}. Provider refs by name: {{ providers.fireworks }}, {{ providers.keep-alerts-srestack }}.
- Workflow runs API returns runs under `items` (not workflow_executions).

## End-to-end with OOM fault (scenario 02, step 12)
- Loadgen scaled 0 -> 1 (kubectl -n loadgen scale deploy/load); cart traffic confirmed; 0 active alerts before fault.
- Fault start 16:53:17 UTC (make aks-cart-oom-start); cart OOM-killed within 60s.
- VERIFIED: Alertmanager active alerts: OOMKilled cart, ContainerRestarting cart, ReplicasUnavailable cart, HTTPErrors web, SlowRequests payment (later HTTPErrors cart).
- VERIFIED: Keep opened ONE incident "Robot-shop degradation" at 16:54:44 (~90s after fault), critical, 5 alerts at creation, 6 later, services web + cart. Dedup/correlation works.
- VERIFIED: workflow run success at 16:55:15 in 8.0s. Fireworks summary accurate (cart OOM -> web 19.4% 5xx, payment p95 1.89s; names the pod; what to check first). Tokens 4400 in / 697 out / 5097 total. Slack returned slack_timestamp (posted).
- NEW: UI labels rule-correlated alerts "👨‍💻 Manually" in the Correlation column.
- VERIFIED: incident chat assistant (CopilotKit) answers "find the root cause" correctly via Fireworks (text works).
- FAILED: "AI Summary" button. Ran ~40s, re-enabled, but incident user_summary stayed null. Chat's "record RCA" action stored rca_points [{},{},{}] (empty). CopilotKit action/tool-call arguments arrive empty with GLM-5.3 Flash, though direct tool calling via curl worked. Likely CopilotKit OpenAIAdapter streaming + this model's tool-call chunks (inference, not proven). Follow-up, not debugged (happy path only).
- Fault reverted 17:02:19 UTC (make aks-cart-oom-revert), cart clean.
- VERIFIED: incident auto-resolved (resolveOn all_resolved). Alerts resolved 17:03:13 (replicas) .. 17:10:13 (payment slow requests, last); incident status resolved seen 17:10:17, ~8 min after revert. All 6 alerts resolved.
- NEW: resolved incident has end_time null. Keep's incident report computes MTTR only from incidents with end_time (keep/api/bl/incident_reports.py), so auto-resolved incidents may report MTTR 0. Unverified beyond this one incident.
- TUNING: payment p95 > 1s stayed firing ~8 min after revert, the last alert to clear; threshold may sit close to payment's normal p95 under loadgen. Tune in the real story.
- Workflow triggers on incident created only, so no "resolved" Slack message. Demo step 5 needs a second trigger (incident updated/resolved).
- NEW: via port-forward the realtime websocket fails (browser tries ws://localhost:3000/websocket and wss://localhost/websocket). Needs a route for the websocket server (Istio gateway) in the real story; manual refresh works meanwhile.
