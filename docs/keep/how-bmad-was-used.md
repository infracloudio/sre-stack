# How we used BMAD to turn issue #91 into an epic and stories

This page records, in order, what we ran, what each step produced, and where a
person decided something. It is written from the session records of 23 and 24
October 2026 and from the files in the repo. It states only what we can show.

BMAD is a set of skills for Claude Code (commands such as `/bmad-spec`). Each skill
does one planning job and writes its result to a file. A person reviews each
result before the next skill runs.

## Summary

| # | Step | BMAD skill | Main output | Who decided |
|---|---|---|---|---|
| 1 | Ask which steps to run | `/bmad-help` | Plain summary of issue #91 and a plan | user changed the scope (AI provider, Slack only) |
| 2 | Research: is the issue buildable? | `/bmad-deep-recon` (technical research) | `research.md` sections 1 to 4, three digests | user set the question |
| 3 | Try it live on AKS | none (manual run with the agent) | `research.md` section 5 and the `tryout/` files | user ran and judged the result |
| 4 | Write the spec | `/bmad-spec` | `SPEC.md`, `glossary.md`, `delivery-slices.md`, `.memlog.md` | user answered 5 open questions; a second agent reviewed |
| 5 | Record architecture decisions | `/bmad-architecture` | AD-008 to AD-013 in `docs/architectural-decisions.md` | user approved each AD one at a time |
| 6 | Break the spec into stories | `/bmad-spec` (story breakdown) | `stories.yaml`, 13 stories | user approved each story one at a time |
| 7 | Put the stories on GitHub | `gh` scripts (no BMAD skill) | project 15, issues #122 to #134, one comment on #91 | user approved the script and the text |
| 8 | Rewrite in plain English and document | none | this page, the architecture page, the story flow page | user asked for it |

## Step by step

### 1. `/bmad-help`: what should we run?

We started by asking `/bmad-help` which BMAD agents and steps to use to turn issue
#91 into an epic with stories, tracked in a GitHub Project. It read the issue and
the BMAD skill catalogue (`_bmad/_config/bmad-help.csv`), then explained the issue
in simple terms and proposed a path.

The user then changed the scope, which became the first of the twelve decisions in
the spec:

- AI is Fireworks (model GLM-5.3 Flash), not Ollama or OpenAI.
- Notifications are one Slack channel only.

Output: a revised scope table. No file was written.

### 2. `/bmad-deep-recon`: research before any spec

We asked for a technical research run with this question: is the Keep design in
issue #91 buildable as written? The skill split the work into parts, sent
sub-agents to read documentation, and read the Keep and Helm chart source itself.

Outputs, all under
`_bmad-output/planning-artifacts/research/technical-keep-keephq-helm-on-kubernetes-for-sre-s-2026-10-23/`:

- `research.md`, sections 1 to 4 (install, AI backend, Alertmanager and Grafana,
  Slack), with a confidence level for each claim.
- `digests/`, three summaries from sub-agents (second-hand, web based).
- `imports/`, shallow clones of the Keep source (commit `e5cd869`) and the Helm
  charts (commit `734018e`). Claims marked "verified in code" come from reading
  these.

Result: buildable, with five things the issue had to state explicitly.

### 3. Live try-out on AKS

Reading code is not the same as running it, so we ran the whole design on the AKS
cluster by hand with the agent: Keep from the Helm chart, Alertmanager pointed at
Keep, a correlation rule, a workflow that calls Fireworks and posts to Slack, and a
cart OOM fault to trigger it.

Outputs:

- `research.md` section 5, with each finding marked verified, failed or open.
- `tryout/`: the values, rules, workflow and smoke-test script we used.
  Story builders start from these files.

The try-out corrected two claims from step 2 (the workflow-side AI path and the
enterprise tier). It also found three blockers the issue did not know about:
Alertmanager was off, no robot-shop alert rules existed, and the Keep websocket
fails through a port-forward.

The spec treats section 5 as fact. Whatever it marks failed or open stays open.

### 4. `/bmad-spec`: the spec

We gave the skill the issue, the twelve decisions that override the issue, and the
repo rules from `AGENTS.md`. It asked us to read `AGENTS.md` first, then:

- kept every decision as one line in `.memlog.md`, an append-only log. The log is
  the source; `SPEC.md` is built from it;
- wrote `SPEC.md` (capabilities CAP-1 to CAP-12, constraints, non-goals, success
  signal), `glossary.md` and `delivery-slices.md`;
- ran two self-checks: one for coherence and one that nothing from the issue was
  dropped. The second check found one lost item (the scenario script must end by
  pointing at Keep), and we added it.

Five open questions went to the user: login type, a sub-path or its own address,
how to load providers and workflows, whether Alertmanager is on for every
environment, and image pinning. The answers are in the decision log.

A second agent then reviewed the spec. We shared the spec, the open questions and
the current status in a handoff file. It returned ten findings. The important ones:

- provider secrets would have leaked into values files (Keep does no variable
  substitution), so `setup-keep` now builds them at install time;
- `make setup-aks` would break when secrets are missing, so Keep is skipped with a
  message;
- one success test contradicted itself;
- the "own address" choice needed a decision;
- two stories were too big and were split (5a/5b and 6a/6b).

We applied all ten and recorded the answers. We did not write stories yet, because
the architecture step had to come first.

### 5. `/bmad-architecture`: the decisions that stories share

The architecture skill works in coaching mode. It lays out the real alternatives
for each decision, states a recommendation, and waits for the user. We wrote the
decisions into `docs/architectural-decisions.md`, one entry at a time, each only
after approval:

- AD-008 secrets, AD-009 login and API keys, AD-010 the address,
- AD-011 configuration as files, AD-012 Alertmanager, AD-013 install baseline.

The second agent's feedback also revised the first drafts (AD-008 and AD-009 were
changed before they were approved). Each AD lists the alternatives we rejected and what we gave up.
The ADs fix what two stories built separately could otherwise choose differently.

### 6. Story breakdown

The `bmad-spec` skill can break a spec into stories. Its output file is
`stories.yaml`. The user set four rules first:

- a human reviews every story spec before work starts;
- work pauses after every story, one pull request at a time, squash-merged;
- the four lower-priority stories come after the nine main ones;
- every story carries the same builder note (start from `tryout/`, run `make lint`,
  prove it live on AKS, never print a secret, stop the cluster at the end, author and
  approver differ).

We then showed the stories to the user one at a time. Each was approved or changed
before the next. During review, claims were checked against the Keep source and the
pinned chart, and that changed several stories:

- Story 3: under `NOAUTH` Keep accepts any key, so "the key is accepted" proves
  nothing. The real key check moved to story 6a.
- Story 5b: incident triggers take no condition, so the "resolved" test goes on the
  action, with a marker so it posts once.
- Story 6a: the websocket cannot work through a port-forward, so live updates moved
  to story 6b, and the `NEXTAUTH_URL` move is recorded in AD-009.
- Story 8: Grafana authenticates with the Digest scheme, not `X-API-KEY`.
- Story 9: Keep cannot take Kubernetes events in as alerts, so the story changed to
  add events to the AI summary.
- Story 10: Loki's built-in ruler can send to the existing Alertmanager.
- Story 11: the AI Summary button is open-source UI code, not the enterprise tier.

Some of these source checks are written down in `research.md` section 6.

### 7. GitHub setup

There is no BMAD skill for this step. We used `gh` scripts, shown in full and
approved before they ran. They are safe to run again, because they record each
created item and skip it next time.

- One GitHub Project, "sre-stack: Keep alert management" (project 15).
- Thirteen issues, #122 to #134, each a sub-issue of #91, type Task, label `intent`.
- Issue #91 added to the project. One comment on #91 summarising the new scope. Its
  text is unchanged.
- Links to files use a commit SHA, so they keep working after the branch is merged.

### 8. Plain-language pass

The architect found the stories hard to follow. We rewrote every story with the same
sections (why, done when, not in this story, must not break, decisions followed, live
checks), added the story flow page, and wrote the architecture page.

## Files this process produced

| File | What it is |
|---|---|
| `_bmad-output/planning-artifacts/research/technical-keep-.../research.md` | research and the live try-out |
| `.../tryout/` | files builders start from |
| `_bmad-output/specs/spec-keep-alert-management/SPEC.md` | requirements |
| `.../glossary.md`, `.../delivery-slices.md` | terms and story flow |
| `.../stories.yaml` | the 13 stories |
| `.../.memlog.md` | the decision log (the source of the SPEC) |
| `docs/architectural-decisions.md` (AD-008 to AD-013) | architecture decisions |
| `docs/keep/architecture.md` | the whole design in one page |
| GitHub project 15, issues #122 to #134 | tracking |

## The agent Mary

Mary is BMAD's business analyst agent (skill `bmad-agent-analyst`). She is a
persona that greets you and offers a menu:

| Code | What it does |
|---|---|
| BP | guided brainstorming |
| MR, DR, TR | market, domain and technical research (all run `bmad-deep-recon`) |
| TS | choose between technologies |
| CR, UV | competitor and user-voice research |
| CB | product brief |
| WB | working-backwards PRFAQ |
| PC | set up the repo's agent instructions |

What the records show: the session records for this repo on the machine where the
work was done contain no use of Mary. There is no `/bmad-agent-analyst` command, no
Mary greeting, and no Mary mention in any `.memlog.md` in `_bmad-output/`. The
research session starts with `/bmad-deep-recon` typed directly, using the technical
research type. That is the same skill Mary's menu item TR (technical research)
starts, so the research step is the part of the work Mary's role covers. Everything
after it (spec, architecture, stories) belongs to other skills, and Mary has no menu
item for them.

If Mary was started in a session that is not recorded here (another machine, another
folder or Claude Code on the web), add the date and what she produced to this
section.

If you want the analyst persona for the next epic, start `/bmad-agent-analyst` and
pick TR. The result should be the same files.

## How to repeat this for another epic

1. `/bmad-help` with the issue link, to get the plan.
2. `/bmad-deep-recon` on the one question that decides whether the idea is buildable.
3. A live try-out of the risky parts. Record what is verified, failed and open.
4. `/bmad-spec` with the issue, your decisions and `AGENTS.md`. Answer its open
   questions. Have a second agent review the result.
5. `/bmad-architecture` for the decisions that stories share. One at a time.
6. Story breakdown into `stories.yaml`. Check every claim against source code.
7. Create the GitHub project and issues with a script you review first.

What worked well:

- The try-out before the spec gave facts instead of guesses.
- A second agent found problems the first agent missed (secret leaks, a broken
  `setup-aks`, a self-contradicting test).
- Checking stories against the Keep source reshaped five stories before any code was
  written.

What to do better next time:

- Write the stories in plain English from the start, with the same sections in each.
- Write the architecture page early. The architect should not need to read six AD
  entries to understand the flow.
