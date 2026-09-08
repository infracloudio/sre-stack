# SRE Stack
This repository provisions sufficiently-complex microservice demo applications such as:
- [instana/robot-shop](https://github.com/instana/robot-shop)
- [jaeger/hotrod](https://github.com/jaegertracing/jaeger/tree/main/examples/hotrod)

Along with standard observability tooling such as:
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) contains:
	- prometheus-operator
	- grafana
	- kube-state-metrics
- [Loki](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack) 
- [Tempo](https://github.com/grafana/helm-charts/tree/main/charts/tempo)
- [Opentelemetry](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector)
- [Grafana/Beyla](https://github.com/grafana/beyla)
- [groundcover.com/Caretta](https://github.com/groundcover-com/caretta)

## Scenarios
`sre-stack` contains carefully crafted fault injection scenarios to effectively disrupt operations of the demo-applications.
Using this repo we create the following feedback-loop:
 - Fault-injection
 - Fault-detection using various o11y tooling
 - Root Cause Analysis using classic / advanced tools
 - Fault mitigation strategies, both long-term and short-term
 
 Available scenarios:
 - [scenario-01](scenarios/scenario-01/README.md)
 - [scenario-02](scenarios/scenario-02/README.md)
 - [scenario-03](scenarios/scenario-03/README.md)
 - [scenario-04](scenarios/scenario-04/README.md)

### Load-generators:
 - [Robot-shop](scenarios/load-gen/README.md)
 - [Rabbitmq](scenarios/scenario-04/README.md)

## Prerequisites
- [kubectl CLI](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [helm CLI](https://helm.sh/docs/intro/install/)
- [git CLI](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [make (GNU make 4.3 or +)](https://www.gnu.org/software/make/)
- [jq](https://jqlang.github.io/jq/download/)
- [k3d](https://k3d.io/v5.6.0/#installation)

## Setup & Configuration
The core configuration is stored in the `.env` file.
This is consumed by the `makefile` to provision infrastructure and deploy applications.

### Configuration
Configurations are grouped in the `.env` file in self-explanatory sections. Most values are set to their sane defaults and would not
need changing for initial setup.

Core provisioning and deployment choices are expressed in the following two variables:

- `STACK_MODE = [ eks| local ]`
  - Choice of deploying the stack to either `aws/eks` or using a `k3d` cluster on local linux systems.
- `APP_STACK=[ robot-shop | hotrod | all ]`
  - Choice of deploying either or both:
    - [instana/robot-shop](https://github.com/instana/robot-shop)
    - [jaeger/hotrod](https://github.com/jaegertracing/jaeger/tree/main/examples/hotrod)

### Setup
Provisioning lifecycles are controlled by `Make` commands.
Prefix all commands with `make` keyword.

Example: `make setup`

### AWS - EKS Lifecycle Commands
For EKS based provisioning you need to setup `AWS_PROFILE` pointing to the correct AWS account. 

Following AWS credentials for the said `profile` should be added to `~/.aws/credentials`
```
[profile-name]
aws_access_key_id=*************
aws_secret_access_key=*********
```

```
EKS setup/deploy/cleanup commands:
	setup                               - End-to-end setup on EKS
	start-cluster                       - start EKS Cluster
	setup-cluster-autoscaler            - Setup node auto scaling
	setup-observability                 - Setup monitoring/observability
	setup-optional-otel                 - Setup OpenTelemetry
	setup-istio                         - Setup istio and ingress
	setup-db-rds-mysql                  - Setup RDS - mysql
	setup-rabbitmq-operator             - Setup rabbitmq-operator
	setup-robot-shop                    - Deploy robot-shop app-stack.
	setup-optional-rmq-consumer-scaling - Setup keda to scale dispatch (optional)
	setup-gateway                       - Setup Ingress gateway
	cleanup-cluster                     - Cleanup cluster
	cleanup                             - Clenaup all resources and EKS cluster
```
### Local - k3D Lifecycle Commands

Just make sure `k3d` is installed, cluster-creation and lifecycle are handled by the following commands:

```
Local (k3D) setup/deploy/cleanup commands:
	setup-local                         - Setup end-to-end stack on local k8s (k3d)
	setup-local-cluster                 - Setup local k3d cluster
	cleanup-local                       - Cleanup end-to-end stack on local k8s (k3d)
```

### Utility Commands:

```
  get-service-endpoints               -  Print exposed endpoints (works for both local/eks)
  install                             -  Install all dev dependencies and CLIs (idempotent; DRY_RUN=1 to preview)
  install-check                       -  Report which dev dependencies are missing (no changes)
```

Or bootstrap a new machine in one step: `make install` (see
`infra/scripts/dev/install-deps.sh` for what it installs).

### Contribution Guide

This repo is built with AI coding agents, and the process is designed
around that. In one sentence: **write down what you want, get a yes, let
the agent build it, prove it works, get one more yes, merge.** Everything
below is that sentence in more detail. The full process is in
[`docs/sdlc/framework.md`](docs/sdlc/framework.md); a complete worked
example is in
[`docs/sdlc/example-walkthrough-001-aks-cluster.md`](docs/sdlc/example-walkthrough-001-aks-cluster.md).

#### 1. Set up your machine (once per clone)

```
make install-check   # shows what is missing, changes nothing
make install         # installs it, and switches on the pre-commit checks
```

`make install` gives you the lint tools, the cloud CLIs, and the
[Spec Kit](https://github.com/github/spec-kit) CLI at the version this
repo expects. It also enables the repo's git pre-commit hooks. Those hooks
are not optional: `make lint` and the agent's own edit hooks refuse to
work until they are on.

Then open the repo in your AI coding tool. Claude Code, Codex, OpenCode
and Devin are all supported. The tool reads [`AGENTS.md`](AGENTS.md) by
itself, which tells it how this repo works, and it finds the
`/speckit-*` commands already installed (OpenCode spells them
`/speckit.*`).

#### 2. Start with a story, not with code

Open a GitHub issue using the **Story** template. It has four short
sections, written in plain language, with no technical decisions:

- **Problem**: what can't be done today, and who cares.
- **Outcome**: the one thing you will be able to see working when it's
  done. If you need the word "and" to describe it, it is two stories.
- **Out of scope**: what this story deliberately leaves alone.
- **Must keep working**: what must not break.

A story should be finishable, including a real run, in one or two days.
The Sponsor reads it at the daily sync and says yes, no, or "split it".
On yes, the issue gets the label `intent:accepted` and three people are
named: an **Owner** (writes the spec), an **Architect** (approves the spec
and the plan) and a **Builder** (runs the agent and ships the PR). The
person who approves something is never the person who wrote it.

If you are outside the team, still start with the issue. A maintainer
will handle the labels and the roles with you.

#### 3. Spec, then plan, then build, all with the agent

Each step is one command in your agent, and each produces a file that is
committed to the story's folder `specs/<nnn>-<slug>/`:

| Step | Who | Command(s) | Produces | Approved by |
|---|---|---|---|---|
| Spec | Owner | `/speckit-specify`, then `/speckit-clarify` | `spec.md`: what to build and how we'll know it works | Architect, label `gate:spec-approved` |
| Plan | Builder | `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze` | `plan.md`, `tasks.md`, an analysis of gaps | Architect, label `gate:plan-approved` |
| Build | Builder | `/speckit-implement` | the code, one task at a time | a human reviewer, on the PR |

A few rules that make this work:

- Push the branch and open a **draft PR** as soon as the spec exists.
  That PR carries everything until it merges.
- A spec with a `[NEEDS CLARIFICATION]` marker still in it is not done,
  and CI will say so.
- **No code before the plan is approved.** CI checks this: if the PR
  changes anything outside the story's `specs/` folder and the
  `gate:plan-approved` label is missing, the PR goes red. Spec and plan
  commits are always fine.
- If reality forces a change to the plan, change `plan.md` in the same
  commit and say why.
- Paste the proof into the PR: `make lint` output, command output,
  screenshots of the thing working. Add the label `evidence:attached`.
  "Should work" does not count; output does.

#### 4. Review and merge

Mark the PR ready. One person who did not write it and did not approve
the plan reads the spec, the plan, the proof and the diff, and approves.
CI must be green. Squash-merge; the `specs/` folder merges with the code
and becomes the story's permanent record. Afterwards run
`/speckit-converge` on `main` to see what the code still misses versus
the spec; anything found becomes a small follow-up or a new story.

#### What the machines check for you

You do not have to remember all of the above. The checks below run on
their own, and every one of them prints what is wrong and what to do:

- **Before the agent edits a file**: it is refused if the file is a
  guardrail or generated file (listed in
  [`agent/hooks/protected-paths.txt`](agent/hooks/protected-paths.txt)),
  or if the content contains something that looks like a credential.
- **After every agent edit**: lint findings are fed straight back to the
  agent to fix.
- **At `git commit`**: the same secret, protected-path, lint and
  allowlist checks run on what you are committing.
- **On every push to a PR**: CI runs `make lint`, rejects leftover
  clarification markers, and enforces the plan gate. `main` will not
  accept a merge without green CI and one human approval.

If a check blocks you, it is telling you something real. Do not work
around it. If the check itself is wrong, fix it in its own reviewed PR.
Guardrail files are changed by a human, committing with
`PROTECTED_OVERRIDE=1` and saying why in the PR. How the labels and the
gate behave, step by step, is in
[`docs/sdlc/labels-and-gates.md`](docs/sdlc/labels-and-gates.md).

#### Where to read more

- [`docs/sdlc/framework.md`](docs/sdlc/framework.md): the whole process,
  the roles, the daily sync, what we measure.
- [`docs/sdlc/example-walkthrough-001-aks-cluster.md`](docs/sdlc/example-walkthrough-001-aks-cluster.md):
  one story from idea to merge, every file and conversation shown.
- [`docs/sdlc/labels-and-gates.md`](docs/sdlc/labels-and-gates.md): the
  five labels, what CI checks at each state, a worked example.
- [`AGENTS.md`](AGENTS.md): what every agent reads first; add a line when
  agents repeat a mistake.
- [`.specify/memory/constitution.md`](.specify/memory/constitution.md):
  our standing rules; the agent reads it before every plan.
- [`agent/policies/`](agent/policies/): review, security and MCP server
  policies.
