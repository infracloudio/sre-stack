# Digest: Alertmanager / Grafana / Slack providers + auth (round 1, assistant 1)

Accessed 2026-10-23. Publisher for all rows: Keep (keephq). pub_date n/a for all (docs pages undated; code is `main` branch). Caveat from assistant: WebFetch returns a small-model summary, so quoted YAML/field names are paraphrase-risk unless marked verbatim.

## Prometheus / Alertmanager
- Webhook path `KEEP_BACKEND_URL/alerts/event/prometheus` | https://docs.keephq.dev/providers/documentation/prometheus-provider | high | config
- Alertmanager auth = HTTP basic auth in `http_config`: username `api_key`, password = Keep API key (not X-API-KEY header) | same + https://raw.githubusercontent.com/keephq/keep/main/keep/providers/prometheus_provider/prometheus_provider.py (webhook_template matches) | high | config
- Docs snippet (paraphrased): route receiver `keep`, group_by [alertname], group_wait 15s, group_interval 15s, repeat_interval 1m, continue true; receiver `keep` webhook_configs url=webhook URL, send_resolved: true, http_config.basic_auth {username: api_key, password: <key>} | docs URL | med | config
- Provider also can pull: GET {url}/api/v1/alerts, basic auth only if username+password set; config fields url, username, password, verify | docs + .py | high | api
- Severity from labels.severity: critical->CRITICAL; error|high->HIGH; warning|medium->WARNING; info->INFO; low->LOW; missing/unknown->INFO | .py | high | api
- Status: firing->FIRING; resolved->RESOLVED; unknown->FIRING | .py | high | api
- Field map: name/id = incoming id if valid UUID else alertname label else UUID4; description = annotation description else summary; service = label service else annotation service; environment = label environment else "unknown"; labels/annotations stored with lowercased keys | .py | high | api
- Fingerprint taken from incoming Alertmanager `fingerprint` field (FINGERPRINT_FIELDS=["fingerprint"]); dedup follows Alertmanager fingerprint | .py | med | gotcha
- lastReceived = current UTC, not startsAt/endsAt | .py | med | gotcha
- `send_resolved: true` needed or Keep never sees RESOLVED | docs | high | gotcha
- Alertmanager sends one webhook per group with alerts[]; how Keep splits them NOT verified | docs | low | gotcha
- UNVERIFIED possible bug: incoming alert with an `id` key may raise TypeError (duplicate id kwarg) | .py (summariser flag) | low | gotcha
- Helm chart exposes svc/keep-backend 8080, svc/keep-frontend 3000, optional svc/keep-websocket 6001; in-cluster Alertmanager URL http://keep-backend.<ns>.svc:8080/alerts/event/prometheus plausible but NOT confirmed | https://docs.keephq.dev/deployment/kubernetes/installation | med | config
- Install: `helm repo add keephq https://keephq.github.io/helm-charts`; `helm install keep keephq/keep -n keep --create-namespace` | same | high | config

## Grafana
- Webhook path `KEEP_BACKEND_URL/alerts/event/grafana`; contact point type Webhook, header `X-API-KEY: <key>` | https://docs.keephq.dev/providers/documentation/grafana-provider | high | config
- Add child notification policy under Default policy with NO matchers; with matchers only matching alerts forwarded | same | high | gotcha
- Auto-setup contact point name `keep-grafana-webhook-integration`; use Test button | same | med | config
- No supported-version matrix. Unified Alerting default from Grafana 9.0; Grafana 8.x or legacy alerting needs legacy config (/api/alert-notifications). Nothing on 10/11/12 | same | med | version
- Provider auth fields (pull / auto-setup only): host, token (service account), optional datasource_uid; scopes alert.rules:read (mandatory), alert.provisioning:read/write | same | high | config
- Payload: unified alerts[] used; events with evalMatches = legacy: always CRITICAL, FIRING only if state=="alerting" | https://raw.githubusercontent.com/keephq/keep/main/keep/providers/grafana_provider/grafana_provider.py | high | api
- Severity from `severity` label critical|high|warning|info else INFO. Status: ok|resolved|normal->RESOLVED; paused->SUPPRESSED; alerting->FIRING; pending|no_data->PENDING | .py | high | api
- No labels required; service default "unknown"; environment from deployment_environment then environment then "unknown"; set a `severity` label or all alerts are INFO | .py | high | gotcha
- Fingerprint order: alert fingerprint, label fingerprint, SHA-256 of labels, hash of name+service | .py | med | gotcha
- setup_webhook detects version via /api/health; >9.4.7 uses authorization header, else API key as query param | .py | med | version

## Slack (notifications only)
- Config: `webhook_url` (sensitive) and optional `access_token` (OAuth via UI); validate_config fails if both empty; webhook wins if both set | https://docs.keephq.dev/providers/documentation/slack-provider + https://raw.githubusercontent.com/keephq/keep/main/keep/providers/slack_provider/slack_provider.py | high | config
- Incoming webhook is enough for channel-only posts, no scopes; webhook bound to one channel; code sends `channel` in payload, Slack honouring it NOT verified | same | high | config
- Workflow `with` keys: message, blocks, channel, slack_timestamp, thread_timestamp, attachments, username, notification_type; need at least one of message/blocks/attachments | .py + docs | high | api
- Bot token path: only chat:write named; `channel` required; needed only for thread replies, chat.update, reactions; OAuth needs SLACK_CLIENT_ID/SLACK_CLIENT_SECRET on backend; `reaction` requires access_token | .py | high | gotcha
- Interactive messages/edits only on OAuth path; avoidable with webhook-only | docs | med | gotcha
- UNVERIFIED code bug: non-dict/list attachments get assigned blocks value; use blocks/message | .py | low | gotcha
- Provisioning: `KEEP_PROVIDERS` (JSON string or file path) OR `KEEP_PROVIDERS_DIRECTORY` (YAML, "recommended"); both not allowed. Shape (paraphrase): {"<name>": {"type": "slack", "authentication": {"webhook_url": "..."}}} | https://docs.keephq.dev/deployment/provision/provider | high | config
- Webhook install default: KEEP_PROVIDERS installs unless install_webhook false; KEEP_PROVIDERS_DIRECTORY off unless install_webhook true; provisioned providers absent from config removed on restart | same | high | gotcha
- Workflows: `KEEP_WORKFLOWS_DIRECTORY` (YAML dir; add/re-provision/deprovision on restart); `KEEP_WORKFLOW` single env workflow also exists | https://docs.keephq.dev/deployment/provision/workflow + /overview | high | config
- Other: KEEP_DASHBOARDS, KEEP_MAPPINGS_DIRECTORY; no helm values for provisioning shown, use chart env/extraEnv (UNVERIFIED) | /overview | med | config

## Auth
- API key: UI profile (bottom-left) -> Settings -> Users and Access -> API Keys -> name, role `webhook` -> Create | search summary of https://docs.keephq.dev/providers/documentation/checkly-provider | med | config
- `AUTH_TYPE=NOAUTH` (not NO_AUTH): no login; any x-api-key accepted; JWT for tenant "keep" unvalidated; not for production | https://docs.keephq.dev/deployment/authentication/no-auth | high | config
- DB auth default admin keep/keep; env KEEP_DEFAULT_USERNAME, KEEP_DEFAULT_PASSWORD, KEEP_FORCE_RESET_DEFAULT_PASSWORD | https://docs.keephq.dev/deployment/authentication/db-auth | high | config

## Leads
- https://docs.keephq.dev/llms.txt; keephq/helm-charts values.yaml (env/extraEnv, backend svc name, default AUTH_TYPE); raw MDX docs in keep repo for verbatim YAML; Alertmanager webhook_config docs; Grafana webhook contact point docs.

## Not found
- Verbatim Alertmanager YAML; Grafana 10/11/12 matrix; official API-keys page; KEEP_API_KEY env var; in-cluster URL confirmation; Slack workflow YAML example; helm values for provisioning; official Alertmanager/Grafana docs (budget spent).

## Contradictions
- Auth style differs: Prometheus basic_auth, Grafana X-API-KEY header, others query param; Prometheus prose mentions "API token" but fields are username/password.
- Slack docs say webhook_url "required" but validate_config accepts either.
- Grafana docs tip "coming soon" vs documented workflow query step.
