# Data Model: Demo Applications for AKS Observability

**Note on provenance**: A separate `/speckit-plan` session proposed a version of this document containing two claims that don't match the real files or the live cluster: "3 replicas per service" (contradicts FR-006 and the actual pod list) and "HotROD has no nodeSelector, runs on default scheduler" (contradicts `app/hotrod/base/hotrod/deployment.yaml`, which sets one explicitly). This version is written from the real chart/manifest files and `research.md`, with citations, not from that session's transcript.

## Entities & Configurations

### 1. Robot Shop Application (Helm release)

| Field | Value | Notes |
|---|---|---|
| **Chart name / version** | `robot-shop` / `1.1.0` | `app/robot-shop/helm/Chart.yaml`, read directly |
| **Release name (per `.env`)** | `roboshop` | `.env:39` — `APP_RELEASE_NAME=roboshop`. Research used `robot-shop` manually since the makefile target was disabled; must be reconciled before implementation (see plan.md "Open items") |
| **Namespace** | `robot-shop`, label `istio-injection=enabled` | Set by the (currently commented-out) `setup-robot-shop` target; applied manually in research |
| **Services** | `web`, `cart`, `catalogue`, `payment`, `ratings`, `shipping`, `user`, `dispatch` | Confirmed via live pod list, one pod per service |
| **Replica count** | **1 per service on AKS**, not 3 | `values.yaml` defaults each service's `replicas:` to `3`, but every Deployment template (confirmed directly in `cart-deployment.yaml:8-12`) gates on `{{- if eq .Values.stack_mode "eks" }} replicas: {{ .Values.X.replicas }} {{- else }} replicas: 1 {{- end }}`. `stack_mode=aks` takes the `else` branch → 1 replica. Matches FR-006 exactly; `values.yaml`'s `3` is the EKS-only production-sized default, not a bug. |
| **Pod placement (app services)** | `nodeSelector: workload: app` | `values.yaml` per-service blocks, e.g. lines 58-59, 77-78, etc. — confirmed present for every app-tier service |
| **Resource requests/limits (app services)** | `cart`, `catalogue`, `dispatch`, `payment`, `ratings`, `user`, `web`: requests `100m CPU / 50Mi`, limits `200m CPU / 100Mi`. `shipping` is the one exception: requests `100m / 1Gi`, limits `200m / 2Gi` (memory-heavy, likely for its distance-calculation logic). | Read directly from `values.yaml` per-service `resources:` blocks — closes the gap FR-006 requires ("exact requests/limits determined during Phase 0 research based on actual measurements"), not previously captured in this document despite plan.md's Constitution Check claiming full Principle VIII citation coverage. |
| **Resource requests/limits (datastores)** | `mysql`: requests `100m / 700Mi`, limits `200m / 1024Mi`. `rabbitmq`: requests `500m / 2Gi`, limits `1 CPU / 2Gi`. `mysqlseeder`: requests `100m / 500Mi`, limits `200m / 1Gi`. `mongodb`: requests `100m / 100Mi`, limits `200m / 200Mi`. `redis`: requests `100m / 50Mi`, limits `200m / 100Mi`. | **Correction**: an earlier pass of this table claimed `mongodb`/`redis` had no resource limits at all. That was wrong — `values.yaml` has no `mongodb.resources`/`redis.resources` key, but both templates (`mongodb-deployment.yaml:26-32`, `redis-statefulset.yaml:30-36`) hardcode requests/limits directly in the container spec, unlike every other service which pulls them from `values.yaml` via `{{ toYaml .Values.X.resources }}`. Confirmed by reading both templates directly. Effective result is the same (both are resource-constrained); the only real gap is the inconsistent configuration pattern, not a missing limit — accepted as-is for this story, not a functional issue. |

### 2. Robot Shop in-cluster datastores

| Datastore | Placement | Storage | Notes |
|---|---|---|---|
| **MySQL** | `nodeSelector: workload: persistent`, toleration `persistent=true:NoSchedule` | `StorageClass: gp2`, `1Gi` (`values.yaml` `mysql:` block) | Templates (`mysql-statefulset.yaml`, `mysql-config.yaml`, `mysql-secret.yaml`, `mysql-service.yaml`, `mysql-seeed-job.yaml`) originally gated on `eq .Values.stack_mode "local"` — a defect (research.md §4b) fixed in this story's plan to `ne .Values.stack_mode "eks"`, so it now renders for `aks` too. Placement config itself was already correct before the fix — only the render condition was wrong. |
| **MongoDB** | `nodeSelector: workload: persistent` | Chart-managed, no separate finding | Not independently defect-tested in research; placement label present in `values.yaml`, same pattern as MySQL/RabbitMQ |
| **RabbitMQ** | `nodeSelector: workload: persistent` | Chart-managed | Higher memory allocation (`2Gi`) per `values.yaml`; used by `dispatch`/`payment` for async messaging. `rabbitmq-service.yaml` had the same chart defect as MySQL (T027, found during real Loki log verification) — gated on `eq "local"`, never rendering the `rabbitmq-cluster` Service on `aks`, so `dispatch` silently retried forever (`dial tcp: lookup rabbitmq-cluster ... no such host`) without the pod ever going unhealthy. Fixed to `ne "eks"`, same as T002; verified live post-fix (`Rabbit MQ ready true` in `dispatch` logs). |
| **Redis** | `nodeSelector: workload: persistent` | `StorageClass: gp2` (StatefulSet, `redis-0` observed live) | Session/cache store |

**Known open defect**: the seed-data Job (`mysql-seeed-job.yaml`) hangs indefinitely when run by the unmeshed `mysql-seeder` pod against the meshed `mysql-0` StatefulSet — reproducible, root cause not confirmed (research.md §4d). Does not block the store's own function (verified live: homepage, product page, cart, checkout all work without seed data); `ratings.cities` table remains empty.

**Resolved defect (T027)**: `rabbitmq-service.yaml`'s render condition was wrong the same way MySQL's was (T002) — found only because T014's real-log re-verification surfaced the connection errors; pod-status checks alone (`dispatch` staying `2/2 Running`) never caught it. Fixed and verified live; see tasks.md T027.

### 3. HotROD Application (Kustomize)

| Field | Value | Notes |
|---|---|---|
| **Manifests** | `app/hotrod/kustomization.yaml`, `namespace.yaml`, `base/hotrod/{deployment,service,kustomization}.yaml` | Read directly |
| **Namespace** | `hotrod` | `namespace.yaml` |
| **Replica count** | 1 | `base/hotrod/deployment.yaml:8` — `replicas: 1`, no conditional (single mode for this app, unlike Robot Shop) |
| **Pod placement** | `nodeSelector: workload: app` | **Confirmed by reading `base/hotrod/deployment.yaml` lines 39-40 directly** — explicitly set, not left to the default scheduler. (A separate session incorrectly claimed no `nodeSelector` was set; this is the corrected, verified fact.) |
| **Resources** | `100m CPU / 100M memory`, both requests and limits | `deployment.yaml:32-38` — already minimal, no fix needed |
| **Telemetry dependency** | `OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector.monitoring:4318` | `deployment.yaml:23-24`. This collector is installed by `setup-optional-otel`, which is **not** in `setup-observability`'s dependency chain (research.md §5) — a real gap this plan's Approach closes by making it explicit. |
| **Container image** | `jaegertracing/example-hotrod:latest` | Upstream, unpinned — pre-existing, not introduced by this story |

### 4. External reachability (FR-011) — Gateway & VirtualService resources

| Field | Robot Shop | HotROD |
|---|---|---|
| **Manifest** | `app/robot-shop/Istio/gateway.yaml` (unchanged, reused) | `app/hotrod/istio-gateway.yaml` (new, added by this story) |
| **Gateway name** | `robotshop-gateway` | `hotrod-gateway` |
| **Host binding** | `"*"` (wildcard — accepts any hostname) | `hotrod.demo.local` (host-scoped, deliberately not `"*"`) |
| **Routes to** | `web.robot-shop.svc.cluster.local:8080` | `hotrod.hotrod.svc.cluster.local:8080` |
| **Selector** | `istio: ingressgateway` (shared with HotROD) | `istio: ingressgateway` (shared with Robot Shop) |

**Why HotROD is host-scoped, not wildcard**: both `Gateway` objects share the same underlying `istio-ingressgateway` Service/selector. Two `VirtualService` objects both matching `hosts: "*"` on the same gateway would collide (ambiguous routing for the same request). Giving HotROD a specific host avoids this — verified live: `curl http://<ingress-IP>/` reaches Robot Shop, `curl -H "Host: hotrod.demo.local" http://<ingress-IP>/` reaches HotROD, both `200 OK`, no interference. This satisfies FR-011's "cannot interfere with the other's" requirement directly.

**Path-prefix rewriting was considered and rejected**: untested and risks breaking HotROD's internal asset links (its frontend likely assumes root-path `/`), whereas host-based routing requires no rewriting at all.

### 5. Shared infrastructure (not owned by this story)

| Field | Value | Notes |
|---|---|---|
| **Istio ingress Service** | `istio-ingressgateway`, namespace `istio-system`, type `LoadBalancer` | Installed by story 003; this story only adds routes to it, does not modify it |
| **External IP** | Assigned by Azure at cluster-creation time (observed: `135.224.177.246`, will differ per cluster) | `kubectl get svc -n istio-system istio-ingressgateway` |
| **StorageClass** | `gp2` (Azure disk provisioner) | Installed by story #97; confirmed present and used by MySQL/Redis PVCs |
| **Monitoring stack** | Prometheus, Grafana, Loki, OTel Collector (via `setup-optional-otel`), Beyla, Caretta — namespace `monitoring` | Installed by story #101/observability work; this story's apps are consumed by it, not part of it |

**Relationships**:
- Both app namespaces (`robot-shop`, `hotrod`) carry `istio-injection=enabled`, so their pods get an `istio-proxy` sidecar automatically — this is what makes them visible to Prometheus/Grafana/Loki without extra configuration (FR-009), and what makes host-based `VirtualService` routing work.
- Both apps' `Gateway` resources bind to the same shared `istio-ingressgateway`, distinguished only by `VirtualService` host matching — no new LoadBalancer or ingress infrastructure is created by this story.
- MySQL's seed-data Job depends on the MySQL `Service`/`StatefulSet` existing first (`docker-compose-wait` pattern) — currently the one link in this chain that doesn't complete (see Known open defect above).

**State**: Robot Shop is "ready" when all 8 app-service pods plus 4 datastore pods reach `Running`. HotROD is "ready" when its single pod reaches `1/1 Running` (verified: takes well under a minute, no dependencies beyond the OTel collector existing). Both are "reachable" (FR-011) when their respective `curl` checks return `200`.
