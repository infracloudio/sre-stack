# Contract: Ratings HTTP Abort Commands (Azure)

What a person — or a test — can rely on when running the three commands. The
states, checks and pre-checks they refer to are defined in
[data-model.md](../data-model.md).

## Commands

| Make target | Runs | Changes the cluster? | Spec |
|---|---|---|---|
| `make aks-ratings-abort-start` | `infra/azure/scenario-01/ratings-abort.sh start` | adds the fault to the `ratings` rule if missing | FR-001, FR-003, FR-004, FR-012 |
| `make aks-ratings-abort-status` | `infra/azure/scenario-01/ratings-abort.sh status` | never | FR-013 |
| `make aks-ratings-abort-revert` | `infra/azure/scenario-01/ratings-abort.sh revert` | removes the fault from the `ratings` rule if present | FR-002, FR-004, FR-012 |

- Run from the repository root, like every other target. No arguments, no
  new `.env` settings; the script reads `STACK_MODE`, `APP_NS` and
  `ISTIO_NAMESPACE` from `.env`.
- The script can also be run directly with `bash`; it resolves the repository
  root itself, so it works from any folder (unlike scenario 01's EKS scripts,
  which must be run from their own folder).
- Any other argument, or none, prints a one-line usage message and exits 2.
- The `makefile` gains the three targets and three lines in the existing
  "Azure (AKS)" block of `make help`; no existing line changes (FR-009,
  SC-008).

## Output

Plain sentences, one per step, on standard output; problems on standard error.
Every run ends with exactly one result line starting `RESULT:` so a person or a
test can find it. Examples (wording settles during implementation; the
`RESULT:` prefix and the state names do not):

```text
$ make aks-ratings-abort-start
Checking the cluster... AKS, mesh running, shop installed and in the mesh.
Adding the fault to the ratings routing rule (every request answered with error 500)...
Checking: 10 test requests from the web pod to ratings...
  500 500 500 500 500 500 500 500 500 500
RESULT: fault active
```

```text
$ make aks-ratings-abort-status
RESULT: fault not active (10 of 10 requests to ratings answered normally)
```

```text
$ make aks-ratings-abort-revert
...
  503 503 503 503 503 503 503 503 503 503   (no healthy upstream)
RESULT: ratings still failing after the fault was removed — not caused by this fault
```

## Exit codes

| Code | Meaning | States (data-model §3) |
|---|---|---|
| 0 | Did what was asked and the check agreed: fault active after start, not active after revert; status found state 1 or 2 | 1, 2 |
| 1 | Check disagreed or the rule holds a fault this command did not set; message says what was seen | 3, 4, 5 |
| 2 | Usage error (unknown or missing argument) | — |
| 3 | A pre-check failed; nothing was read or changed beyond the check itself | data-model §5 |

Status exits 0 for both "fault active" and "fault not active" — both are
normal answers. A `make` target passes the script's code through, so `make`
itself fails on codes 1–3.

## Timing

Each command finishes in under 30 seconds, including its check (SC-005). The
check is retried after a change; no new check starts after 15 seconds, and
each check is cut off after 8 seconds (data-model §4), so this holds even when
ratings hangs.

## Guarantees

- **Twice in a row is safe** (FR-004, SC-007): a second start or revert makes
  no change and ends with the same `RESULT:` as the first.
- **No timer** (FR-003): nothing removes the fault except revert.
- **No traffic change**: the commands never touch the load generator.
- **Only ratings** (FR-005): only the `ratings` rule in `APP_NS` is ever
  changed.
- **Nothing on refusal** (FR-006): when a pre-check fails, the rule is not
  changed.
