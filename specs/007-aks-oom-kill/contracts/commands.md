# Contracts — Commands for the Cart OOM Kill Fault (Azure)

The interface the three commands expose: names, arguments, output lines, exit
codes and time budgets. Every line here is a promise the script and the make
targets must keep, in the shape story 006 already uses so both files read the
same way. Underlying state and waits are `data-model.md` §1–§5.

## 1. Make targets and the script behind them

Three new targets in the Azure (AKS) block of the `makefile`, directly under
the story 006 trio (`aks-ratings-abort-revert` ends at `makefile:252`; the
`setup-aks:` target starts at `makefile:262`):

```makefile
aks-cart-oom-start:
	bash infra/azure/scenario-02/cart-oom-kill.sh start

aks-cart-oom-status:
	bash infra/azure/scenario-02/cart-oom-kill.sh status

aks-cart-oom-revert:
	bash infra/azure/scenario-02/cart-oom-kill.sh revert
```

and three lines in the `help` target under the existing Azure help lines
(`makefile:32–34`), same shape:

```makefile
@echo "	aks-cart-oom-start             - Start the cart out-of-memory fault on AKS: cart's memory allowance is lowered until reverted"
@echo "	aks-cart-oom-status            - Report whether the cart out-of-memory fault is active (AKS, changes nothing)"
@echo "	aks-cart-oom-revert            - Remove the cart out-of-memory fault (AKS)"
```

Script path `infra/azure/scenario-02/cart-oom-kill.sh`, the numbering
continuing `infra/azure/scenario-01/` (story 006's folder). Usage line, verbs
and refusals follow 006's script exactly:

- `cart-oom-kill.sh start | status | revert` — anything else exits `2`.
- No flags, no environment beyond what `.env` offers.
- Every cluster call through a `k()` wrapper capped at
  `kubectl --request-timeout=5s` (006 does the same) so a hung API server
  cannot stall a command past its 90 s budget.

## 2. Exit codes (same four as 006's script)

| Code | Meaning |
|---|---|
| `0` | done, and the command's own check agreed with what it observes |
| `1` | done, but the check disagrees — the allowance is lowered and this fault did not set it, or the state never became what the command waited for |
| `2` | usage error (unknown verb) |
| `3` | a pre-check refused; nothing was changed |

## 3. `RESULT:` lines — the one line each run prints

The truth table that drives them is `data-model.md` §3. Each command prints one
`RESULT:` line when it finishes its own work — a pre-check refusal happens
*before* the script reaches its reporting path, so a refusal prints the refusal
message and `Nothing was changed.` on stderr and exits `3`, matching 006; only
the paths below reach a `RESULT:`. The lines are quoted in plain language.

### `start`

| Pre-state (truth table row) | Run behaves as | `RESULT:` line |
|---|---|---|
| Row 1 healthy | lowers the allowance, writes the marker, waits for the first kill | `RESULT: fault active (cart container was killed for running out of memory within 60s)` |
| Row 1 healthy, but no kill within the wait | reports failure after the same change | `RESULT: the allowance is lowered but no out-of-memory kill was observed within 60s; state when last seen: <pod fields>` |
| Row 3 fault active | idempotent success, nothing re-numbered | `RESULT: fault already active` |
| Row 2 lowered, no marker | (unowned) makes it row 3 and succeeds | `RESULT: fault active (cart container was killed for running out of memory within 60s)` |
| Row 4 marker only | re-lowers the allowance, writes nothing new to the marker | `RESULT: fault active (cart container was killed for running out of memory within 60s)` |

### `status`

Always read-only. Prints one of:

| State | `RESULT:` line |
|---|---|
| Row 3 (active) | `RESULT: fault active (cart allowance 24Mi, restarts currently climbing OR waiting for the next restart)` |
| Row 1 | `RESULT: fault not active (cart runs at the chart's allowance, no out-of-memory kills recorded)`; if the container is nonetheless `OOMKilled`/`CrashLoopBackOff` at that allowance, the line ends `… but cart is failing for another reason — this fault is not active` (EC-006) |
| Row 2 | `RESULT: the cart allowance (24Mi) was not set by this fault — it is not active` (EC-008, 006's "rule holds a fault this command did not set" wording family) |
| Row 4 | `RESULT: fault not active (the shop's allowance is correct); a leftover marker can be cleared with the revert command` |

### `revert`

| Pre-state | Run behaves as | `RESULT:` line |
|---|---|---|
| Row 3 active | restores the release's allowance, removes the marker, waits for a running pod at the original values | `RESULT: fault reverted (cart runs at the allowance the shop is installed with, no further out-of-memory kills)` |
| Row 1 healthy | nothing changes, exit `0` (SC-008), observed live in Finding 3 | `RESULT: fault not active; nothing changed` |
| Row 2 lowered, no marker | restores the allowance (FR-008 covers this state) | `RESULT: fault reverted (cart allowance restored to the shop's installed values)` |
| Row 4 marker only | removes the marker, touches no allowance | `RESULT: fault not active; nothing changed (leftover marker cleared)` |

Notes both start and revert obey (FR-009):

- The wait loop checks the pod's actual state through the fields in
  `data-model.md` §4 — never a fixed sleep — and prints what it saw when the
  budget expires; it does not print a mistaken success.
- The second run of either (or after the other) prints the row 3 "already
  active" / row 1 "nothing changed" line, exits `0`, and leaves the cluster as
  it found it.

## 4. Time budgets

Every command, pre-checks and wait included, finishes **inside 90 s** (SC-005):

- pre-checks: one pass, each call capped at 5 s;
- start's wait for the first kill: **60 s** of polling (poll every 3 s; the
  live kill was observed at 15 s — Finding 1), then an honest `RESULT:`/exit 1;
- revert's wait for a running pod with no fresh kill: **60 s** (live: the
  healthiest new pod was `2/2 Running` inside 50 s of the change — Finding 1);
- status: read-only, no wait loop, one pass — live checks answered in ~1 s.

The 90-second overall budget wins over the individual ones if they ever
disagree (a `start` whose kill shows up at 88 s is still a success; one that
never shows at all is a failure reported at 90 s, not a hang).

## 5. What the commands never do

- They never touch anything outside the `cart` Deployment (allowance + marker)
  — no other shop service, no chart values, no `.env`, no dashboards
  (FR-006, FR-013, FR-014, SC-010).
- They never start, stop or restart the load generator or any traffic (spec's
  Out of Scope).
- They never replay a value recorded by a previous run: both the lowered
  values and the target values are read or written to the objects they touch,
  never remembered across runs (FR-008).
- They never change the shop's Deployment for status (read-only commands, and
  status changes nothing even on refusal — FR-003).

## 6. Guides and files these contracts feed

- `infra/azure/scenario-02/README.md` (the Azure scenarios guide, FR-012)
  quotes the `RESULT:` lines above as "what you will see".
- The `quickstart.md` validation run invokes these exact commands and records
  their exits and `RESULT:` lines.
- The `monitoring/dashboards/application.yaml` addition (FR-011 as clarified)
  is out of these commands' scope entirely — the commands change nothing there;
  see `data-model.md` §6.
