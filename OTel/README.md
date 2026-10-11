# OTel Collector Migration — Local Lab (macOS / kind)

End-to-end implementation of the "unified ingestion via OTel Collector" plan from
the design issue. Walks you from an empty MacBook Air to a working LGTM stack
where logs, metrics, traces, and k8s events all flow through a two-tier
collector (agent DaemonSet + gateway Deployment).

## Topology — before vs after

**Before (fragmented):**

```
Apps ──► Prometheus (scrape)
Apps ──► Promtail ──► Loki
Apps ──► OTel SDK ──► Tempo
CloudWatch ──► YACE ──► Prometheus
k8s events ──► (not collected)
host metrics ──► (not collected)
```

**After (unified):**

```
                                 ┌──────────────────────────┐
Apps (OTLP) ───────────┐         │   OTel Gateway           │
                       ├────────►│   (Deployment)           ├──► Tempo  (traces)
Pod logs (filelog) ────┤         │   - k8sattributes        ├──► Loki   (logs)
Host metrics ──────────┤         │   - tail_sampling        ├──► Prom   (metrics, via RW)
Kubelet stats ─────────┘         │   - batch / memory_limit │
       (Agent DaemonSet)         └──────────────────────────┘
                                          ▲
k8s events / cluster metrics ─────────────┘
       (gateway-only receivers)
```

## Step-by-step

Each folder is one rollback unit. Run them in order; you can stop at any step
and still have a working stack.

| Step | Folder | What it does |
|------|--------|--------------|
| 0    | `00-prereqs/`         | Install Docker, kubectl, helm, kind on macOS |
| 1    | `01-cluster/`         | Create a 3-node kind cluster |
| 2    | `02-lgtm-stack/`      | Install Prometheus, Loki, Tempo, Grafana via Helm |
| 3    | `03-otel-collector/`  | Deploy collector in two tiers (agent + gateway) |
| 4    | `04-logs-migration/`  | Switch logs to filelogreceiver + k8seventsreceiver, retire Promtail |
| 5    | `05-metrics-migration/` | Add hostmetrics + kubeletstats + k8scluster receivers, ship via remote_write |
| 6    | `06-validation/`      | Deploy a sample app, verify trace ↔ logs ↔ metrics correlation |
| 7    | `07-prometheus-scrape-migration/` | (Optional) move scraping from Prometheus into the collector via `prometheusreceiver` + target-allocator |
| 8    | `08-yace-decision/`   | Pick a path for AWS CloudWatch metrics — keep YACE OR use `awscloudwatchreceiver` |

## Quick start

```bash
# from this folder
./00-prereqs/install-macos.sh
./01-cluster/up.sh
./02-lgtm-stack/install.sh
./03-otel-collector/install.sh
./04-logs-migration/apply.sh
./05-metrics-migration/apply.sh
./06-validation/deploy-demo.sh
```

Each `apply.sh` is idempotent — re-running it just upgrades the Helm release.

## Tearing down

```bash
kind delete cluster --name otel-lab
```

## References

- Collector deployment patterns: https://opentelemetry.io/docs/collector/deployment/
- opentelemetry-collector Helm chart: https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector
- Grafana LGTM correlation: https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/#trace-to-logs
