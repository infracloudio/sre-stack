# Delivery slices (proposed story order)

Each slice becomes one sub-issue of epic #91, sized at 1 to 2 days, and can be demoed on its own. "Needs" lists the slices it depends on. Problem, Outcome, Out of scope and Must keep working get written when each story is filed (`write-intent`).

Order: 1 and 2 in parallel → 3 → 4 → 5a → 5b → 6a → 6b → 7. That makes 9 main stories.

| # | Slice | Capabilities | Needs | Demo on its own |
|---|---|---|---|---|
| 1 | Robot-shop alert rules, payment latency threshold tuned and recorded | CAP-2 | none | Cart OOM fault: OOM, restart, unavailable-replica and 5xx alerts fire on the Prometheus Alerts page; quiet for 30 min under load with no fault |
| 2 | Install Keep: `setup-keep`, secrets check, telemetry off, o11y pool, gp2, chart images pinned; wired into `setup-aks`, where it is skipped with a message when secrets are missing | CAP-1 | none | `make setup-keep` on AKS; UI through port-forward; a missing secret stops it; `make setup-aks` without secrets still finishes |
| 3 | Alertmanager on (AKS overlay only), sending only to Keep; broken Slack setting removed from the shared values | CAP-3 | 1, 2 | OOM fault: alerts appear in Keep and resolve after revert |
| 4 | Correlation rule created by an idempotent `POST /rules` script, run by `setup-keep` | CAP-4, CAP-7 | 3 | OOM fault: exactly one incident; it closes on its own; re-running adds no duplicate rule |
| 5a | Slack and Fireworks providers built from the secrets file into our own Secret (`KEEP_PROVIDERS`), plus the opened-incident summary workflow as a repo file | CAP-5, CAP-7 | 4 | OOM fault: summary in Slack within 2 min; providers survive uninstall and reinstall; no secret in any repo or values file |
| 5b | Resolved message: workflow triggered on incident updated; the Slack action runs only if status is resolved and a marker is not yet set, and sets it | CAP-5, CAP-7 | 5a | After revert, exactly one resolved message in Slack, not one per update |
| 6a | Login (`AUTH_TYPE=DB`) and real API key seeded with `KEEP_DEFAULT_API_KEYS` | CAP-6 | 3, 4, 5b | Login required through port-forward; a made-up API key is rejected; Alertmanager alerts still arrive with the real key |
| 6b | Own address `keep.demo.local` for UI and websocket (AD-010), listed in `get-service-endpoints` | CAP-6 | 6a | Login page at the listed address; live updates without refresh |
| 7 | One-take demo: README section, diagram, screenshots, scenario ends by pointing at Keep and Slack | CAP-8 | 5b, 6b | Newcomer runs the success signal from the README |

Later, lower priority, each its own story after the main nine: Grafana alerts (CAP-9, needs 3), incident summary with Kubernetes events (CAP-10, needs 5a), Loki log alerts (CAP-11, needs 3), AI Summary button investigation (CAP-12, needs 2).

Notes:
- The route (6b) never goes live before the login (6a).
- Live checks the architecture decisions hand to stories: story 2 (image pins, a hook image with a shell, `MYSQL_ROOT_PASSWORD_FILE` on the pinned MySQL, AD-013); story 3 (the seeded webhook key and the before-and-after render, AD-009, AD-012); story 6a (the DB login, AD-009); story 6b (the `/websocket/app/` route, AD-010). If a check fails beyond its fallback, stop and come back to the spec.
- Stories 2 to 5b run Keep under `NOAUTH`, reached only by port-forward.
