# Data Model — Out-of-Memory Kill of the Cart Pod on Azure

Everything the three commands look at, hold and change, with the transitions the
live run proved (research.md). One namespace (`APP_NS`, `.env:38`), one Helm
release (`roboshop`), one object carries the fault.

## 1. The cart Deployment — the only object the commands change

`Deployment cart` in the shop namespace, Helm-managed by release `roboshop`
(verified live in research.md Findings 3 and 4). Its pod template carries:

| Field | Fault off (chart value) | Fault on | Where the value comes from in the commands |
|---|---|---|---|
| `containers[cart].resources.requests.cpu` | `100m` | unchanged | — |
| `containers[cart].resources.requests.memory` | `50Mi` | `8Mi` | start | 
| `containers[cart].resources.limits.cpu` | `200m` | unchanged | — |
| `containers[cart].resources.limits.memory` | `100Mi` | `24Mi` | start |
| annotation marker (below) | absent | present | start writes, revert removes |

Two cluster facts behind these numbers, both live-run (research.md):

- **Requests must come down with the limit.** `50Mi` asked against a `24Mi`
  limit is rejected by the API server ("must be less than or equal"), so start
  and revert always set both requests and limits (Finding 1).
- **Only the cart container changes.** The `istio-proxy` sidecar is injected
  per pod and is not part of the Deployment's container list, so a container
  limits change touches cart's allowance and nothing else (FR-006 holds;
  Finding 1).

## 2. The fault marker — one annotation on the same Deployment

Key: `sre-stack/oom-fault: active`, value `active`. Kubernetes annotation,
written on the same Deployment the commands change — no new Kubernetes object,
no ConfigMap, no chart value (FR-014: setup behaves as today; the chart is
untouched).

- **Written by start, removed by revert.** Never set manually in the design —
  but the truth table below is written so that a stale marker (someone else
  removing it by hand) is never mistaken for the fault.
- **Survives a shop redeploy** (research.md Finding 4 proved `helm upgrade
  --install` leaves it in place across revision 4→5).

## 3. The two inputs status reads

1. **Is the marker present?** — `kubectl get deployment cart` and its annotation.
2. **Is the live allowance lowered below the Helm release's?** — the live values
   on the Deployment compared with the ones read out of the Helm release
   manifest (`helm get manifest roboshop`), which still carried `100Mi`/`50Mi`
   while the live object carried `24Mi`/`8Mi` (Finding 4). This is *the* source
   for revert too, which is how FR-008's "the allowance the shop is installed
   with at the moment it runs, no recorded value replayed" is met.

State truth table, copied from the live run (each row is a state the commands
can be in or find):

| marker | live allowance | state meaning | any of the commands change it? |
|---|---|---|---|
| absent | = release (`100Mi`) | healthy — the shop as installed (SC-010 territory) | no |
| absent | lowered | someone set it that way without start (EC-008) — the commands do not claim this fault | start (making it row 3) or revert (back to row 1) |
| present | lowered | **fault active**, whether the container is being killed or waiting out the restart back-off (the 2026-10-21 clarification) | revert (making it row 1) |
| present | = release | marker left over after a shop redeploy cleared the fault (Finding 3), or someone cleared the allowance by hand | revert (making it row 1) |

## 4. The pod(s) and what the commands wait for

Cart runs **one pod** on Azure by chart default (`cart-deployment.yaml:8–12`,
replicas 1 off EKS). While start or revert rolls a new ReplicaSet, **two pods
briefly exist simultaneously**, the new one coming up while the old one may
still serve (every command must handle more than one pod — Finding 1). Pod
fields the commands use:

- Start's wait counts only pods of the Deployment's newest ReplicaSet; a pod left
  over from an older rollout may carry a stale kill and is ignored.
- `status.containerStatuses[name=cart].state` — running / waiting / terminated
  as the container is being killed or waiting to restart.
- `status.containerStatuses[name=cart].lastState.terminated.reason` —
  `OOMKilled` with exit code `137`, seen live in Finding 1 within 15 s of the
  change. This is the start command's own result check.
- `status.containerStatuses[name=cart].restartCount` — the number the demo
  points at. Revert replaces the pod (rolling update) so the counter **resets
  to 0** rather than flattening (Finding 1); the guide says so for the presenter
  and the acceptance scenario "count stops climbing" is read as "the pod no
  longer keeps re-numbering upward", which is what a rollout shows.

Wait cycles live in `contracts/commands.md`; the budgets are the spec's (SC-005
under 90 s per command), backing out of the wait is an honest failure with the
observed state printed, never a silent success.

## 5. The pre-checks every command runs first

Cheap, read-only, in this order, each one refusing with a message naming what is
missing and changing nothing (FR-007, EC-005). Checked in `research.md` in the
order given, against the live cluster, wherever marked ✔:

1. `.env` read, and `STACK_MODE=aks` ✔ (`:5`) — a non-AKS value or an unreadable
   `.env` refuses; nothing runs against EKS or local (FR-013).
2. `kubectl` reachable — a `connection refused` refuses ("Could not reach the
   cluster in the current kubectl context."). ✔ pattern proven live in Finding 1.
3. The current cluster **is an AKS cluster** — nodes carry the
   `kubernetes.azure.com/cluster` label, live-proven just now
   (`kubectl get nodes -l kubernetes.azure.com/cluster` listed all 9 nodes,
   `aks-app-*` through `aks-persistent-*`). This is the same check story 006
   uses (`infra/azure/scenario-01/ratings-abort.sh`, precheck: AKS label via
   `get nodes -l kubernetes.azure.com/cluster`); the "aks- node-name" stub I
   first wrote here is replaced by the label check, which is the honest gate,
   not a naming guess.
4. Namespace `APP_NS` holds a `cart` Deployment ✔ (every finding up to Finding 4
   read it live).
5. Helm release `roboshop` exists and is `deployed` or `failed` ✔ (a failed last redeploy still holds the allowance the shop was installed with; found by the live redeploy check, tasks D20) (Finding 3: the redeploy
   itself printed "Release has been upgraded", `REVISION: 4`; Finding 4: the
   release manifest was read as the revert source). A missing release also
   means there is no "allowance the shop is installed with" for FR-008 to
   restore, which is a hard refusal rather than a degraded answer.

Unlike 006, no mesh check: nothing in this fault sits behind the mesh, and the
commands must not require a component they never touch. If the mesh is broken
while cart runs, start/status/revert still behave as designed, which was
observed repeatedly in Findings 1–4 while other pods were `1/2`.

Any later failure in start or revert prints the state it observed — which
truth-table row it found, and the pod fields listed in §4 — so nothing is
checkpointed into a file or left to memory.

## 6. What is deliberately *not* in this data model

- No `.env` addition. The namespace, the release, the chart directory it
  installs from and the kill-value hint `24Mi` all come from what the chart
  releases (FR-008) or from this plan; adding a tunable to `.env` becomes a
  feature with its own command path, not a requirement this story has.
- No state in the repo. Nothing tracks "is a fault active" outside the cluster
  (EC-003 says any arriving person with cluster access can check or revert).
- Anything about Grafana panels is out of scope here — the *dashboard section*
  recording the counter and kill reason lives in its own file(s) for
  `monitoring/dashboards/application.yaml` (FR-011 as clarified), designed in
  quickstart.md, since it is the spec's only "visible on a dashboard" clause.
