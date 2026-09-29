#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f demo.yaml
kubectl -n demo wait --for=condition=available --timeout=60s deploy/demo-logger || true

cat <<'EOF'

==> Demo deployed. Cross-signal checks to run in Grafana (http://localhost:3000):

1) Traces in Tempo
   Explore → Tempo → "Search" tab → service.name="demo-app"
   You should see ~150 spans from the 30s, rate=5 job.

2) Logs in Loki — confirm filelog is picking up demo-logger stdout
   Explore → Loki → {k8s_namespace_name="demo"}
   You should see "demo log line" entries with k8s_pod_name, service_name labels.

3) Metrics in Prometheus — confirm hostmetrics + telemetrygen metrics flow
   Explore → Prometheus →   system_cpu_load_average_1m
                            gen_by_telemetrygen{service_name="demo-app"}

4) Correlation: pick any span in Tempo → "Logs for this span" button → should
   land in Loki filtered by the same service.name / pod.

5) Kubernetes events as logs:
   Explore → Loki → {k8s_resource_name=~".+"}
EOF
