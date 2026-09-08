# Labels and gates: how a change is allowed to move

This is the mechanical side of [`framework.md`](./framework.md): the five
labels, who applies them, what the machines check at each point, and one
story followed through every state. Read this when CI is red and you
want to know why, or when you are about to apply a label and want to be
sure it is yours to apply.

---

## 1. The five labels

| Label | Lives on | Applied by | Means | Checked by a machine? |
|---|---|---|---|---|
| `intent` | the story issue | the issue template, automatically | a story has been filed and is waiting for the Sponsor | no |
| `intent:accepted` | the story issue | Sponsor, at the daily sync | the story is worth doing; Owner, Architect and Builder are named | no |
| `gate:spec-approved` | the PR | Architect | `spec.md` is buildable, small enough, and does not contradict the constitution | no (but CI rejects a spec with clarification markers) |
| `gate:plan-approved` | the PR | Architect | `plan.md`, `tasks.md` and the analyze report are sound; code may be written | **yes**: CI fails a PR with code changes and no label |
| `evidence:attached` | the PR | Builder | verification output is on the PR | no |

Two rules apply to every label. **The person applying it did not write
the thing it approves.** And it is applied in public, on GitHub, so the
weekly retro can see who approved what.

---

## 2. What the machines check

Three mechanisms, in the order a change meets them.

### Agent hooks (before and after each edit)

- **Before an edit** the agent is refused if the file is a guardrail or
  generated file (the list is `agent/hooks/protected-paths.txt`), if the
  content contains a credential pattern, or if the clone has no pre-commit
  hooks enabled. The refusal reason is shown to the agent.
- **After an edit** lint and allowlist findings are fed back to the agent
  to fix before it moves on.

Claude Code and Devin run these hooks. Codex and OpenCode have no hook
mechanism, so for them the wall is the next layer down.

### Git pre-commit (every commit, every harness, every human)

`make install` (or `make hooks`) switches this on per clone. It runs the
same scripts as the agent hooks on the staged files: secrets, protected
paths, lint, and the allowlist ratchets. A blocked commit prints why.

A human making a deliberate change to a protected file commits with:

```
PROTECTED_OVERRIDE=1 git commit
```

and explains the change in the PR.

### CI (every push to a PR, and every label change)

Two jobs in `.github/workflows/ci.yml`, both required by branch
protection on `main`:

| Job | What it does | Goes red when |
|---|---|---|
| `lint and validate` | runs `make lint` in strict mode against the PR's base branch | any check fails; a protected file changed and the PR has no `gate:plan-approved` label |
| `gate:plan-approved check` | lists the PR's changed files and labels | a `specs/*/spec.md` still contains `[NEEDS CLARIFICATION`; or a file outside `specs/<story>/` changed and the label is missing |

The gate job re-runs when a label is added or removed, so after the
Architect applies `gate:plan-approved` a red PR turns green without a new
push.

### Branch protection on `main`

Merges need both jobs green and one approving review from someone who is
not the author. Force pushes and deletions are off.

---

## 3. What "outside the story's specs folder" means

The gate is deliberately simple. If every changed file in the PR matches
`specs/<something>/`, the PR is a spec-or-plan PR and needs no label. The
moment any other file changes, including `AGENTS.md`, `README.md`, a
template, the constitution, or a hook, the PR needs `gate:plan-approved`.

That covers two kinds of PR:

- **Story PRs.** The label means "the Architect approved the plan".
- **Process PRs** (a retro change to a template, a constitution
  amendment, a hook fix). There is no plan to approve, so the label means
  "someone other than the author read this and agrees". The Architect of
  the week applies it.

Either way the label does the same job: it records a second person's yes
before code lands.

---

## 4. One story, every state

Illustrative numbers. Story 005, "Key Vault": no secret values in `.env`;
secrets are fetched from Azure Key Vault at setup time.

| When | Who does what | Labels on issue #130 | Labels on PR #131 | CI on PR #131 | Why |
|---|---|---|---|---|---|
| Mon 09:00 | Abishek files the story from the template | `intent` | — | — | template adds the label |
| Mon 09:30 | Aman accepts at the sync; hats: Owner Abishek, Architect Rijo, Builder Viknesh | `intent`, `intent:accepted` | — | — | Sponsor's yes |
| Mon 10:30 | Abishek runs `/speckit-specify` and `/speckit-clarify`; pushes `specs/005-key-vault/spec.md`; opens draft PR #131 | | — | **green** | only `specs/005-key-vault/` changed; no markers left |
| Mon 11:00 | One marker was missed; Abishek pushes the spec with `[NEEDS CLARIFICATION: rotation cadence?]` still in it | | — | **red** (gate job) | marker in `spec.md` |
| Mon 11:20 | Abishek answers it, pushes | | — | **green** | |
| Mon 14:00 | Rijo reads the spec, leaves two comments, Abishek fixes; Rijo applies the label | | `gate:spec-approved` | green | Architect's yes on the spec |
| Mon 15:00 | Viknesh, in a worktree, runs plan, tasks, analyze; pushes `plan.md`, `tasks.md` | | `gate:spec-approved` | **green** | still only `specs/` |
| Mon 16:00 | Viknesh, eager, pushes `infra/scripts/keyvault/fetch.sh` | | `gate:spec-approved` | **red** (gate job) | code outside `specs/`, no plan label |
| Mon 16:30 | Rijo reads plan + analyze output, one comment answered, applies the label | | `gate:spec-approved`, `gate:plan-approved` | **green** | gate job re-ran on the label event; no new push needed |
| Tue all day | Viknesh runs `/speckit-implement`; agent refuses one edit to `agent/hooks/check-secrets.sh` it wanted to "tweak"; Viknesh raises it as a separate process PR instead | | same | green | protected path, refused before the edit |
| Tue 15:00 | Viknesh pastes the verification run into the PR, applies the label, marks ready | | + `evidence:attached` | green | Builder's evidence |
| Tue 16:00 | Abishek (Owner, wrote neither plan nor code) reviews and approves; squash-merge | | | | one human approval + green CI is what `main` requires |
| Wed 09:30 | Viknesh runs `/speckit-converge` on `main`; one gap becomes issue #132 | `intent` on #132 | | | the next story is found |

The process PR Viknesh opened on Tuesday, #133, changes only
`agent/hooks/check-secrets.sh`. It goes red on both jobs until Rijo, who
did not write it, applies `gate:plan-approved`; then the lint job accepts
the protected file and the gate job passes.

---

## 5. CI is red: what now

| The log says | It means | Do this |
|---|---|---|
| `spec still contains a [NEEDS CLARIFICATION] marker` | the spec is not done | run `/speckit-clarify`, push |
| `PR changes files outside specs/ but 'gate:plan-approved' is missing` | code before the plan was approved | ask the Architect for the label; nothing to push |
| `PROTECTED PATH: <file> matches /.../` followed by `Guardrail and generated paths change by a human-reviewed PR` | a guardrail or generated file changed in a PR without the label | same as above, or move the change to its own PR |
| `RATCHET: ... was added to ... without a justification` | the secrets allowlist grew | add the reason to `agent/policies/security-policy.md` in the same change |
| `RATCHET: new 'secret-check:allow' marker(s)` | a scan bypass appeared outside test tooling | remove it; fixtures live under `agent/` |
| `SECRET PATTERN in ...` | something looks like a credential | remove it; real values go in `.env` or a secret store |
| `check-hooks-enabled: pre-commit hooks are NOT enabled` (local only) | this clone skipped setup | `make hooks` |

---

## 6. What is not enforced by a machine, on purpose

- That the labeler is not the author. Anyone with write access can apply
  any label. It is applied in public and reviewed at the retro. Making CI
  verify it is a known option (framework, section 10).
- That the reviewer holds the right hat. Branch protection counts
  approvals, not roles.
- Story size, the daily sync, and same-day responses. Those are habits.
