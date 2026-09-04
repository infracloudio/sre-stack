# How We Build: AI-Native SDLC with Spec Kit

Version 0.2 · Owner: Rijo · Reviewers: Abishek, Viknesh · Sponsor: Aman

This document explains how our team builds software with AI coding agents.
Read it top to bottom once; after that you only need the checklist at the
end. A full worked example — one story taken from idea to merge, with every
file and every conversation shown — is in
[`example-walkthrough-001-aks-cluster.md`](./example-walkthrough-001-aks-cluster.md).

---

## 1. The idea

An AI agent writes the code. Because of that, writing code is no longer the
slow part — deciding what to build, and checking it was built right, are.
So we spend our human time on exactly two things:

1. **Writing down what we want before any code exists.** These write-ups
   are ordinary markdown files, committed to git. The agent reads them and
   builds from them.
2. **Saying yes at a few fixed points.** A "yes" is a named person
   approving a file or a pull request. Nothing moves forward without one,
   and the approval is recorded in GitHub, so months later we can see who
   decided what, and why.

Everything else — research, drafting, coding, testing, re-testing — the
agent does, and a person checks.

One rule makes this work: **every story must be finished in one or two
days**, including running it for real. The agent is fast enough that if a
story takes longer, the story was too big — not the team too slow. Small
stories keep the whole project small enough to hold in your head.

---

## 2. The team

Four people. Each story assigns three hats; the fourth (Sponsor) is
standing.

- **Sponsor** — Aman. Accepts or rejects new stories. Doesn't join the
  day-to-day.
- **Owner** — writes the story and its spec. Answers "what do we want?"
- **Architect** — approves the spec and the plan. Answers "is this the
  right way?"
- **Builder** — makes the plan, runs the agent, ships the pull request.

The hats rotate story by story. Only one hard rule: **the person who
approves something cannot be the person who wrote it.** For the first
migration story: Rijo is Owner, Abishek is Architect, Viknesh is Builder.

---

## 3. The tool: Spec Kit

[Spec Kit](https://github.com/github/spec-kit) is a small open-source
toolkit from GitHub. You install it once, and it adds commands to your AI
agent — Claude Code, Codex, OpenCode and Devin are all supported, and the
commands are the same in each. The commands walk you through writing the
files, in order:

| You type | The agent produces |
|---|---|
| `/speckit.specify <your story text>` | a branch, a folder `specs/001-<name>/`, and `spec.md` — what to build and how we'll know it works |
| `/speckit.clarify` | questions back at you about anything the spec left vague; your answers get written into the spec |
| `/speckit.plan` | `plan.md` — how to build it: files to change, tools, versions, risks |
| `/speckit.tasks` | `tasks.md` — the plan broken into a checklist of small tasks |
| `/speckit.analyze` | a report of gaps and contradictions between spec, plan and tasks |
| `/speckit.implement` | the actual code, ticking off the tasks |
| `/speckit.converge` | after merge: a check of what the code still misses versus the spec |

There is one more file, written once per repo, not per story:
`.specify/memory/constitution.md` — our standing rules (things like "every
script must be safe to re-run" and "no secrets in git"). The agent reads it
before every plan and follows it. When a rule changes, we change that file
by pull request, like code.

---

## 4. The rhythm: one daily call

We have exactly one recurring meeting: a **15-minute daily sync**, same
time every day, all four of us (Aman optional, required only when a new
story needs accepting). In it we:

1. Accept or reject new stories (Sponsor's call), and hand out the three
   hats for each accepted one.
2. Approve anything waiting for an approval that got stuck in async.
3. Look at anything that finished yesterday — a 2-minute screen share of
   the thing working.
4. Say blockers out loud.

Everything else is asynchronous, on the pull request, with one rule:
**if someone asks for your review or approval, respond the same day.**
With 1–2 day stories, a day of silence is half a story lost.

Once a week the sync extends to 45 minutes for a **retro**: we look at how
the last stories went and change the process — the constitution, the
templates, this document. Every change is a pull request, so the process
itself has a history.

---

## 5. The life of a story

This is the whole process. A story goes through these steps in order.
Steps 1–4 are typically the morning of day one; step 5 runs through day
two; steps 6–8 close it out.

### Step 1 — Write the story (Owner, ~30 minutes)

A story is a GitHub issue, written in plain language, with four short
sections:

- **Problem** — what can't we do today, and who cares.
- **Outcome** — what you will be able to *see working* when it's done.
- **Out of scope** — what this story deliberately does not touch.
- **Must keep working** — what must not break.

No solutions, no technology choices — those come later. Draft it with an
agent if you like, but edit it back into your own words. The test for
size: the outcome is **one** thing, showable in a couple of minutes, and
you believe agent-plus-Builder can deliver it in 1–2 days. If you can't
say the outcome without the word "and", it's two stories.

### Step 2 — Get it accepted (Sponsor, at the daily sync)

The Sponsor reads the story at the sync and says yes, no, or "split it".
On yes, the issue gets the label `intent:accepted` and the three hats are
assigned. That's the first approval.

### Step 3 — Turn it into a spec (Owner, ~1 hour)

The Owner opens the agent on `main` and runs `/speckit.specify`, pasting
the accepted issue text. The agent creates a branch and a `spec.md`: the
story restated as concrete, testable statements — "given a fresh
subscription, `make setup` exits 0 and prints a URL that opens" — plus
numbered success criteria.

Wherever the agent wasn't sure, it leaves a marker in the text:
`[NEEDS CLARIFICATION: ...]`. Run `/speckit.clarify`: the agent asks you
each open question, one at a time, and writes your answers into the spec.
A spec with markers still in it is not done.

Push the branch and open a **draft pull request**. This PR will carry
everything the story produces — spec, plan, code — until it merges.

### Step 4 — Spec approved (Architect, same day, async)

The Architect reads `spec.md` on the PR and checks three things: it's
buildable, it's small enough, and it doesn't contradict the constitution.
Comments are PR comments; fixes are commits. When satisfied, the
Architect approves the spec with a PR comment and the label
`gate:spec-approved`. Second approval.

If comments are still flying after a few rounds, take it to tomorrow's
sync — don't let a thread run for days.

### Step 5 — Plan, then build (Builder, the bulk of the 1–2 days)

The Builder takes over the branch (use a separate git worktree so your
other work isn't disturbed) and runs three commands:

1. `/speckit.plan` — the agent writes `plan.md`: which files change, which
   tools and versions (pinned), what could go wrong, and how the result
   will be verified. It also writes a short verification script — the
   exact commands a reviewer will run to see the story working.
2. `/speckit.tasks` — the plan becomes `tasks.md`, a checklist.
3. `/speckit.analyze` — the agent cross-checks spec vs plan vs tasks and
   lists gaps ("the spec requires tagging, no task does it"). Fix the
   gaps in the files before writing any code.

Then get the **plan approved**: the Architect reads `plan.md` and the
analyze report on the PR — async, or in five minutes at the sync — and
applies the label `gate:plan-approved`. Third approval. **No implementation
before this label**, and CI enforces that mechanically. Here is how: a
GitHub Actions job runs on every push to the PR. It asks the GitHub API
which labels the PR carries, and diffs the branch against `main` to see
which files changed. If any file *outside* the story's `specs/<nnn>-…/`
folder has changed — that is, actual code — and the `gate:plan-approved`
label is not present, the job fails, and branch protection won't let a
red PR merge. So spec and plan commits flow freely, but the first code
commit pushed before approval turns the PR red until the label appears
(the job re-runs when labels change, so no re-push is needed). The same
job also fails the PR if any `[NEEDS CLARIFICATION]` marker survives in
the spec, and runs `make lint` on every push. The label itself is
protected socially, not technically — anyone *could* apply it, but it's
applied in public on the PR, and the retro reviews who approved what.

Now `/speckit.implement`. The agent writes the code and works through the
checklist, verifying as it goes — lint, template rendering, and the real
thing (for us: actually creating the cloud resources and tearing them
down). The Builder watches, steers, and re-runs. Two habits:

- If reality forces a change to the plan, change `plan.md` in the same
  commit and say why. The plan must match what was actually done.
- Paste the proof into the PR: command output, timings, a screenshot of
  the thing working. "Should work" doesn't count; output does.

### Step 6 — Review and merge (Reviewer, same day)

The Builder marks the PR ready. Two reviews happen:

1. **Agent review** — CI runs an agent over the diff with our checklist
   and the constitution. It posts findings ranked by severity. Findings
   are advice, not a blocker; the Builder fixes or answers each one.
2. **Human review** — one person approves. It's whoever holds neither the
   Builder nor the plan-Architect hat for this story (usually the Owner).
   With the spec, the plan, the agent findings and the proof already on
   the PR, this is a 20-minute read, not an afternoon. This is the fourth
   approval, and the one GitHub branch protection actually enforces.

Squash-merge. The `specs/001-<name>/` folder merges with the code — that's
the story's permanent record.

### Step 7 — Converge (Builder, 10 minutes)

On `main`, run `/speckit.converge`. The agent compares the merged code
against the spec and lists anything still missing or newly discovered.
Each item either gets fixed in a small follow-up PR the same day, or
becomes a new story issue. This is how the next story gets found.

### Step 8 — Show it (next daily sync, 2 minutes)

Run the verification script live, or show the recorded output. The Owner
confirms the success criteria are met and closes the issue, linking the
merged PR. The Sponsor's nod here is what lets the result be used in the
shared demo environment. Done.

---

## 6. Guardrails that run by themselves

People approve; machines enforce. Three mechanisms, set up once:

- **Branch protection** on `main`: changes arrive only by PR, one human
  approval required, CI must be green.
- **CI** on every PR: the GitHub Actions job described in step 5 of the
  story's life — `make lint`, no surviving `[NEEDS CLARIFICATION]`
  markers, no code changes before the `gate:plan-approved` label — plus the
  agent review pass.
- **Hooks** in the agent itself: block edits to protected paths, block
  committing secrets, and stop the agent from "fixing" a failing test by
  editing the test. Same scripts run in git pre-commit, so every harness
  and every human hits the same wall.

If a mistake happens twice, it stops being a review comment and becomes a
constitution rule, a checklist line, or a hook. That's the ratchet that
makes the process better every week.

---

## 7. What we measure

One row per story, appended to the closed issue, reviewed at the retro:

| Measure | Question it answers |
|---|---|
| Days from accepted to merged | Are stories really 1–2 days? |
| Merged without rework after human review? | Are the earlier steps catching problems? |
| Gaps found by `/speckit.analyze` | Are specs and plans lining up before code? |
| Gaps found by `/speckit.converge` | Did we ship what the spec said? |
| Tasks in `tasks.md` | Are stories staying small? (trend must stay flat) |

No dashboards yet. Five numbers, one table, honest trends.

---

## 8. The migration, story by story

Our first project under this process: move sre-stack from AWS to Azure.
Nothing persists in AWS, so it's a clean move. Each row below is one
story — one issue, one branch, one PR, 1–2 days:

| # | Story | You can see... | Needs |
|---|---|---|---|
| 001 | AKS cluster | `make setup-cluster` creates an AKS cluster with our four labelled node pools; `make cleanup` leaves nothing behind | — |
| 002 | Apps on AKS | Istio, gateway, robot-shop and hotrod running; the shop opens in a browser | 001 |
| 003 | Metrics on AKS | Prometheus + Grafana up; dashboards populate | 002 |
| 004 | Logs and traces | Loki, Tempo, OTel, Beyla, Caretta up; traces visible | 003 |
| 005 | Key Vault | no secret values in `.env`; secrets fetched from Azure Key Vault at setup time | 001 |
| 006 | Managed MySQL | robot-shop on Azure Database for MySQL, created/destroyed by our scripts | 002, 005 |
| 007 | DB fault scenario | scenario-02 (connection overload) works against Azure MySQL | 006 |
| 008 | DB dashboard | an Azure Monitor exporter replaces YACE; the RDS dashboard re-pointed | 003, 006 |
| 009 | Autoscaling | AKS node-pool autoscaling + KEDA replace the AWS autoscaler | 002 |
| 010 | All scenarios | scenarios 01, 03, 04 verified on AKS with recorded evidence | 004, 009 |
| 011 | AWS removed | EKS/RDS/YACE files gone; README and CI describe AKS and local only | all |

The order and slicing get confirmed at the first sync; expect the list to
change as converge reports come in. Story 001 runs first on purpose: it
exercises every step above once, on the smallest real outcome.

---

## 9. Getting started (one-time setup)

1. Install: `uv tool install specify-cli` (needs Python 3.11+), plus the
   `az` CLI. Then in the repo: `specify init --here --integration claude`
   (repeat with `codex` / `opencode` / `devin` for those harnesses).
2. Write the constitution with `/speckit.constitution` — start from our
   existing conventions (idempotent scripts, pinned versions, `.env` as
   the only config surface, no secrets in git, workload node labels).
   Architect and Owner approve it by PR.
3. Turn on branch protection, the CI checks and the hooks (section 6).
4. Create the issue template with the four story sections, and the labels
   `intent`, `intent:accepted`, `gate:spec-approved`, `gate:plan-approved`,
   `evidence:attached`.
5. Book the daily sync. Write story 001. Go.

---

## 10. Still to decide

1. Which harness runs the agent review in CI, and with what credentials.
2. Do stories live only in GitHub issues, or mirrored in the enterprise
   tracker?
3. Exact story order for the migration (section 8 is a proposal).
4. Whether Aman wants to see plans too for the first couple of stories,
   or only accept stories and results.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-09-04 | First draft |
| 0.2 | 2026-09-04 | Rewritten in plain linear form; stories cut to 1–2 days; one daily sync replaces separate ceremonies; migration re-sliced into 11 stories |
