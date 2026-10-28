# Architectural Decisions

*Decisions made in this repository that others (and our future selves) will
need to read again. One entry per decision, newest at the bottom. Entries
span stories and specs — a decision made for one setup often applies to
every cluster target. Simple language on purpose; each entry answers: what
we chose, why, and what we gave up.*

## AD-001 — Keep the `gp2` storage-class alias on Azure

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: review of
`specs/001-azure-aks-setup/plan.md:38` (PR 98, comment thread on the gp2
storage setting)

### What was proposed

Drop the `gp2` StorageClass from the Azure setup, and split the application
helm charts so each cloud (AWS and Azure) carries its own copies. On Azure
the charts would then point straight at AKS's built-in disk classes (for
example `managed-csi`), so no alias with the AWS-style name would be needed.

### Why we didn't

Three reasons, in the order a reviewer should weigh them:

1. **Removing it breaks the workload contract, not just one file.** Every
   workload asks for a storage class named `gp2` — `app/robot-shop/helm/
   values.yaml` (mysql, redis), `templates/rabbitmq-deployment.yaml`, and
   `monitoring/grafana-postgres/statefulset.yaml`. No class of that name on
   an Azure cluster means every PVC lands `Pending` and the apps never come
   up. The alias is a 4-line manifest; the "removal" PR would have to touch
   charts, hardcoded templates, and the workload contract to get the same
   job done. Fewer files is not less work here.
2. **It drifts from this story's spec.** The accepted spec (US1) describes
   an *empty cluster* that mirrors Amazon's shape precisely so that the
   existing application and observability manifests deploy unchanged.
   Splitting the charts per cloud reopens the workload contract — a
   different work item, not a plan tweak inside a cluster-setup story.
3. **It breaks the constitution.** Principle V ("Workload Placement
   Contract") requires every new cluster target to reproduce the `gp2`
   storage-class alias so manifests deploy unchanged. Skipping it on Azure
   needs a constitution amendment approved in its own PR — with its own
   evidence — not a side effect of this story.

### The chart-split part

Separate charts per cloud remain a good idea, but this story has no
running AWS environment to regress against, so chart changes here cannot
prove "nothing on Amazon broke". That belongs to its own story: split the
charts, point Azure at AKS's built-in `managed-csi`, retire the `gp2` alias
target by target, and amend constitution V in the same PR.

### Keep-alive caveat for that future story

`app/robot-shop/helm/templates/rabbitmq-deployment.yaml:35` hardcodes
`storageClassName: gp2` and ignores its own values key. Any chart-split
story must fix that template — it is latent AWS drift already.

## AD-002 — Cost-first pool mode: prefer spot, fall back on-demand, refuse if neither fits

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: review of
`specs/001-azure-aks-setup/plan.md:64` (PR 98: "cost minimization as
guiding light", "use spot unless blocked").

### Decision

Before anything is created, the shared helper (`infra/scripts/cluster/
azure-common.sh`) reads the region's machine allowance (`az vm list-usage`)
and picks a deployment mode for the four workload pools:

1. **Spot preferred**: if the subscription's spot vCPU allowance in the
   chosen location fits the whole designed shape (26 spot vCPU at minimum
   counts — app 6, persistent 8, o11y 8, loadgen 4), all four workload
   pools are created as spot machines. All-or-nothing: no mixed pools.
2. **On-demand fallback**: if spot does not fit, the helper checks the
   regular vCPU allowances per machine family (DSv5 needs 22, FSv2 needs 4).
   If every family fits, the pools are created as regular machines.
3. **Refuse**: if neither fits, the start command stops before creating
   anything, and the message names the short allowance and how to fix it
   (raise the quota, free machines, or pick a different location). Nothing
   is half-created by a quota problem — that is the FR-005/FR-011 rule.

The system pool is always regular: Azure requires the first pool on a
cluster to be a non-spot system pool regardless of allowance.

### Why this shape

- Spot is the cheaper option whenever the region's spot allowance allows
  it, which answers the review's cost guidance without changing the
  designed cluster shape (sizes, counts, labels, taints stay in the
  data-model §3 table).
- All-or-nothing per mode keeps verification simple: the check report can
  state one mode and compare every pool against it.
- The fallback (not a hard error) keeps the cluster creation-able for
  people whose subscription has no spot room — a smaller bill was the
  goal, never a blocked deployment.
- The choice is made once, before creation, from a documented command
  shape — the same check-rather-than-guess pattern every other pre-check
  in the helper uses.

## AD-003 — Workload manifests need a toleration for Azure's spot auto-taint

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: T010 review
discussion (`specs/001-azure-aks-setup/tasks.md`, Phase 3; grounding in
`specs/001-azure-aks-setup/data-model.md` §3 and research.md fact 5).

### Decision

Any workload manifest that targets the four workload pools **when they run
in spot mode** (`AZURE_POOL_MODE=spot`, AD-002) must carry one extra
toleration for the taint Azure automatically adds to every spot node:

```yaml
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
```

AWS (eksctl) adds no such taint, so this is Azure-only glue: a spot pool on
Azure is UnSchedulable for pods without it, exactly like the designed
taints (`persistent=true:NoSchedule` etc.) already are. The verified
cluster keeps the taint; the verify script excludes this one taint from
its per-pool comparison and flags any other unexpected taint.

### Why

- The taint is Azure's own mechanic for reclaiming spot machines, not a
  cluster-design decision. Blocking creation of spot pools to dodge it
  (or un-tainting spot nodes, which Azure does not support) would give up
  the cost benefit AD-002 was built for.
- The data-model pools already run with NoSchedule taints and every
  workload manifest is written to tolerate those one-per-pool; adding one
  Azure-only toleration keeps that pattern ("taint + matching toleration")
  instead of a special case.

### What we gave up / consequences

- **Workload manifests stop being 100% provider-agnostic in spot mode.**
  A manifest without the toleration deploys fine on eks/local and on a
  *regular-mode* aks cluster, but cannot schedule on a *spot-mode* aks
  cluster. Cost-first mode therefore quietly requires this manifest
  change; no script can fix it for the workload.
- **On-demand-mode escape hatch documented**: today's subscription has
  3/26 spot vCPU, so the helper picks `regular`, no auto-taint exists, and
  manifests need nothing extra. The flip to spot (quota raised, new
  cluster shape version) is the moment every workload story must check
  this toleration — it is recorded in data-model §3 so the next stories
  inherit the requirement rather than rediscovering the failure as
  `Pending` pods on the nodes.

## AD-004 — Amazon non-regression is proven by diff and lint, not a live AWS run

**Date**: 2026-09-10 · **Status**: Accepted · **Raised by**: story-owner
review of Phase 5 (`specs/001-azure-aks-setup/tasks.md`, T019).

### Decision

The Azure story's non-regression promise (`spec.md`, User Story 3) is proven
by two checks that need no cloud account:

1. The untouched-files guard (T017): the branch diff against its merge-base
   shows no change under `infra/eksctl.yaml`, the eks/local script paths,
   `app/`, `monitoring/`, `scenarios/`, or `infra/local/`, beyond the two
   documented dispatch edits in `setup-cluster.sh` and `cleanup-cluster.sh`.
2. `make lint` (T018) passing unchanged: hooks, secrets, protected paths,
   shell/YAML lint, Spec Kit version, loom drift.

The intended live confirmation — a person with Amazon access running
`make setup` and `make cleanup` with `STACK_MODE=eks` — is dropped because
no such person is available to this story.

### Why

- A live run nobody can perform is not evidence; it is a task that keeps the
  story open forever.
- The Azure work touches no Amazon/local behaviour except the two dispatch
  edits, and the diff guard checks exactly that, file by file.
- The lint gate, the pre-commit hooks, and CI already run on every change,
  so a silent regression would have to survive all of them first.

### What we gave up

- No live end-to-end proof from *this* branch that the Amazon path still
  creates and deletes. The exposure is small — the eks/local bodies are
  byte-identical and the dispatch change only routes `STACK_MODE` — but it
  is real. The next person who touches the eks path should run
  `make setup` and `make cleanup` once on a real account and report back.

## AD-005 — Host-based `VirtualService` routing, not per-app gateways or path rewriting

**Date**: 2026-09-23 · **Status**: Accepted · **Raised by**: architect
review of `specs/004-deploy-demo-apps-aks/spec.md` (added FR-011: Robot
Shop and HotROD must both be externally reachable and must not interfere
with each other).

### Decision

Robot Shop and HotROD share the one Istio ingress gateway
(`istio-ingressgateway` in `istio-system`) already installed for the
cluster. They are told apart by `VirtualService` host matching, not by
separate infrastructure:

- Robot Shop's existing `Gateway`/`VirtualService`
  (`app/robot-shop/Istio/gateway.yaml`) keeps `hosts: "*"` — reachable at
  the ingress IP directly, no header needed.
- HotROD gets a new `Gateway`/`VirtualService`
  (`app/hotrod/istio-gateway.yaml`), scoped to `hosts: "hotrod.demo.local"`
  — reachable only with a matching `Host` header
  (`curl -H "Host: hotrod.demo.local" http://<ingress-IP>/`).

Both bind the same `Gateway` selector (`istio: ingressgateway`), so no new
`LoadBalancer` Service or ingress class is created.

### Alternatives considered and rejected

1. **A second dedicated ingress gateway/LoadBalancer for HotROD.** Rejected:
   doubles the number of cloud LoadBalancer Services (and their cost) for a
   demo stack that has no scaling or isolation requirement between the two
   apps — nothing in spec.md's user stories asks for that separation.
2. **Path-prefix rewriting on one wildcard host** (e.g. `/hotrod` routed to
   HotROD, `/` to Robot Shop). Rejected: untested against HotROD's own
   frontend, which likely assumes it is served from root path `/` for its
   static asset links; rewriting risks breaking the UI in a way that would
   only surface after deploying, with no fallback if it did.
3. **Two wildcard `hosts: "*"` `VirtualService` entries on the same
   gateway.** Rejected outright, not just deprioritized: both would match
   every request with no way for Istio to disambiguate, so one app would
   silently swallow the other's traffic depending on config-apply order —
   verified live during this story's research (`research.md` §7) before
   settling on the host-scoped approach.

### Why this shape

- Host-based matching is a supported, first-class Istio routing mechanism
  purpose-built for exactly this — multiple backends behind one gateway —
  so it needs no new manifests beyond one more `Gateway`/`VirtualService`
  pair.
- No rewriting means no risk to HotROD's internal links; the app is served
  exactly as its own manifests expect.
- Verified live: `curl http://<ingress-IP>/` reaches Robot Shop and
  `curl -H "Host: hotrod.demo.local" http://<ingress-IP>/` reaches HotROD,
  both `200 OK`, with no observed interference either direction.

### What we gave up

- HotROD is only reachable with the `Host` header set (via `curl -H`,
  `/etc/hosts` entry, or a browser extension) since `hotrod.demo.local`
  resolves nowhere by default — there is no public DNS record for it. This
  is acceptable for an internal demo/POC stack; a real external hostname
  would need its own DNS entry, which is out of scope for this story.

## AD-006 — AKS observability: platform reuse over more installs

**Date**: 2026-10-05 · **Status**: Accepted · **Raised by**:
`specs/002-azure-observability-stack` (plan.md Approach items 1–7,
research.md findings 12–16, spec Clarifications of 2026-09-15 and
2026-10-05).

### Decision

The AKS monitoring path (`make setup-aks-o11y` and its constituent
targets) reuses what the platform or the repo already provides rather than
installing more of it. Six choices, each traced to its evidence:

1. **Skip `setup-metric-server` on AKS.** AKS's built-in metrics-server
   addon already serves the standard `metrics.k8s.io` API
   (research.md L2: 2/2 Running, standard `ClusterRole
   system:metrics-server` owned by Azure's addon manager), and installing
   a second one collides on that exact ClusterRole — proven live in
   `specs/004-deploy-demo-apps-aks/research.md` §6. The AKS chain omits
   the target rather than fighting an addon-manager-reconciled resource.
2. **Reuse Kiali's existing manifest unmodified.** The shared pre-rendered
   `monitoring/istio-observability-addons/kiali.yaml` (chart
   `kiali-server-1.63.1`, image `v1.63`) runs healthy against AKS's
   Istio 1.30.4 — verified live (research.md L3/L4: pod Running on an
   `o11y` node, `200 OK` through `robotshop-gateway`) — so story 002 adds
   only AKS wiring and the mesh-readiness gate (`make setup-aks-kiali`
   refuses when istiod is absent, FR-013), not a new Azure-specific pin.
3. **Apply the four observability routing/scrape files individually**
   (`grafana-vs.yaml`, `prometheus-vs.yaml`, `istio-podmonitor.yaml`,
   `istio-servicemonitor.yaml` via `setup-aks-o11y-routes`), not through
   the whole-folder `setup-istio-o11y-addons` target, which stays
   EKS/local's. Known accepted coupling: a file added to that shared
   folder later does not automatically reach AKS (plan.md Risks; no
   drift check in this story).
4. **`grafana/alloy`, not the deprecated standalone `promtail` chart,
   ships logs on AKS.** The new Loki chart bundles no shipper at all
   (research.md finding 13), and Promtail is deprecated and frozen;
   Alloy (chart `1.13.0`) is Grafana's own actively-maintained successor.
   Its config is not yet live-verified at plan time — a real render
   confirmed the DaemonSet and its `operator: Exists` toleration offline;
   the live proof is the implementation task that queries Loki for an
   actually-arrived log line (constitution VIII deferral, recorded for
   the Architect).
5. **Keep the new Loki chart's Service flat.** The chart is pinned at
   `18.13.7` from the `grafana-community/helm-charts` repo (finding 12),
   and its values (`infra/azure/chart-values/loki.yaml`) set
   `fullnameOverride: loki`, `gateway.enabled: false`,
   `loki.auth_enabled: false` so the Service stays at the flat
   `loki:3100` the shared `prometheus-values.yaml`
   `additionalDataSources` entry and the Alloy shipper both hardcode —
   instead of adopting the chart's default gateway topology, which would
   render a `loki-gateway` Service every existing consumer misses
   (findings 14, 16: placement lives under `singleBinary.*`, the
   Monolithic-mode targets must be zeroed, and the canary/test/caches
   are disabled rather than given their own `o11y` placement).
6. **Run both per-machine helpers on every pool.** The Alloy DaemonSet
   (`controller.tolerations: [{operator: Exists}]`, the chart's actual
   placement keys per finding 16) and node-exporter tolerate every
   taint and carry no nodeSelector, so each runs on all five pools
   (system, app, persistent, o11y, loadgen) — the spec's
   Clarification of 2026-10-05 — instead of being pinned to `o11y`.
7. **Also accepted**: the shared `prometheus-values.yaml` provisions a
   Tempo datasource (`http://tempo.monitoring:3100`), but Tempo is out
   of scope on AKS — on a fresh AKS cluster Grafana shows one broken
   datasource. Accepted, not fixed: FR-006 requires only the metrics
   and logs sources; fixing it would mean editing a shared file (which
   would touch EKS/local) or carrying a third AKS-specific values file
   for one broken entry.

### Why this shape

- Reusing AKS's addon and the proven Kiali manifest keeps the new
  install surface to exactly what AKS lacks (Loki's own chart, a log
  shipper, the routing apply) — each a smaller, separately-verifiable
  change.
- Every choice traces to live output (research.md L1–L4) or a real
  offline render (finding 16), not documentation reading alone; the one
  documentation-shaped choice (Alloy) carries its explicit deferral and
  live-verification task.
- The `.env` configuration surface is unchanged: no new required keys
  (everything reuses `MONITORING_NS`), and chart settings stay in the
  repo's existing `*/chart-values/` mechanism (Principle II's exception).

### What we gave up

- One broken Tempo datasource on a fresh AKS Grafana (accepted, above)
  and a known not-yet-proven Alloy config (accepted with its own
  verification task). Also left as-is: Loki's volume claim names no
  StorageClass, so on AKS it uses the cluster default rather than
  `gp2` — pre-existing behaviour shared with EKS/local; follow-up story.

### Corrected during live implementation (2026-10-05)

Two decisions above did not survive first contact with the running
cluster. Both are now fixed with AKS-specific files under `infra/azure/`,
leaving the shared EKS/local files untouched (FR-017):

- **Point 2 is superseded: Kiali is no longer reused unmodified.** The
  shared v1.63 manifest runs (pod healthy, UI `200`) but its traffic-graph
  API crashes against Kubernetes 1.34 (`json: cannot unmarshal object into
  Go value of type []*kubernetes.RegistryEndpoint` — the deprecated
  `Endpoints` API shape changed). AKS now uses a manifest rendered from
  `kiali-server` **2.32.0** at `infra/azure/kiali/kiali.yaml`, applied by
  `setup-aks-kiali`. Verified live: the graph API returns real nodes/edges
  for Robot Shop, and the UI loads. EKS/local keep the shared v1.63
  manifest via `setup-istio-o11y-addons`. The chart's generated
  component/image naming (chart 2.32 / image v2.32.0) is copied verbatim
  into the manifest; the `kiali-vs.yaml` VirtualService is unchanged.
- **The optional collector did not work on AKS unmodified (FR-010).**
  `setup-optional-otel` never pinned its chart, so the chart floated to
  latest (0.175.0) while the shared values pin an old image (0.94.0); the
  newer chart emits component names (`file_log`, `k8s_attributes`,
  `otlp_grpc`) and config keys (`memory_ballast`,
  `service.telemetry.metrics.address`) the old image rejects — a
  crash-loop. AKS now pins chart **0.81.2** (the release whose app version
  *is* 0.94.0) with values at
  `infra/azure/chart-values/otel-collector.yaml`, via a `STACK_MODE=aks`
  branch in `setup-optional-otel`; `setup-hotrod` inherits it. Verified
  live: 1/1 Running. EKS/local keep the shared values unchanged.

Both are out of story 002's original scope (which reused shared files
unmodified); they are recorded here so a follow-up story can formalise the
Kiali-v2 and collector-pin decisions rather than have them live only in
this ADR.

Three smaller live fixes changed no decision above but are recorded so the
files explain themselves (plan.md "Implementation departures" items 3–5):

- **Alloy `app` label falls back to the pod's `service` label.** The
  shared Application Dashboard queries `{app="<service>"}`; Robot Shop
  pods carry `service=<name>`, not `app.kubernetes.io/name`. A relabel
  rule copies `service` into `app` only when non-empty, so it never
  overwrites `app.kubernetes.io/name`. (The first Alloy draft also used a
  Perl-only regex, `(?s.*)`, that Go's RE2 rejects; it was removed.)
- **`setup-dashboards` skips `rds.yaml` on AKS.** The AWS RDS CloudWatch
  dashboard has no data source on AKS; EKS/local still apply it.
- **Loki sets `loki.commonConfig.replication_factor: 1`.** The chart's
  default of 3 fails every ring query with a single Loki replica; an
  offline render cannot show this, only a live query can.

## AD-007 — Live research is the first step of `/speckit-specify`, not Phase 0 of `/speckit-plan`

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: story owner,
after `specs/008-aks-db-latency-fault` (constitution 1.5.0, principle VIII).

### Decision

All of principle VIII's hands-on research moves to the start of
`/speckit-specify`. Before any section of `spec.md` is written, the agent
settles what the story depends on — mechanism, platform behaviour, what
undoes it, charts, versions, targets, paths — against the real cluster,
subscription or chart repo, one finding at a time, into the story's
`research.md`. The spec is then written from those findings. The Architect
approves any research substitute at the spec gate. `/speckit-plan` no
longer runs a research pass: it builds on `research.md`, and a fact the
plan needs but research lacks is added as a new finding under the same
rules, with any resulting spec change going back to the Architect.

### Why

- Research during planning kept changing specs that were already approved.
  In story 008 the CPU-limit fault was abandoned, the MySQL Rewriter plugin
  turned out not to be installed, and a `mysql-0` restart wiped the fault —
  each found after `gate:spec-approved`, each a spec amendment and a
  second Architect review.
- A spec written from tested facts promises what can actually be delivered:
  realistic thresholds and accepted limits are agreed at the spec gate
  instead of discovered by the Builder.

### What we gave up

- The spec step is no longer about an hour; it carries the live research,
  so the Owner needs cluster or subscription access and spends cluster
  money before the spec gate — including on stories the Architect rejects.
- Research runs before the requirement is settled; a scope change in
  `/speckit-clarify` or at the spec gate can waste findings.
- Findings can go stale between spec and plan; the plan re-checks pins,
  targets and paths before asserting them rather than trusting old output.
- The rule lives in protected, generated skill files
  (`speckit-specify`, `speckit-plan`, four harness copies each).
  `specify integration upgrade --force` overwrites them silently, so an
  upgrade must re-apply both blocks.

## AD-008 — Keep secrets: one untracked folder, our own Secrets, built at install time

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: architecture
pass over `_bmad-output/specs/spec-keep-alert-management/SPEC.md`
(epic #91), try-out in its `research.md` §5.

### Decision

Every Keep credential lives in one untracked folder on the operator's
machine, and `setup-keep` turns it into Kubernetes Secrets at install time.
Nothing secret is in `.env`, a values file, a manifest, or a template.

1. **Where the values live.** `.env` holds only the folder's location,
   `KEEP_SECRETS_DIR=$HOME/.secrets/keep` (not `~`: make does not expand
   it; the script expands `$HOME`). One value per file, of two kinds:

   | File | Holds | Kind | First story |
   |---|---|---|---|
   | `fireworks.key` | Fireworks API key | supplied by operator | 2 |
   | `slack-webhook.url` | Slack incoming webhook | supplied by operator | 5a |
   | `keep-webhook-api.key` | Keep API key Alertmanager sends (AD-009) | generated | 3 |
   | `setup-api.key` | Keep API key `setup-keep` sends (AD-009) | generated | 4 |
   | `db-password` | Keep's MySQL root password (AD-013) | generated | 2 |
   | `login-password`, `jwt-secret`, `nextauth-secret` | login values (AD-009) | generated | 6a |

   Generated files are created by `setup-keep` only when missing
   (`openssl rand -hex 24`, mode 600) and reused on every later run.
   Hex keeps `:` and `,` out of the values, which would break
   `KEEP_DEFAULT_API_KEYS` (`name:role:secret`, comma-separated); a reused
   file that is not lowercase hex stops the script and names the file.
   The default username is not secret and goes in `.env`.
2. **Our own Secrets, never named `keep-*`.** The chart's pre-delete hook
   deletes every `keep-*` Secret in the namespace on `helm uninstall`. Ours
   use the prefix `sre-keep-`, one per concern, keys named after the
   environment variable they become: `sre-keep-ai-env` (story 2),
   `sre-keep-db` (key `DATABASE_CONNECTION_STRING` for the backend and key
   `mysql-root-password` mounted into the database pod; story 2),
   `sre-keep-api-keys` (`KEEP_DEFAULT_API_KEYS`, stories 3 and 4),
   `sre-keep-providers` (`KEEP_PROVIDERS` JSON, 5a), `sre-keep-auth`
   (login values, 6a). Alertmanager's key is the Secret
   `alertmanager-keep-auth` in `monitoring`, mounted for `password_file`
   (3). Both copies of that key come from the same file, so they cannot
   drift.
3. **Wiring.** Each story adds its Secret to `backend.envFromSecrets` /
   `frontend.envFromSecrets` (both lists in chart 0.1.97), never to the
   single `envFromSecret` slot, so stories do not overwrite each other.
   **No variable that comes from a Secret may also appear in
   `backend.env` or `frontend.env`**: Kubernetes lets an explicit `env`
   entry win over `envFrom`, so the real value would be silently ignored.
   In particular the values file drops the chart's default
   `NEXTAUTH_SECRET: secret` from `frontend.env`. Non-secret values the
   chart's helpers read from `frontend.env` (`NEXTAUTH_URL`,
   `API_URL_CLIENT`) stay there.
4. **Applying changes.** Secrets are written with `kubectl create secret …
   --dry-run=client -o yaml | kubectl apply -f -`. When apply reports a
   Secret changed (not `unchanged`), `setup-keep` runs `kubectl rollout
   restart` on the workloads that read it, since `envFrom` is read only at
   pod start. An unchanged re-run restarts nothing.
5. **Missing values.** `setup-keep` keeps one list of the files the
   current code uses (it grows story by story) and checks it before
   touching the cluster. A missing generated file is created; a missing
   supplied file stops `setup-keep` run on its own, naming each file.
   Inside `setup-aks`, the same check prints which supplied files are
   missing, skips Keep, and lets the rest of AKS setup finish.

### Why

- Constitution IV forbids real credentials in git; the tracked `.env`
  carries demo values only. Constitution III still holds: `.env` names
  where secrets come from, which III allows ("change where `.env` values
  come from").
- Keep's `KEEP_PROVIDERS_DIRECTORY` loader does no environment-variable
  substitution, and the chart's `backend.provision.providers` renders
  values into a Secret from the values file. Building the JSON at install
  time is the only path that keeps provider secrets out of the repo.
- The try-out lost Keep's stored provider credentials to the uninstall
  hook; a separate prefix makes reinstall safe.
- Generating the internal credentials means the operator only brings what
  comes from outside (Fireworks, Slack); skipping inside `setup-aks` keeps
  the one-shot AKS deploy usable for people without those accounts.

### What we gave up

- Two files must be created by hand before `setup-keep` runs:
  `fireworks.key` and `slack-webhook.url` (README lists them). The
  generated ones exist only on the machine that first ran `setup-keep`;
  a second operator machine generates different values, and installing
  from it changes the login password and the API keys.
- Deleting a generated API-key file is safe: the next run makes a new
  value, which is seeded as a new key under a new name (AD-009), and
  Alertmanager's Secret follows. The old key is not revoked; it stays
  valid in Keep's database until removed in the UI or by API. Deleting
  `login-password` resets the login (AD-009); deleting `jwt-secret` or
  `nextauth-secret` signs everyone out. Deleting `db-password` after the
  first install breaks Keep's database connection until the database
  volume is recreated: MySQL sets the root password only when it first
  creates its data directory.
- `setup-aks` succeeding no longer means Keep is installed; its output
  must be read.

## AD-009 — Keep login and API keys: DB login, one user, two seeded keys

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: architecture
pass over the Keep alert-management SPEC (epic #91); Keep's `NOAUTH`
behaviour seen in the try-out (`research.md` §5); Keep source at
`e5cd869` (`keep/api/core/db_on_start.py`, `keep/identitymanager/rbac.py`).

### Decision

1. **Login (story 6a).** `AUTH_TYPE=DB` (uppercase; lowercase caused a
   redirect loop) on backend and frontend, as plain `env`. One default
   user: `KEEP_DEFAULT_USERNAME` from `.env`; `KEEP_DEFAULT_PASSWORD` and
   `KEEP_JWT_SECRET` (backend) and `NEXTAUTH_SECRET` (frontend) from
   `sre-keep-auth` (AD-008). `KEEP_FORCE_RESET_DEFAULT_PASSWORD=true` as
   plain backend `env`: Keep otherwise applies the password only when it
   first creates the user (`db_on_start.py:33`), and the database survives
   `helm upgrade`, so `login-password` is always the source of truth.
   `NEXTAUTH_URL` is set in `frontend.env` to Keep's address (AD-010);
   with the chart's ingress off it otherwise defaults to
   `http://localhost:3000` and the login redirect fails. Story 6a keeps
   that default, because its sign-in goes through `kubectl port-forward`
   on `localhost:3000` and the route to `keep.demo.local` does not exist
   yet; story 6b sets `NEXTAUTH_URL` to `http://keep.demo.local` in the
   same pull request that adds the route (AD-010).
2. **Two API keys, seeded at start-up** through `KEEP_DEFAULT_API_KEYS`
   in `sre-keep-api-keys`, each named after a fingerprint of its value
   (first 8 hex characters of its SHA-256):
   `alertmanager-<fp>:webhook:<keep-webhook-api.key>,setup-<fp>:admin:<setup-api.key>`.
   Keep looks seeded keys up by name and skips any that exist
   (`db_on_start.py:124-126`), so a fixed name would keep the old hash
   while Alertmanager sends the new value and every alert gets 401. With
   the fingerprint, a new value is a new key.
   - The `webhook` role has exactly `write:alert` and `write:incident`
     (`rbac.py`): Alertmanager sends only that key.
   - `setup-keep`'s own API calls (the correlation rule, AD-011) send the
     `admin` key, which `POST /rules` needs. It never leaves the
     operator's machine and the `keep` namespace.
3. **Seeded from story 3, under `NOAUTH` too.** Seeding sits in Keep's
   single-tenant start-up path, not behind `AUTH_TYPE=DB`: the webhook key
   arrives with story 3, the setup key with story 4. `NOAUTH` accepts any
   key, but every caller sends the real one from the start, so nothing in
   Alertmanager or the scripts changes when story 6a turns the login on.
   Story 3 confirms the key exists by listing API keys. Keep also stores
   each seeded key's value in its own Secret `keep-<key name>` in the
   `keep` namespace; that one is Keep's, and the uninstall hook removes it.
4. **Story 6a starts with a live check** the try-out never ran: the DB
   login signs in with `login-password`, a changed `login-password` takes
   effect after a re-run, and a made-up key is rejected while both seeded
   keys work. If seeding fails, the fallback is `POST /settings/apikey`;
   if that fails too, stop and return to the spec.

### Why

- Under `NOAUTH` every request with any key is admin; Keep cannot be
  reachable from outside the cluster in that mode.
- Seeding makes keys declarative: a reinstall recreates them, so
  Alertmanager's mounted key keeps working with no API step. The
  fingerprint name turns Keep's skip-if-exists behaviour from a silent
  401 into a clean new key.
- A `webhook` key in the `monitoring` namespace can only post alerts and
  incidents. As an admin key, anyone who can read that namespace's
  Secrets could rewrite Keep's rules and workflows.
- Sending the real key from the start makes story 6a a switch, not a
  change to every earlier story.

### What we gave up

- One shared login; no per-person accounts or roles (SPEC non-goal).
- A new key value leaves the old key valid in Keep's database; it is
  unused, not revoked, until someone deletes it by hand.
- The login password cannot be changed in Keep's UI: every restart resets
  it to `login-password`.
- Seeding is read from code, not yet seen live; 6a may fall back to an
  API call, which then becomes a step `setup-keep` repeats after each
  reinstall.

## AD-010 — Keep's address: `keep.demo.local` on the shared ingress, extending AD-005

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: architecture
pass over the Keep alert-management SPEC (epic #91); try-out finding that
the websocket fails without a route (`research.md` §5).

### Decision

Keep's UI and websocket are served at the root of `keep.demo.local`, a
host-matched `Gateway`/`VirtualService` pair in the `keep` namespace on
the shared `istio: ingressgateway`, the pattern AD-005 set for HotROD.

1. **Routes** (one `VirtualService`, host `keep.demo.local`):
   `/websocket/app/` → `keep-websocket:6001`, prefix rewritten to `/app/`;
   everything else → `keep-frontend:3000`. The backend gets no route; the
   frontend proxies it at `/backend`. The chart points the browser at
   `<page origin>/websocket` (`PUSHER_HOST` defaults to the websocket
   prefix, `_helpers.tpl:123-129`), and the try-out's browser console
   showed the connection path
   `ws://localhost:3000/websocket/app/keepappkey?protocol=7&client=js&version=8.4.0`.
   Matching only `/websocket/app/` keeps Soketi's HTTP publish API
   (`/apps/…`) unreachable from outside. Fallback, if the narrow match
   fails live: the whole `/websocket` prefix, rewritten to `/`, as the
   chart's own nginx ingress does (`ingress-nginx.yaml:26-28`).
2. **One address everywhere.** `NEXTAUTH_URL=http://keep.demo.local` in
   `frontend.env`, a fixed string in the values file, like
   `hotrod.demo.local` in its manifest. Anything that links to Keep uses
   the same address: the Slack workflow's "Open in Keep" link is
   `http://keep.demo.local/incidents/<id>` from story 5a, not the
   try-out's `localhost:3000`. It resolves once story 6b is live.
3. **Reaching it.** `make get-service-endpoints` prints the URL and the
   `/etc/hosts` line (`<LB_ENDPOINT> keep.demo.local`). Scripts and checks
   use `curl -H "Host: keep.demo.local"`.
4. **Never before the login.** The route manifest arrives in story 6b,
   after 6a. `setup-keep` applies it only after confirming the running
   backend has `AUTH_TYPE=DB`, and refuses otherwise, so the order is
   enforced, not just planned.

### Alternatives considered and rejected

1. **nip.io hostname** (`keep.<ip>.nip.io`). Same host matching, no
   `/etc/hosts` edit, but an outside DNS dependency, and `NEXTAUTH_URL`
   then depends on the load balancer IP, so a recreated load balancer
   breaks login until `setup-keep` re-runs. Can be added later as a second
   host on the same `VirtualService` without changing this decision.
2. **A separate port on the gateway** (the SPEC's earlier preference).
   The ingress gateway is our own `istio/gateway` Helm release
   (`setup-istio-aks.sh`), not a managed add-on, so it is possible; but it
   changes the one entry point every app uses, on a release the EKS and
   k3d paths install too, and `NEXTAUTH_URL` again depends on the IP.
3. **A sub-path** (`/keep`). Ruled out: the published frontend image has
   no `basePath`, and Next.js fixes it at build time.

### Why

- Extends AD-005 rather than departing from it: no new load balancer, no
  change to the shared gateway release, no rewriting of the app's own
  paths. The only prefix strip is the one Keep's chart itself does for
  the websocket.
- A fixed hostname makes the login's redirect address and every link to
  Keep a constant, not an install-time lookup.

### What we gave up

- The browser needs an `/etc/hosts` entry (or a Host-header extension),
  same as HotROD; a presenter on a new machine adds one line first.
- Plain HTTP: the login password crosses the network unencrypted. Accepted
  for a demo stack with a generated, single-purpose password; TLS would
  need a certificate story of its own.

## AD-011 — Keep configuration: workflows as files, providers from a Secret, the rule by API

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: architecture
pass over the Keep alert-management SPEC (epic #91, CAP-7); Keep source at
`e5cd869` (`keep/api/config.py`, `keep/providers/providers_service.py:609-660`,
`keep/workflowmanager/workflowstore.py`, `keep/api/routes/rules.py:176-200`).

### Decision

Everything Keep needs after install comes from the repo plus AD-008's
secrets folder; nothing is clicked or posted by hand. Each kind of
configuration uses the one path Keep supports for it:

1. **Where the files live.** `infra/azure/keep/` holds `setup-keep`'s
   script and Keep's configuration: `workflows/` (one Keep workflow YAML
   per file), `providers.template.json`, `correlation-rule.json`. Chart
   values live in `infra/azure/chart-values/keep.yaml`. AKS-only, like
   every other `infra/azure/` feature (AD-006).
2. **Workflows (stories 5a, 5b): files, loaded at start-up.**
   `setup-keep` builds the ConfigMap `sre-keep-workflows` from
   `workflows/` (`kubectl create configmap --from-file … --dry-run=client
   -o yaml | kubectl apply -f -`), mounts it with `backend.extraVolumes`,
   and sets `KEEP_WORKFLOWS_DIRECTORY` to the mount path in `backend.env`.
   A changed ConfigMap restarts the backend, as AD-008 rule 4 does for
   Secrets. The chart's inline `backend.provision.workflows` stays empty;
   using both would set `KEEP_WORKFLOWS_DIRECTORY` twice. From Keep's
   source: start-up provisioning is on by default (`PROVISION_RESOURCES`
   defaults to `"true"`, `config.py:20`); the loader reads only names
   ending `.yaml` or `.yml`, so a mounted ConfigMap's `..data` entries are
   skipped; and a provisioned workflow whose file is gone is deprovisioned
   at the next start (`provision_workflows`). Story 5a sees this live in
   its normal run; it is not a gate.
3. **Providers (story 5a): JSON built at install time.**
   `providers.template.json` holds every non-secret field; `setup-keep`
   fills in the Fireworks key and Slack webhook from AD-008's files with
   `jq` and writes the result as `KEEP_PROVIDERS` into
   `sre-keep-providers`. Provider names are fixed here because workflows
   refer to them: `fireworks` (type `litellm`) and `slack`.
   `KEEP_PROVIDERS_DIRECTORY` and the chart's `backend.provision.providers`
   are not used: the first does no variable substitution, the second puts
   the values in the values file.
4. **Correlation rule (story 4): an idempotent API call.**
   `correlation-rule.json` is the rule as `POST /rules` takes it
   (`ruleName`, `sqlQuery`, `celQuery`, `timeframeInSeconds`, `timeUnit`,
   `resolveOn`, `createOn`, `groupingCriteria`). `setup-keep` lists the
   rules and matches by `ruleName`: absent, it creates the rule; present
   and different, it updates it in place with `PUT /rules/{rule_id}`
   (same body, `rules.py:176-200`); identical, it does nothing. Keep's
   start-up provisioning has no correlation rules.
5. **How `setup-keep` reaches Keep's API.** Always through
   `kubectl port-forward svc/keep-backend :8080`, letting kubectl pick a
   free local port and reading the port it prints, stopped by a `trap` on
   exit; every call sends the `admin` key (AD-009). The backend never
   gets an outside route (AD-010), so the same call works before and after
   story 6b, and a fixed local port cannot clash on the operator's machine.

### Alternatives considered and rejected

1. **Workflows inline in `backend.provision.workflows`.** Chart-native,
   with a free restart on change, but each workflow becomes a list entry
   in a values file instead of a Keep workflow file that can be uploaded
   or tested on its own, and stories 5a and 5b would both edit the same
   list.
2. **Everything through the API, as in the try-out.** Works, but leaves
   providers and workflows as state in Keep's database that a reinstall
   loses, and that differs from the repo when someone edits the UI.

### Why

- CAP-7: after `helm uninstall keep` and `make setup-keep`, everything
  is back with no manual step, and no secret value is in the repo.
- One file per workflow keeps stories 5a and 5b from editing the same
  file; deleting a file removes its workflow, so the folder is the truth.
- Fixed provider names stop the workflows (5a, 5b) and the providers
  template (5a) from drifting apart.

### What we gave up

- Three loading mechanisms instead of one, because Keep offers no single
  one: a reviewer must know which kind of configuration goes where.
- Workflows and providers are reloaded only when the backend restarts;
  UI edits to them are overwritten at the next restart.
- The correlation rule is the one piece applied by API, so it depends on
  a reachable backend and a valid admin key at install time.

## AD-012 — Alertmanager on AKS only, sending only to Keep

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: architecture
pass over the Keep alert-management SPEC (epic #91, CAP-3); try-out
override `tryout/prometheus-stack-keep-override.yaml` and its pre-upgrade
diff (`research.md` §5, `tryout/keep-tryout-findings.md:43`).

### Decision

1. **AKS only.** `alertmanager.enabled: true` goes in
   `infra/azure/chart-values/prometheus-stack.yaml`, the overlay
   `setup-aks-prometheus-stack` layers after the shared file. The shared
   `monitoring/chart-values/prometheus-values.yaml` keeps
   `enabled: false`, so EKS and k3d still run no Alertmanager.
2. **Keep is the only receiver, set in the AKS overlay.** Root route
   `receiver: keep`, `group_by: [alertname, namespace]`, `group_wait: 15s`,
   `group_interval: 1m`, `repeat_interval: 1h` (the try-out's timings),
   with `routes: []` set explicitly (Helm merges maps, so the shared file's
   sub-routes would otherwise survive), and the `receivers` list restated
   in full (lists replace): `'null'` and `keep`. The `keep` receiver posts
   to `http://keep-backend.keep.svc.cluster.local:8080/alerts/event/prometheus`
   with `send_resolved: true` and basic auth: username `api_key`,
   `password_file` from the Secret `alertmanager-keep-auth` (key `api-key`),
   listed in `alertmanagerSpec.secrets`. The AKS file does not rely on what
   the shared file contains.
3. **The Secret exists before Alertmanager does.** A Secret listed in
   `alertmanagerSpec.secrets` is mounted as a volume, so if it is missing
   the Alertmanager pod does not start at all — not merely fails to send.
   `setup-aks-prometheus-stack` therefore creates `alertmanager-keep-auth`
   before its `helm upgrade`, through the same helper in
   `infra/azure/keep/` that `setup-keep` uses, generating
   `keep-webhook-api.key` if missing (AD-008). That file is generated,
   never supplied, so this works even when Keep itself is skipped. One
   target owns the `prometheus-stack` release; `setup-keep` never
   upgrades it. Grafana, which belongs to the same release, also reads
   this Secret (story 8) through an environment variable used by its
   provisioning file, so the key has no further copy.
4. **The broken Slack setting leaves the shared file.** Removed:
   `slack_api_url: "slack-webhook-url"`, the `P1 → slack` sub-route and the
   `slack` receiver; the root receiver becomes `'null'`. This departs from
   specs/005's "shared file stays untouched" (FR-007/FR-008) and from
   AD-006 point 7's reluctance to edit it; the AKS overlay's header comment
   is updated to say so. Non-regression for EKS and k3d follows AD-004 and
   is expected to pass: with Alertmanager disabled the chart never renders
   the config block — in the try-out, `helm template` of the shared values
   plus the AKS overlay rendered no Alertmanager objects, and all five
   appeared only when `enabled: true` was added. So removing the Slack
   setting cannot change EKS or k3d output. Story 3 still runs the render
   comparison (before and after, shared values only) and `make lint`.

### Alternatives considered and rejected

1. **`setup-keep` adds the Keep receiver as a third values file.** Two
   targets would own one Helm release; a later `setup-aks-prometheus-stack`
   run would silently drop the Keep wiring.
2. **Leave the Slack setting in the shared file and neutralise it in the
   overlay only.** Works on AKS, but keeps a placeholder that looks like a
   secret slot and a Slack path the epic says does not exist; the overlay
   still neutralises it anyway (point 2), so removal costs nothing.

### Why

- Keep groups, summarises and notifies; a second notifier in Alertmanager
  would post raw alerts to Slack beside Keep's summary.
- Creating the Secret with the release, not with Keep, means the pod
  always starts.
- The timings are part of CAP-5's budget: Slack must show the summary
  within two minutes of the incident opening, and in the try-out the
  incident opened about 90 seconds after the fault. Raising `group_wait`
  or `group_interval` later eats that budget; change them only with the
  two-minute check re-run.

### What we gave up

- With Keep skipped (AD-008 rule 5), Alertmanager runs and its deliveries
  fail with errors in its log until `setup-keep` runs. Accepted: alerts
  went nowhere before this epic either, and the errors say why.
- `setup-aks-prometheus-stack` now depends on `infra/azure/keep/` and the
  secrets folder location, so monitoring and Keep are no longer
  independent installs.
- A shared file EKS and k3d use changes, proven by render and lint, not
  a live run on those targets.

## AD-013 — Keep install baseline: one values file, every image pinned, a database password, telemetry off

**Date**: 2026-10-23 · **Status**: Accepted · **Raised by**: architecture
pass over the Keep alert-management SPEC (epic #91, CAP-1); chart
`keephq/keep` 0.1.97 templates; try-out install findings (`research.md` §5).

### Decision

1. **One values file, shared by every story.** All chart settings live in
   `infra/azure/chart-values/keep.yaml`; `--set` only for one-off host
   wiring (AGENTS.md). Chart pinned to `keephq/keep` **0.1.97** (Keep
   0.54.3); backend and frontend image tags follow the chart's app version,
   and the chart already pins Soketi (`1.4-16-debian`).
2. **`env` lists restate the chart defaults.** `backend.env`,
   `frontend.env` and `database.mysql.env` are lists, so setting them
   replaces the chart's defaults. The values file carries the defaults
   verbatim, minus the ones a Secret now supplies (AD-008 rule 3:
   `NEXTAUTH_SECRET`, `DATABASE_CONNECTION_STRING`,
   `MYSQL_ALLOW_EMPTY_PASSWORD`), and every story only appends to or
   edits its own entries; none removes a default without saying why in
   its `plan.md`.
3. **Every image the chart leaves floating is pinned to an exact tag**,
   looked up and recorded in story 2's `plan.md` when it is built:
   - `database.mysql.image.tag` (chart: `latest`); the check is Keep's
     database migrations running on it, and `MYSQL_ROOT_PASSWORD_FILE`
     being honoured (point 4).
   - `deleteSecretJob.image` (chart: `bitnami/kubectl:latest`,
     `pullPolicy: Always`, set to `IfNotPresent`). The hook runs
     `/bin/sh -c` with `grep` and `xargs`, so the image needs a shell,
     not only kubectl. Bitnami changed its free Docker Hub catalogue in
     2025 and versioned tags may no longer pull; story 2 uses a versioned
     `bitnami/kubectl` tag if one pulls, otherwise a pinned image with a
     shell and kubectl (for example `alpine/k8s:<version>`).
   - `busybox`, which the chart hardcodes in its `wait-for-database` init
     container (`templates/backend.yaml:170-174`) with no values key:
     `backend.waitForDatabase.enabled: false`, and the same wait (`until nc
     -z keep-database 3306`) added as `backend.extraInitContainers` with a
     pinned `busybox` tag.
4. **The database has a root password, from story 2.** The chart runs
   MySQL with `MYSQL_ALLOW_EMPTY_PASSWORD` and connects as root with none.
   Instead, all through values: the generated `db-password` (AD-008)
   goes into `sre-keep-db`; the database pod mounts it with
   `database.extraVolumes` / `database.extraVolumeMounts` and reads it
   through `MYSQL_ROOT_PASSWORD_FILE` (`database.mysql.env` renders plain
   values only, `templates/db.yaml:69-78`, so it cannot reference a
   Secret); the backend reads `DATABASE_CONNECTION_STRING` from the same
   Secret through `backend.databaseConnectionStringFromSecret`. The
   connection string embeds the password
   (`mysql+pymysql://root:<db-password>@keep-database:3306/keep`);
   AD-008's hex rule means it needs no URL-escaping, so `db-password` must
   never switch to a generator that can produce `@`, `/` or `:`.
5. **Telemetry off.** `POSTHOG_DISABLED=true` on backend and frontend,
   `SENTRY_DISABLED=true` on frontend, as plain `env` (not secret).
6. **Placement and storage.** Backend, frontend, websocket and database
   carry `nodeSelector: workload: o11y` and the o11y and spot tolerations
   (AD-003). The delete-secret hook job has no placement keys in the
   chart; it lands on an untainted pool (the system pool always is,
   AD-002). `database.pv.enabled: false` (the chart's default is a
   hostPath volume) and `database.pvc.storageClass: gp2` (AD-001).

### Why

- The try-out saw Keep report uptime to PostHog by default; an internal
  demo stack should not send data out unasked.
- A floating `latest` means two installs a week apart can run different
  databases; the hook image is pulled again on every uninstall, and may
  stop pulling at all.
- A passwordless root database lets anything in the cluster write a user
  or an admin API key hash straight into Keep's tables, which undercuts
  AD-009's login. MySQL sets the root password only when it first creates
  its data directory, so it has to arrive with story 2; adding it later
  means wiping Keep's volume.
- Replacing the chart's own init container is the only way to pin
  `busybox` without forking the chart.
- Four stories edit the same lists; restating defaults once and only
  appending stops a later story from silently dropping one.

### What we gave up

- The values file restates about twenty chart defaults; a chart upgrade
  must re-diff them by hand, since Helm will not merge them in.
- Our copy of the wait-for-database container can drift from the chart's
  if a later chart version changes it.
- The hook image may not be Bitnami's, so it is one more image whose
  behaviour we vouch for.
- Pins age: a newer MySQL or kubectl needs a deliberate bump.
- Deleting `db-password` after the first install breaks Keep's database
  connection until the volume is recreated (AD-008).

## AD-014 — Story cost ledger: local logs, a pinned price table, a per-story upsert file

**Date**: 2026-10-27 · **Status**: Proposed (built ahead of the story issue and `gate:plan-approved` on the owner's say-so) · **Raised by**: owner request to see tokens and dollars per Spec Kit story; plan `story-cost-ledger`.

### Decision

1. **Local logs, not billing APIs.** `agent/tools/story-cost.sh` reads Claude Code transcripts (`~/.claude/projects/<repo path with / and . as ->/`, including worktrees and `subagents/`) and the OpenCode database (read with `python3 -I` and its built-in `sqlite3`, on a copy, so the live file is never opened for writing). Other harnesses need one new reader function.
2. **One row per harness + session + model + branch** in `specs/<story>/usage.tsv`. A fresh run replaces rows with the same key and keeps the others, so rows survive after the harness deletes its logs. A fresh row with fewer tokens than the stored one is a sign of deleted logs: the stored row stays and is flagged `shrunk`. `cost.md` is rebuilt from `usage.tsv` only and has no timestamp, so a re-run changes nothing.
3. **Branch decides the story.** A reply belongs to story `<branch>` only if `specs/<branch>/` exists. Claude Code gives the branch on every reply. OpenCode has none, so it is read from the checkout's git reflog at the message time. Everything else (`main`, `planning/*`, deleted `/tmp` worktrees, reflog older than 90 days) is dropped and only counted in a "skipped" line. There is no override map and no all-stories mode.
4. **Pinned price table in `agent/tools/model-prices.tsv`**, not `agent/policies/` (prices are data, and an agent must be able to update them in a reviewed PR). Each reply is priced on its own, because fast mode and the Haiku over-100k-token tier are per reply. An unknown model is flagged `unpriced` with an empty `usd` (never 0).
5. **No Spec Kit extension package.** It would generate `speckit-*` skills and commands, which are protected paths. Instead `.specify/extensions.yml` has plain `after_specify`, `after_tasks`, `after_analyze`, `after_implement` and `after_converge` hooks (`optional: false`; the first three were added on 2026-10-27 so the specify, tasks and analyze steps are costed too) that call a hand-written `story-cost` skill (and `.opencode/commands/story-cost.md`). The hooks are a convenience; `make story-cost` is the trigger. `make lint` only warns when a story with ticked tasks has no `usage.tsv`.
6. **OpenCode token meaning, checked against stored cost** (OpenCode v2.1.4; `opencode-go` replies with non-zero stored cost): `tokens.input` excludes cache reads and writes, and `tokens.reasoning` is billed in addition to `tokens.output` at the output rate. With `deepseek-flash` rates input 0.15, output 0.60, cache read 0.003 dollars per million, adding reasoning at the output rate matched the stored cost to within 1% on 652 of 652 replies with reasoning; leaving it out matched 16. A second model, `deepseek-v4.1-flash`, fits the same way (1096 of 1096). The script constant is `OPENCODE_REASONING_SEPARATE=1`.
7. **OpenCode's stored cost wins when it is non-zero.** An OpenCode message that stores a cost above 0 is counted at that cost. Only messages that store cost 0 (free models, subscriptions) are priced from the table, meaning "what this would cost at list price". This was chosen because the stored cost for `opencode-go` did not match the published Zen list rates (see below).
8. **Retention is a user-level setting.** `cleanupPeriodDays` in `~/.claude/settings.json` (not 0; 3650 suggested), otherwise Claude Code deletes transcripts after 30 days. The repo does not change `.claude/settings.json`.

### Why

- Provider billing APIs do not split cost by story or branch; the local logs do.
- Keeping rows after logs vanish makes the ledger a record, not a view.
- Splitting by branch matches how stories are worked (one branch per story) with no manual tagging.
- A table in `agent/tools/` avoids protected paths and stays reviewable.

### What we gave up

- Planning work done on `main` or `planning/*`, and older OpenCode work (deleted worktrees, expired reflog), is never counted.
- Older stories are not back-filled, and Codex and Devin are not read.
- Dollars are list price: the table has to be kept current by hand. A check against OpenCode's own stored cost showed the `opencode-go` stored cost is exactly half of the table rates for `deepseek-flash` and `deepseek-v4.1-flash` (and for about half of the `glm-5.3-flash` replies), so the ledger uses the stored cost for those messages instead of the table. The table rates for OpenCode models now matter only for zero-cost messages, and the id-to-name match for `deepseek-flash` on the Zen price page is still unconfirmed.
- Rates were taken from the vendors' pricing pages on 2026-10-27 and not re-fetched while building.
- The session that runs a hook is recorded only up to that moment; the next run tops it up.
- A future `specify extension add` or `remove` may rewrite `.specify/extensions.yml`.

## AD-015 — Robot-shop alert limits live in the rule file, not in .env; slow requests are measured as a share

**Date**: 2026-10-28 · **Status**: Proposed (with spec 009's plan, PR #138, `gate:plan-approved` pending the Architect) · **Raised by**: story #122, keep alert rules for the demo shop on Azure; plan `specs/009-robot-shop-alert-rules/plan.md`.

### Decision

1. **Alert limits and waits live in `infra/azure/alert-rules/robot-shop-alerts.yaml`**, next to each rule, with the reason in a comment. They are not in `.env`. This is the exception to principle III (one configuration surface) in the plan's Complexity Tracking table. The file is applied by `make setup-aks-alert-rules`, so a limit changes with no chart upgrade (FR-015).
2. **Slow requests are measured as a share, not a 95th percentile.** The shipping and ratings rules fire when more than 15% (shipping, over 2.5 s) or more than 10% (ratings, over 0.5 s) of requests in the window are slower than the limit. Each rule also needs at least 30 requests in its window, so a service with a handful of requests stays quiet.

### Why

- The alert rule and its limit are read together, so a person changing a limit sees the reason at once. A template filled from `.env` would hide the condition and would not let `promtool` check the real expression (research Findings 5, 7 and 8).
- A 95th-percentile limit leaves almost no room: a healthy shop reached 3.8 s and the slow-database fault sat at 4.4 to 5.0 s (Findings 5 and 7). The share separates them: 0.5% to 7.4% healthy, 7% to 24% during the fault (Finding 8).

### What we gave up

- One configuration surface. Limits for the shop alerts now sit in a monitoring file, not with the other tunable settings in `.env`.
- The simpler 95th-percentile rule. The share rule needs a request-count guard and a short explanation for each limit.
- Each limit rests on one run plus the verification run. Changes must be written down with a new finding (plan, "What counts as pass").
