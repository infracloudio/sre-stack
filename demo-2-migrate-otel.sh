#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# demo-2-migrate-otel.sh
#
# Full OTel migration from the upstream infracloudio/sre-stack scope:
#   • Two-tier OTel Collector (Agent DaemonSet + Gateway Deployment)
#   • Loki 3.x switch (uninstall loki-stack → grafana/loki 7.0.0)
#   • Logs:    filelog (agent) + k8sobjects (gateway) → otlphttp/loki → Loki 3.x
#   • Metrics: hostmetrics+kubeletstats (agent) + k8s_cluster (gateway)
#              → prometheusremotewrite → Prometheus
#   • Traces:  app OTLP → agent → gateway → Tempo
#   • Prometheus scraping: prometheusreceiver with kubernetes_sd_configs
#   • k8sattributes processor on every pipeline for cross-signal correlation
#
# Prereq: demo-1-before.sh has run and the cluster is in the "before" state.
# Do NOT add --wait or --timeout to helm commands — causes failures on MacBook Air.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")"

NS=monitoring

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()          { echo; echo "══════════════════════════════════════════════════"; echo "▶  $*"; echo "══════════════════════════════════════════════════"; }
log_sub()      { echo "  ➜  $*"; }

wait_for_pod() {
  local label=$1 ns=${2:-$NS}
  echo "  Waiting for pod matching '$label' in $ns..."
  for i in $(seq 1 40); do
    if kubectl get pods -n "$ns" 2>/dev/null | grep "$label" | grep -q "Running"; then
      echo "  ✅ $label is Running"
      return 0
    fi
    sleep 5
  done
  echo "  ⚠️  $label not ready after 200s — continuing anyway"
}

wait_for_pod_gone() {
  local label=$1 ns=${2:-$NS}
  echo "  Waiting for '$label' to terminate in $ns..."
  for i in $(seq 1 20); do
    if ! kubectl get pods -n "$ns" 2>/dev/null | grep -q "$label"; then
      echo "  ✅ $label is gone"
      return 0
    fi
    sleep 3
  done
  echo "  ⚠️  $label still present after 60s — continuing"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Helm repos
# ─────────────────────────────────────────────────────────────────────────────
log "Step 1: Helm repo setup"
helm repo add open-telemetry        https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo add grafana               https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add prometheus-community  https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
log_sub "Repos ready"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Enable Prometheus remote_write receiver
#
# The OTel gateway ships metrics via prometheusremotewrite. Prometheus must
# accept remote_write pushes via --web.enable-remote-write-receiver.
# NOTE: prometheus-values.yaml already has enableRemoteWriteReceiver: true —
# this step re-applies it at the pinned chart version to avoid schema drift.
# ─────────────────────────────────────────────────────────────────────────────
log "Step 2: Enabling Prometheus remote_write receiver"
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "$NS" \
  --version 52.0.0 \
  --reuse-values \
  --set "prometheus.prometheusSpec.enableRemoteWriteReceiver=true"

sleep 5
wait_for_pod "prometheus-stack-kube-prom-prometheus"
log_sub "Prometheus remote_write receiver enabled"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Switch from Loki 2.x (loki-stack) to Loki 3.x (grafana/loki)
#
# loki-stack 2.10.3 ships Loki 2.9.3 which has no OTLP ingest endpoint at all.
# grafana/loki 7.0.0 ships Loki 3.6.7 with:
#   - OTLP ingest at /otlp/v1/logs
#   - allow_structured_metadata: true (stores OTel attrs alongside logs)
#   - tsdb/v13 schema (required for Loki 3.x)
# ─────────────────────────────────────────────────────────────────────────────
log "Step 3: Switching to Loki 3.x (grafana/loki chart 7.0.0)"

log_sub "Uninstalling loki-stack (removes Loki 2.x + Promtail)"
helm uninstall loki --namespace "$NS" 2>/dev/null || true
wait_for_pod_gone "promtail"

log_sub "Installing grafana/loki 7.0.0 → Loki 3.6.7 (SingleBinary + PVC)"
helm upgrade --install loki grafana/loki \
  --namespace "$NS" \
  --version 7.0.0 \
  --values monitoring/chart-values/loki-v3-values.yaml

sleep 10
wait_for_pod "loki-0"
kubectl get pods -n "$NS" | grep loki

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Deploy OTel Gateway (Deployment)
#
# Runs on o11y nodes. Receives OTLP from agents, enriches via k8sattributes.
# Fans out:
#   traces  → Tempo  (otlp/tempo  gRPC  :4317)
#   metrics → Prometheus (prometheusremotewrite /api/v1/write)
#   logs    → Loki 3.x (otlphttp/loki /otlp/v1/logs)
#
# Extra receivers on gateway only:
#   k8s_cluster  → cluster-state metrics (deployment desired/ready, pod phases)
#   k8sobjects   → k8s events as logs (CrashLoopBackOff, OOMKilled, etc.)
# ─────────────────────────────────────────────────────────────────────────────
log "Step 4: Deploying OTel Gateway (Deployment on o11y nodes)"
echo "  Presets  : kubernetesAttributes | kubernetesEvents | clusterMetrics"
echo "  Receivers: otlp | k8sobjects | k8s_cluster"
echo "  Exporters: otlp/tempo | prometheusremotewrite/prom | otlphttp/loki"
echo

helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "$NS" \
  --values monitoring/chart-values/otel-gateway-values.yaml

sleep 5
wait_for_pod "otel-gateway"
kubectl get pods -n "$NS" | grep otel-gateway

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — Deploy OTel Agent (DaemonSet)
#
# Runs on ALL nodes (tolerations: Exists — includes o11y-tainted nodes).
# Collects node-level signals and forwards to gateway:
#   filelog      → reads /var/log/pods/** (CRI format) — replaces Promtail
#   hostmetrics  → CPU / memory / disk / network per node  [NEW metric coverage]
#   kubeletstats → pod & container resource usage          [NEW metric coverage]
#
# k8sattributes preset stamps every record with pod/namespace/node/deployment.
# kubeletstats override: insecure_skip_verify=true — k3d kubelet cert has no IP SANs.
# ─────────────────────────────────────────────────────────────────────────────
log "Step 5: Deploying OTel Agent DaemonSet (one pod per node)"
echo "  Presets  : kubernetesAttributes | logsCollection | hostMetrics | kubeletMetrics"
echo "  Receivers: filelog | hostmetrics | kubeletstats"
echo "  Exporters: otlp → otel-gateway:4317"
echo

helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  --namespace "$NS" \
  --values monitoring/chart-values/otel-agent-values.yaml

sleep 5
wait_for_pod "otel-agent"
kubectl get pods -n "$NS" | grep otel

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Wire HotROD → OTel Gateway → Tempo
#
# Before : HotROD → Jaeger endpoint (Istio intercepts; only ingress hops in Tempo)
# After  : HotROD → OTel Gateway:4318 (OTLP HTTP) → Tempo
#          Each request creates 5+ spans: frontend / customer / driver / route / redis
# ─────────────────────────────────────────────────────────────────────────────
log "Step 6: Wiring HotROD → OTel Gateway → Tempo"
echo "  Before: HotROD → JAEGER_ENDPOINT (only Istio ingress hops visible)"
echo "  After : HotROD → OTEL_EXPORTER_OTLP_ENDPOINT=gateway:4318 (full app spans)"
echo

kubectl set env deployment/hotrod -n hotrod \
  JAEGER_ENDPOINT- \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway.monitoring.svc.cluster.local:4318

sleep 5
wait_for_pod "hotrod" "hotrod"
kubectl get pods -n hotrod

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — Generate traffic (both apps)
#
# Robot Shop: HTTP through Istio ingress → populates istio_requests_total
#             per service → Application Dashboard / Service Map works
# HotROD:     dispatches → full app spans in Tempo with k8s attributes
# ─────────────────────────────────────────────────────────────────────────────
log "Step 7: Generating traffic — Robot Shop + HotROD"

# Kill stale port-forward if HotROD pod restarted in Step 6
pkill -f "port-forward svc/hotrod" 2>/dev/null || true
lsof -ti:18080 | xargs kill -9 2>/dev/null || true
sleep 2
kubectl port-forward svc/hotrod -n hotrod 18080:8080 &
sleep 3

log_sub "Robot Shop — 40 requests across catalogue / user / cart"
echo "  These flow through Istio sidecars → istio_requests_total per service"
echo

for i in $(seq 1 40); do
  curl -s http://localhost:8080/api/catalogue/categories            > /dev/null || true
  curl -s "http://localhost:8080/api/catalogue/products/1"         > /dev/null || true
  curl -s "http://localhost:8080/api/catalogue/products/2"         > /dev/null || true
  curl -s http://localhost:8080/api/user/login \
    -H "Content-Type: application/json" \
    -d '{"name":"user","password":"password"}'                     > /dev/null || true
  curl -s http://localhost:8080/api/cart/items                     > /dev/null || true
  echo "  robot-shop $i/40"
  sleep 1
done

log_sub "HotROD — 20 requests (OTLP traces → Tempo with full app spans)"
echo

for i in $(seq 1 20); do
  curl -s "http://localhost:18080/dispatch?customer=123&nonse=$(python3 -c 'import random; print(random.random())')" > /dev/null || true
  echo "  hotrod $i/20"
  sleep 1
done

log_sub "Waiting 25s for Tempo to flush trace blocks..."
sleep 25

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — Enable Prometheus scraping via OTel Gateway
#
# Upgrades gateway to add a prometheusreceiver with kubernetes_sd_configs.
# Scrapes two targets via endpoint discovery:
#   - grafana            (metrics at /grafana/metrics)
#   - prometheus-self    (metrics at /metrics)
#
# NOTE: Target Allocator (automatic ServiceMonitor discovery) is not used here
# because the vanilla open-telemetry/opentelemetry-collector Helm chart does
# not support the targetAllocator key — it requires the OTel Operator CRDs.
# Direct scrape_configs achieves the same result for a known target set.
# ─────────────────────────────────────────────────────────────────────────────
log "Step 8: Enabling Prometheus scraping via OTel Gateway"
echo "  Adding prometheusreceiver with kubernetes_sd_configs"
echo "  Scrape targets: grafana + prometheus-self"
echo "  Results pushed to Prometheus via remote_write"
echo "  Job labels: monitoring/grafana, monitoring/prometheus-self"
echo

helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "$NS" \
  --values monitoring/chart-values/otel-gateway-prom-scrape-values.yaml

sleep 10
wait_for_pod "otel-gateway"
kubectl get pods -n "$NS" | grep otel-gateway

# ─────────────────────────────────────────────────────────────────────────────
# Final state
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║         OTel MIGRATION COMPLETE — VALIDATION GUIDE                  ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║                                                                      ║"
echo "║  ACCESS                                                              ║"
echo "║    Grafana    →  http://localhost:8080/grafana  (admin/prom-operator)║"
echo "║    Robot Shop →  http://localhost:8080                               ║"
echo "║    HotROD     →  http://localhost:18080                              ║"
echo "║                                                                      ║"
echo "║  APPLICATION DASHBOARDS (Robot Shop + Istio)                        ║"
echo "║    Application Dashboard → Service Map populated (robot-shop ns)    ║"
echo "║    Global Request Volume, per-service success/error rates visible    ║"
echo "║    Istio metrics: istio_requests_total per source/destination        ║"
echo "║                                                                      ║"
echo "║  TRACES  Grafana → Explore → Tempo → Search                         ║"
echo "║    HotROD spans: frontend / customer / driver / route / redis       ║"
echo "║    Click span → k8s.pod.name, k8s.namespace.name on every span      ║"
echo "║    Click 'Logs for this span' → jumps to correlated Loki logs       ║"
echo "║                                                                      ║"
echo "║  LOGS    Grafana → Explore → Loki                                   ║"
echo "║    {k8s_namespace_name=\"hotrod\"} → logs enriched with OTel attrs    ║"
echo "║    {k8s_namespace_name=\"robot-shop\"} → Robot Shop pod logs          ║"
echo "║    {k8s_namespace_name=\"monitoring\"} → infra + collector logs       ║"
echo "║                                                                      ║"
echo "║  METRICS  Grafana → Explore → Prometheus                            ║"
echo "║    system_cpu_time_seconds_total   → host metrics (OTel agent)      ║"
echo "║    k8s_deployment_desired          → cluster state (OTel gateway)   ║"
echo "║    container_cpu_usage_seconds_total → kubeletstats (OTel agent)    ║"
echo "║    up{job=\"monitoring/grafana\"}     → OTel Prometheus scraping       ║"
echo "║                                                                      ║"
echo "║  CROSS-SIGNAL CORRELATION                                           ║"
echo "║    Tempo: click span → 'Logs for this span' → Loki (same pod/time) ║"
echo "║    Tempo: click span → 'Metrics for this span' → Prometheus         ║"
echo "║    All signals share k8s attrs from k8sattributes processor         ║"
echo "║                                                                      ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  OTel Pods:"
kubectl get pods -n monitoring | grep otel | awk '{printf "║    %-66s║\n", $1" "$3}'
echo "║                                                                      ║"
echo "║  Loki:"
kubectl get pods -n monitoring | grep "^loki" | awk '{printf "║    %-66s║\n", $1" "$3}'
echo "║                                                                      ║"
echo "║  Robot Shop:"
kubectl get pods -n robot-shop | grep -v NAME | awk '{printf "║    %-66s║\n", $1" "$3}'
echo "╚══════════════════════════════════════════════════════════════════════╝"
