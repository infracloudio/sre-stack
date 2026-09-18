#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# demo-1-before.sh
# Tear down any existing cluster and build the BEFORE state:
#   k3d cluster (4 nodes) + Istio + Prometheus + Loki + Tempo
#   + Robot Shop (with Istio sidecars) + HotROD
#   NO OTel Collector.
#
# Run from: ~/Documents/Claude/Projects/sre-stack
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")"

NS=monitoring

log()     { echo; echo "══════════════════════════════════════════════════"; echo "▶  $*"; echo "══════════════════════════════════════════════════"; }
log_sub() { echo "  ➜  $*"; }

wait_for_pod() {
  local label=$1 ns=${2:-$NS}
  echo "  Waiting for pod matching '$label' in $ns..."
  for i in $(seq 1 60); do
    if kubectl get pods -n "$ns" 2>/dev/null | grep "$label" | grep -q "Running"; then
      echo "  ✅ $label is Running"
      return 0
    fi
    sleep 5
  done
  echo "  ⚠️  $label not ready after 300s — continuing anyway"
}

wait_for_job() {
  local job=$1 ns=${2:-robot-shop}
  echo "  Waiting for job '$job' in $ns..."
  for i in $(seq 1 40); do
    if kubectl get jobs -n "$ns" 2>/dev/null | grep "$job" | grep -q "1/1"; then
      echo "  ✅ job $job complete"
      return 0
    fi
    sleep 5
  done
  echo "  ⚠️  job $job not complete after 200s — continuing anyway"
}

# ─── 0. Nuke existing cluster ────────────────────────────────────────────────
log "Step 0: Deleting existing cluster (if any)"
k3d cluster delete sre-stack-local 2>/dev/null || true

# ─── 1. Create k3d cluster ───────────────────────────────────────────────────
log "Step 1: Creating k3d cluster (4 nodes)"
k3d cluster create sre-stack-local \
  --agents 3 \
  --k3s-arg "--disable=traefik@server:*"

# Node roles:
#   agent-0, agent-1 → observability (tainted so only monitoring stack runs here)
#   agent-2          → app workloads (Robot Shop + HotROD)
kubectl label nodes k3d-sre-stack-local-agent-0 k3d-sre-stack-local-agent-1 workload=o11y
kubectl taint nodes k3d-sre-stack-local-agent-0 k3d-sre-stack-local-agent-1 o11y=true:NoSchedule
kubectl label nodes k3d-sre-stack-local-agent-2 workload=app

# Raise inotify limits — prevents spurious pod restarts under heavy log load
for node in agent-0 agent-1 agent-2 server-0; do
  docker exec k3d-sre-stack-local-${node} \
    sysctl -w fs.inotify.max_user_instances=8192 fs.inotify.max_user_watches=524288 2>/dev/null || true
done

kubectl apply -f ./infra/local/gp2-storageclass.yaml
log_sub "Cluster ready"

# ─── 2. Monitoring stack (no OTel) ───────────────────────────────────────────
log "Step 2: Installing monitoring stack (Prometheus + Grafana + Loki + Tempo)"

log_sub "kube-prometheus-stack"
make setup-kube-prometheus-stack

log_sub "Loki + Promtail (old stack — will be replaced in demo-2)"
make setup-loki

log_sub "Tempo"
make setup-tempo

log_sub "Zipkin service → bridges Istio traces to Tempo"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: zipkin
  namespace: monitoring
spec:
  selector:
    app.kubernetes.io/name: tempo
  ports:
  - name: zipkin
    port: 9411
    targetPort: 9411
EOF

# ─── 3. Istio ────────────────────────────────────────────────────────────────
log "Step 3: Installing Istio service mesh"
make setup-istio

log_sub "Applying Istio observability addons + dashboards"
make setup-istio-o11y-addons
make setup-dashboards

# ─── 4. Robot Shop ───────────────────────────────────────────────────────────
log "Step 4: Deploying Robot Shop (with Istio sidecar injection)"
log_sub "Using local override values — single replica, all pods on workload=app node"
echo
echo "  Override file: app/robot-shop/robot-shop-local-values.yaml"
echo "  Key overrides:"
echo "    replicas: 1 (all services, avoids anti-affinity on single-node app tier)"
echo "    nodeSelector: workload=app for all services (no persistent node in local cluster)"
echo "    affinity: {} (removes required podAntiAffinity)"
echo

kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -

# Enable Istio sidecar injection — this is what populates istio_requests_total
# and makes the Application Dashboard / Service Map work
kubectl label namespace robot-shop istio-injection=enabled --overwrite

helm upgrade --install roboshop -n robot-shop --create-namespace \
  ./app/robot-shop/helm/ \
  --values ./app/robot-shop/robot-shop-local-values.yaml \
  --set mysql_root_password=docdb3421z

# Apply Istio gateway + virtual services for Robot Shop
kubectl apply -f ./app/robot-shop/Istio/gateway.yaml -n robot-shop

log_sub "Waiting for Robot Shop pods to start (MySQL + MongoDB take longest)..."
sleep 20

# Wait for key pods
wait_for_pod "web" "robot-shop"
wait_for_pod "catalogue" "robot-shop"
wait_for_pod "user" "robot-shop"
wait_for_pod "cart" "robot-shop"

log_sub "Waiting for MySQL seeder job to complete..."
wait_for_job "mysql-seeed" "robot-shop"

echo
kubectl get pods -n robot-shop
echo

# ─── 5. HotROD ───────────────────────────────────────────────────────────────
log "Step 5: Deploying HotROD (traces via Jaeger endpoint — before OTel)"
log_sub "HotROD namespace has NO Istio injection — it bypasses the mesh deliberately"
make setup-hotrod
sleep 10
wait_for_pod "hotrod" "hotrod"

# ─── 6. Port-forwards ────────────────────────────────────────────────────────
log "Step 6: Starting port-forwards"

pkill -f "port-forward svc/istio-ingressgateway" 2>/dev/null || true
pkill -f "port-forward svc/hotrod"               2>/dev/null || true
lsof -ti:8080,18080 | xargs kill -9 2>/dev/null  || true
sleep 2

# Single Istio port-forward handles both Grafana (/grafana) and Robot Shop (/)
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 &
kubectl port-forward svc/hotrod -n hotrod 18080:8080 &
sleep 3

# ─── 7. Warm up traffic ──────────────────────────────────────────────────────
log "Step 7: Generating initial traffic to populate Istio metrics"
log_sub "30 Robot Shop requests → istio_requests_total appears in Prometheus"
echo

for i in $(seq 1 30); do
  curl -s http://localhost:8080/api/catalogue/categories  > /dev/null || true
  curl -s http://localhost:8080/api/catalogue/products/1  > /dev/null || true
  curl -s "http://localhost:8080/api/user/login" \
    -H "Content-Type: application/json" \
    -d '{"name":"user","password":"password"}' > /dev/null || true
  echo "  sent $i/30"
  sleep 1
done

log_sub "5 HotROD requests (Jaeger-style traces, no app spans yet)"
for i in $(seq 1 5); do
  curl -s "http://localhost:18080/dispatch?customer=123&nonse=$RANDOM" > /dev/null || true
  echo "  hotrod $i/5"
  sleep 1
done

# ─── Done ────────────────────────────────────────────────────────────────────
echo
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  BEFORE STATE IS READY                                              ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Grafana      →  http://localhost:8080/grafana                      ║"
echo "║                  login: admin / prom-operator                       ║"
echo "║  Robot Shop   →  http://localhost:8080                              ║"
echo "║  HotROD       →  http://localhost:18080                             ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  WHAT TO SHOW (before state — limitations):                         ║"
echo "║                                                                      ║"
echo "║  ✅ Application Dashboard → Istio service map for robot-shop        ║"
echo "║     namespace visible, request rates from Istio sidecars            ║"
echo "║                                                                      ║"
echo "║  ❌ Explore → Prometheus → system_cpu_time_seconds_total            ║"
echo "║     No results. Host CPU invisible (no OTel agent yet)              ║"
echo "║                                                                      ║"
echo "║  ❌ Explore → Prometheus → k8s_deployment_desired                   ║"
echo "║     No results. k8s cluster state invisible (no OTel gateway yet)   ║"
echo "║                                                                      ║"
echo "║  ❌ Explore → Tempo → Search                                         ║"
echo "║     Istio ingress hops only (1–2 spans). No app-level spans.        ║"
echo "║     Cannot see Redis calls, DB calls, root cause of latency.        ║"
echo "║                                                                      ║"
echo "║  ❌ Explore → Loki → {namespace=\"robot-shop\"}                        ║"
echo "║     Logs exist but NO trace_id field — cannot link log → trace      ║"
echo "║                                                                      ║"
echo "║  When done showing limitations, run:                                ║"
echo "║    ./demo-2-migrate-otel.sh                                         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
