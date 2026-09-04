# Worked example — Story 001 "AKS cluster", start to finish

> **This is a mock.** Everything below — the files, the chat transcripts,
> the meeting minutes — is invented to show you what the process in
> [`framework.md`](./framework.md) looks and feels like. The names are
> real, the words are not, and the technical choices inside (Kubernetes
> version, VM sizes, region) are placeholders the real story will decide
> for itself. Read it for the flow, not for the Azure details.

**The people.** Aman — Sponsor. Rijo — Owner (and reviewer of the final
PR). Abishek — Architect. Viknesh — Builder. The agent transcripts happen
to be Claude Code; Codex, OpenCode or Devin would run the same commands.

**The clock.** Two working days, as the framework demands:

| When | What happens |
|---|---|
| Mon 09:30 | Daily sync: story accepted, hats assigned |
| Mon 11:00 | Spec written and clarified, draft PR open |
| Mon 14:00 | Spec approved (async, on the PR) |
| Mon 16:30 | Plan + tasks written, analyze run, plan approved |
| Tue all day | Build, verify on Azure, evidence into the PR |
| Tue 17:45 | Agent review, fixes, human review, **merge** |
| Wed 09:30 | Daily sync: demo, converge results, story 002 accepted |

---

## 1. The story (GitHub issue #101, written Sunday evening by Rijo)

> **Title:** AKS cluster we can create and destroy with make
>
> **Problem**
> The enterprise only supports Azure now, and this whole repo assumes AWS.
> We have no Azure path at all — not even a bare cluster. Until a cluster
> comes up on AKS, nothing else can be migrated.
>
> **Outcome**
> With `STACK_MODE=aks` in `.env`:
> - `make setup-cluster` creates an AKS cluster with our four node pools,
>   labelled and tainted the same way as on EKS
>   (`workload=app|persistent|o11y|loadgen`).
> - A storage class named `gp2` exists and a test volume claim binds to an
>   Azure disk (same alias trick we already use on k3d).
> - `make cleanup-cluster` deletes everything it created — no leftover
>   resource group, no stray disks or IPs.
> - Running either command twice in a row is safe.
>
> **Out of scope**
> Istio, the apps, monitoring, the database, autoscaling, secrets,
> removing AWS files. All later stories.
>
> **Must keep working**
> `make setup-local` and the EKS files, untouched (not tested, just not
> broken — they still lint).

Notice what's *not* here: no `az` commands, no VM sizes, no Kubernetes
version. The story says what we want, not how.

---

## 2. Monday 09:30 — daily sync (15 min)

**Present:** Aman, Rijo, Abishek, Viknesh. **Minutes by:** Rijo.

- Aman read #101. One question: "Why not cluster *and* apps in one story?"
  Rijo: at 1–2 days per story including the cloud runs, cluster alone is
  the honest size; apps are story 002, already drafted. Aman: accepted.
- Hats for 001: Owner Rijo, Architect Abishek, Builder Viknesh. Final PR
  reviewer will be Rijo (he isn't Builder and didn't approve the plan).
- Aman confirmed the sandbox subscription; all three have Contributor.
- Viknesh flagged one risk out loud: nobody has created AKS node pools
  with taints via CLI before. Agreed the plan must prove it before code.

**Decisions:** #101 labelled `accepted`. Story 002 ("apps on AKS") to be
brought to tomorrow's sync.
**Actions:** Rijo → spec today, morning. Viknesh → check `az` CLI
installed everywhere, today.

---

## 3. Monday ~10:00 — Rijo writes the spec

Rijo, in Claude Code on `main`:

```
> /speckit.specify AKS cluster we can create and destroy with make.
  [pastes the accepted issue text from #101]

● Created branch 001-aks-cluster
● Created specs/001-aks-cluster/spec.md
● 3 [NEEDS CLARIFICATION] markers — run /speckit.clarify.
```

The generated `spec.md`, trimmed to its core:

```markdown
# Spec: AKS cluster via make

**Branch**: 001-aks-cluster · **From**: issue #101 · **Status**: draft

## What a user can do when this ships
1. Set STACK_MODE=aks, run `make setup-cluster`: an AKS cluster exists
   with four node pools labelled workload=app / persistent / o11y /
   loadgen, taints matching the EKS config.
2. Apply a PersistentVolumeClaim against storage class `gp2`: it binds
   to an Azure disk.
3. Run `make setup-cluster` again: exits 0, creates nothing new.
4. Run `make cleanup-cluster`: every created resource is gone.
5. Run `make cleanup-cluster` again: exits 0.

## Requirements
- R1  STACK_MODE accepts `aks` alongside `eks` and `local`.
- R2  All Azure settings (region, resource group, cluster name, node
      sizes, node counts, Kubernetes version) live in `.env`.
- R3  Scripts are check-then-create and re-runnable, like the EKS ones.
- R4  Every created resource is tagged project=sre-stack.
      [NEEDS CLARIFICATION: tag set fixed or configurable?]
- R5  Storage class `gp2` backed by the Azure disk driver.
- R6  EKS scripts and eksctl.yaml byte-identical to main; makefile may
      gain aks branches. `make setup-local` behaviour unchanged.
- R7  Node pools use [NEEDS CLARIFICATION: cheap interruptible "spot"
      VMs like EKS, or regular VMs?]
- R8  [NEEDS CLARIFICATION: is the o11y/loadgen pool created now even
      though nothing runs on it until later stories?]

## How we'll know it works (success criteria)
- S1  Fresh subscription → setup-cluster completes ≤ 15 min (measured,
      not promised).
- S2  After cleanup-cluster, `az resource list --tag project=sre-stack`
      is empty.
- S3  Second setup-cluster run ≤ 2 min, output contains no "Creating".
- S4  `make lint` passes; `git diff main -- infra/eksctl.yaml
      infra/scripts/cluster/*.sh` is empty.
```

Then the clarify pass — the agent asks, Rijo answers, answers go into the
spec:

```
> /speckit.clarify

Q1 (R4): tags fixed or configurable?
> Fixed pair project=sre-stack, owner=<from .env>. Keep it boring.

Q2 (R7): spot or regular VMs?
> Spot by default — same cost profile as EKS — with a single .env switch
  to regular for demos. Which is default is written here, not in code
  comments.

Q3 (R8): create the empty pools now?
> Yes, all four. The labels-and-taints contract is the point of this
  story. o11y and loadgen at 1 node each; sizes are the plan's problem.

● 0 markers remain. Clarifications recorded in spec.md, dated.
```

Rijo commits `specs/001-aks-cluster/spec.md`, pushes, and opens **draft
PR #102**, linking issue #101. He posts in the team channel: "001 spec
ready for Abishek."

---

## 4. Monday ~13:00 — spec review (async, on PR #102)

> **Abishek:** R1 says STACK_MODE accepts `aks` — but this story only
> wires `setup-cluster`/`cleanup-cluster`. Someone running plain `make
> setup` with aks will get half a stack. Spec should say what `make
> setup` does in aks mode *for now*: fail with a clear message, or run
> just the cluster part?
>
> **Rijo:** Good catch. Added R9: "in aks mode, `make setup` and `make
> cleanup` stop with a message naming the stories that will complete
> them; only setup-cluster/cleanup-cluster do real work." Commit pushed.
>
> **Abishek:** S1 says 15 min — based on what?
>
> **Rijo:** A guess. Reworded: measured and recorded, not a pass/fail
> number.
>
> **Abishek:** ✅ Spec approved at commit `a1b2c3d`. Label
> `spec-approved` applied. (Mon 14:05)

Two comments, one round, done in an hour of elapsed async time. If it had
dragged, it would have gone to Tuesday's sync — it didn't need to.

---

## 5. Monday ~14:30 — Viknesh plans

Viknesh makes himself a worktree so his other work stays untouched:

```
git worktree add ../sre-stack-001 001-aks-cluster
```

Then, in the agent:

```
> /speckit.plan
  az CLI bash scripts in this repo's check-then-create style. Pin
  versions in .env. Check AKS facts against the microsoft-learn MCP
  server, not memory.

● Read constitution v1.0.0 and spec.md (0 markers).
● Wrote plan.md, research.md, quickstart.md.
```

`plan.md`, trimmed:

```markdown
# Plan: 001-aks-cluster

## Approach
A sibling of the EKS scripts: infra/scripts/cluster/aks/ with three
bash scripts (common.sh, setup-cluster.sh, cleanup-cluster.sh), driven
by a new AZURE_*/AKS_* block in .env. Cleanup deletes the resource
group, which takes everything with it. The makefile forks on
STACK_MODE=aks for setup-cluster, cleanup-cluster, and the R9 guard
messages. gp2 storage class applied after create, exactly like
infra/local/gp2-storageclass.yaml does on k3d, but with
provisioner disk.csi.azure.com.

## Files changing
.env · makefile · infra/scripts/cluster/aks/{common,setup-cluster,
cleanup-cluster}.sh (new) · infra/aks/gp2-storageclass.yaml (new) ·
README.md · AGENTS.md

## Pinned choices (full reasoning in research.md)
K8s 1.33 (newest AKS GA; EKS's 1.27 no longer exists on AKS) ·
region centralindia · VM sizes: D2as_v5 (app), D4as_v5 (persistent,
o11y), F4s_v2 (loadgen), system pool D2s_v5 · Spot priority with
AKS_NODEPOOL_PRIORITY=Regular as the .env switch.

## Constitution check
Re-runnable scripts ✔ · one config surface (.env) ✔ · versions pinned ✔
· no secrets ✔ · workload labels/taints ✔ · lintable before cloud ✔

## Risks
1. Taints on AKS node pools use different CLI syntax than eksctl —
   verified against MS Learn docs, but T02 proves it on a real pool
   before the rest is written.
2. Spot quota in the region — T02 checks quota first.

## Verification (quickstart.md)
1  make lint                                → PASS
2  time make setup-cluster                  → exit 0, note minutes
3  kubectl get nodes -L workload            → all four labels present
4  kubectl describe nodes | grep Taints     → match eksctl.yaml
5  apply test-pvc.yaml + a pod              → PVC Bound on azure disk
6  make setup-cluster (again)               → ≤2 min, no "Creating"
7  make setup (aks mode)                    → stops with the R9 message
8  time make cleanup-cluster                → exit 0
9  az resource list --tag project=sre-stack → empty
10 make cleanup-cluster (again)             → exit 0
11 git diff main -- infra/eksctl.yaml infra/scripts/cluster/*.sh → empty
```

`/speckit.tasks` turns that into 12 tasks; the interesting part is the
order — prove the risky bits before writing the bulk:

```markdown
T01 .env: AZURE_*/AKS_* block (placeholders, no secrets)
T02 Prove it small: create a 1-pool throwaway cluster with a taint and
    a spot VM; check quota. If the taint syntax fails → STOP, replan.
T03 common.sh: repo root, source .env, subscription check, tag helper
T04 setup-cluster.sh (check-then-create RG, cluster, 4 pools)   [P]
T05 cleanup-cluster.sh (delete RG if present, wait, tolerate absent) [P]
T06 infra/aks/gp2-storageclass.yaml                              [P]
T07 makefile: aks branches + R9 guard messages
T08 README: AKS section        [P]
T09 AGENTS.md: new layout line [P]
T10 make lint + local checks (quickstart 1, 11)
T11 Full quickstart run on the sandbox subscription, output captured
T12 Evidence into PR, plan.md updated if reality disagreed
```

`[P]` marks tasks the agent can do in parallel.

Then the cross-check:

```
> /speckit.analyze

| ID | Severity | Finding |
|----|----------|---------|
| A1 | HIGH     | Spec R4 (tags) has no task asserting tags actually
|    |          | land on the created resources; S2 depends on it |
| A2 | LOW      | quickstart step 5 needs a committed test-pvc.yaml —
|    |          | not in the file list |
```

Viknesh fixes both in the files (T11 gains a tag assertion; the test
manifest joins the file list) and posts: "001 plan ready."

**16:20, on the PR:** Abishek reads plan + research + the analyze output.
One comment — "cleanup waits for the resource-group delete to finish,
right? Async delete is the classic leftover-resources bug" — Viknesh
points at the `--wait` in T05's description. ✅ `plan-approved` label,
16:30. Building may start.

---

## 6. Tuesday — build and verify

```
> /speckit.implement

● Prerequisites: plan-approved label ✔  make lint baseline ✔
● T01 ✔
● T02 throwaway cluster: taint syntax OK via --node-taints; spot quota
  OK (need 14 vCPU, have 32). Cluster deleted. ✔
● T03–T09 ✔
● T10 make lint PASS; git diff main -- eks files: empty ✔
● T11 quickstart run 1: FAILED at step 5 — test PVC stuck Pending.
  Cause: gp2 storage class applied before the Azure disk driver's node
  pods were ready on a brand-new cluster. Fix: setup-cluster.sh now
  waits for the csi-azuredisk-node daemonset before applying the class.
  plan.md updated (see Deviations). Re-run: all 11 steps green. ✔
● T12 evidence posted ✔
```

The deviation note the agent added to `plan.md` (this is the habit that
matters — the plan always matches what was actually built):

```markdown
## Deviations
- T11: added a wait for the Azure disk driver daemonset before applying
  the gp2 storage class. On a fresh cluster the class existed before the
  driver did and the first PVC hung. Constitution still satisfied
  (script remains re-runnable). AGENTS.md gained a line so no agent
  trips on this again.
```

Evidence block pasted into PR #102:

```
quickstart run 2 — Tue 8 Sep, sandbox subscription
1  make lint ................................. PASS (21s)
2  make setup-cluster ........................ 11m48s, exit 0
3  nodes: app ✔ persistent ✔ o11y ✔ loadgen ✔ (+system, unlabelled)
4  taints match eksctl.yaml .................. ✔
5  test PVC Bound, pod wrote a file .......... ✔ (screenshot)
6  setup-cluster again ....................... 1m37s, no "Creating"
7  make setup (aks) .......................... stops: "aks mode: only
   the cluster exists yet — apps arrive with story 002"
8  make cleanup-cluster ...................... 8m12s, exit 0
9  az resource list --tag project=sre-stack .. empty
10 cleanup-cluster again ..................... exit 0 ("already gone")
11 git diff main -- <eks files> .............. empty
```

PR marked **ready for review**, Tue 15:10.

---

## 7. Tuesday afternoon — review and merge

**Agent review** (runs in CI when the PR goes ready; posts as a PR
review):

> **[IMPORTANT]** `cleanup-cluster.sh:19` — the resource-group existence
> check swallows *all* az errors, so an expired login also prints
> "already gone" and exits 0. Distinguish "not found" from other errors.
>
> **[NIT]** `.env` — `AKS_O11Y_NODE_COUNT=1` has no comment saying story
> 003 is what will use it; future readers may "clean it up".
>
> Spec check: R1–R9 each traced to a diff hunk ✔. Plan matches diff, one
> deviation, recorded ✔. Constitution: no violations ✔.

> **Viknesh:** Both taken. Auth errors now exit 1 with the az message;
> comment added. Evidence re-run for cleanup only. Commit `d4e5f6a`.

**Human review:**

> **Rijo:** Diffed the branch against the spec side by side. Every
> requirement is visible in the evidence; nothing outside the plan's file
> list changed; the R9 guard message reads well. The agent finding about
> swallowed az errors was real — good catch, good fix. ✅ Approved.

Branch protection is satisfied (one human approval + green CI), and the
PR **squash-merges** Tue 17:45. The `specs/001-aks-cluster/` folder
merges with the code — the story's permanent record lives in git.

---

## 8. Wednesday 09:30 — daily sync (15 min)

- **Demo (3 min).** Viknesh shows the recorded run: nodes with labels, a
  PVC binding, the empty resource list after cleanup. Rijo confirms the
  success criteria and closes #101 with links to the PR. Aman: baseline
  accepted, this is now what story 002 builds on.
- **Converge.** Viknesh ran `/speckit.converge` on `main` after merge; it
  found two things: the o11y/loadgen pools are created but never
  exercised (story 003/010 will), and Istio 1.17.2's support window
  doesn't include Kubernetes 1.33 — filed as new issue #103
  "istio upgrade", parked until story 002 proves whether it matters.
- **Next story.** Issue #104 "Apps on AKS" accepted; hats rotate: Owner
  Abishek, Architect Rijo, Builder Viknesh.
- **Metrics row** appended to #101:

| Accepted → merged | Rework after human review? | Analyze findings | Converge findings | Tasks |
|---|---|---|---|---|
| 2 days | No (agent review caught the one defect) | 1 HIGH, 1 LOW | 2 (1 → new issue) | 12 |

---

## 9. Friday — weekly retro (45 min, replaces that day's sync)

**Went well:** the T02 "prove it small first" task saved the day —
taint syntax worked but would have been found on task 8 of 12 otherwise.
The two-day clock held. The agent review caught a real bug before a human
read a line.

**Didn't:** the disk-driver race cost ~2 hours; it's a *class* of bug
(fresh-cluster ordering), not a one-off. The evidence block is prose in a
PR description — fine for one story, unsearchable for twenty.

**Changes filed (each its own PR):**

1. Plan template gains a mandatory "ordering hazards on a fresh
   environment" line under Risks. (Rijo)
2. Evidence moves to a committed file, `specs/<nnn>/evidence.md`, and
   quickstart steps that can be scripted become a `make verify-aks`
   target. Framework doc bumped to reflect it. (Viknesh)
3. Constitution: "a destroy script distinguishes 'already gone' from
   'could not check'" — promoted straight from the agent-review finding,
   so it's now enforced everywhere instead of re-found each story.
   (Abishek)

**Aman's closing note:** "Two days, four files of record, and I only had
to show up twice for five minutes. Write that sentence at the top of
whatever we send the other teams."

---

## What each person actually did

| | Rijo (Owner) | Abishek (Architect) | Viknesh (Builder) | Aman (Sponsor) |
|---|---|---|---|---|
| Wrote | story #101, spec.md | 2 spec comments, 1 plan comment, retro change 3 | plan, research, tasks, code, evidence, deviation note | — |
| Approved | final PR | spec, plan | — | story, result |
| Ran | specify, clarify | (read analyze output) | plan, tasks, analyze, implement, converge | — |
| Meeting time | 3 × 15 min + retro | 3 × 15 min + retro | 3 × 15 min + retro | 2 × 15 min + retro |
