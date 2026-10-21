# T011 — owner checks, for the PR description

Paste these into the PR description.

## 1. Guide walkthrough (SC-006, plan Verification row 5)

Run by the owner (rijojohn), 2026-10-14, 20:35–20:41 IST, following the
guide's commands on the running AKS shop with the load generator started:
`status` (`fault not active`), `start` (10 × 500, `fault active`), `status`
(`fault active`), `revert` (10 × 200, `fault removed`).

- First attempt without help: yes.
- Note: typed `make aks-ratings-abort-stop` first ("No rule to make target");
  the documented commands are start / status / revert. Left as is.

## 2. Read-through (FR-011, plan Verification row 6)

Owner's read of `docs/aks-explained.md` section 8 and the repo map against
`infra/azure/scenario-01/README.md`: the commands
(`make aks-ratings-abort-start|status|revert`), the panel names
("Non-2xx Responses by Service" `ratings ->` tile, "5xxs"), the ~15 s delay,
the blank "Server …" panels, the always-red `user ->` tile, `NaN` for "Global
Success Rate", and "start the pretend shoppers first" say the same in both
files. Version 2 still points to `scenarios/scenario-01`.

No conflicting steps.

## 3. Not proven by running (name these in the PR)

- The six pre-check refusals other than "cluster not reachable" (step 13 is the
  only refusal exercised live): not STACK_MODE, not an AKS cluster, mesh not
  running, shop not installed, web pod not in the mesh, no curl in web.
- Status states 4 (fault set but not taking effect) and 5 (rule holds another
  fault): checked by reading the script only.
- EC-003 (anyone can revert): proven by design — the fault lives only in the
  cluster's ratings rule, no local state (plan, Storage).
- Revert's "still failing" branch, and ratings itself answering `500`.
- A reinstall across a change to the chart's ratings rule file
  (`app/robot-shop/helm/templates/ratings-vs.yaml`), which would drop the fault.
- SC-009 on a fresh `make setup-aks`: the run used the existing research
  cluster `sre-stack-452138`.
- Out-of-story item in the diff: `.gitignore` (`.playwright-mcp/`, commit
  `4cab1b9`).
- Cluster-only fixes made during the run, not in the repo: restart of `web`,
  `user`, `dispatch` after a sidecar-injection race on cluster start; Grafana
  `grafana` database recreated in Postgres.
