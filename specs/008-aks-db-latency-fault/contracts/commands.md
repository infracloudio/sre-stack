# Contracts — Commands for the Slow Database Fault (Azure)

The interface the three commands expose: names, arguments, output lines, exit codes and time budgets. Every line here is a promise the script and the make targets must keep, in the shape stories 006 and 007 already use so the files read the same way. States and waits are in `data-model.md`.

## 1. Make targets and the script behind them

Three new targets in the Azure (AKS) block of the `makefile`, directly under `aks-cart-oom-revert` (`makefile:267`, before `setup-aks:` at `makefile:278`), with a short comment block like the existing ones:

```makefile
aks-db-latency-start:
	bash infra/azure/scenario-03/db-latency.sh start

aks-db-latency-status:
	bash infra/azure/scenario-03/db-latency.sh status

aks-db-latency-revert:
	bash infra/azure/scenario-03/db-latency.sh revert
```

and three lines in the `help` target after `makefile:37`, same shape as the existing Azure help lines:

```makefile
@echo "	aks-db-latency-start              - Start Azure scenario 03 on AKS: the shop's database answers slowly"
@echo "	aks-db-latency-status             - Report whether the Azure scenario 03 database fault is active (AKS, read-only)"
@echo "	aks-db-latency-revert             - Remove the Azure scenario 03 database fault (AKS)"
```

The script is `infra/azure/scenario-03/db-latency.sh` with a `README.md` beside it, continuing `scenario-01/` and `scenario-02/`.

- `db-latency.sh start | status | revert`; anything else exits `2`.
- No flags, and no environment beyond what `.env` offers.
- Every `kubectl` call goes through a `k()` wrapper capped at `--request-timeout=5s`, as in 006 and 007.
- Database calls run through `kubectl exec` into `mysql-0` (container `mysql`) and read the password from the pod's own environment.

## 2. Exit codes (the same four as 006 and 007)

| Code | Meaning |
|---|---|
| `0` | done, and the command's own check agreed |
| `1` | done, but the check disagreed (for example the lookups were not slow after start), or status found something off |
| `2` | usage error (unknown verb) |
| `3` | a pre-check refused; nothing was changed |

## 3. Pre-checks, before any change (FR-007, EC-006)

- `STACK_MODE` is `aks`.
- The cluster is reachable and is an AKS cluster.
- `mysql-0` exists and is running in the shop's namespace.
- The `web` pod exists and has `curl` (the test requests are sent from it).

A refusal prints the reason and `Nothing was changed.` on stderr and exits `3`.

## 4. `RESULT:` lines

State names are from `data-model.md`. Each run prints one `RESULT:` line when it reaches its reporting path.

| Command | State before | `RESULT:` line | Exit |
|---|---|---|---|
| start | Not installed, Off or Partial | `RESULT: fault active (shipping lookup <n.n>s, ratings lookup <n.n>s)` | 0 |
| start | On | `RESULT: fault already active` | 0 |
| start, lookups not slow | any | `RESULT: the fault is set but the lookups were not slow: shipping <n.n>s, ratings <n.n>s` | 1 |
| revert | On or Partial | `RESULT: fault removed (shipping lookup <n.n>s, ratings lookup <n.n>s)` | 0 |
| revert | Off or Not installed, lookups normal | `RESULT: fault not active, nothing changed` | 0 |
| revert, lookups still slow | any (revert always sends the test requests, even when it changed nothing) | `RESULT: the fault is removed but the lookups are still slow: shipping <n.n>s, ratings <n.n>s` | 1 |
| status | On | `RESULT: fault active (shipping lookup <n.n>s, ratings lookup <n.n>s)` | 0 |
| status | On, lookups not slow | `RESULT: the fault is set but the lookups were not slow: shipping <n.n>s, ratings <n.n>s` | 1 |
| status | Off or Not installed, normal speed | `RESULT: fault not active` | 0 |
| status | Off or Not installed, slow | `RESULT: fault not active, but the lookups are slow for another reason: shipping <n.n>s, ratings <n.n>s` | 1 |
| status | Partial | `RESULT: the fault is partly set (<n> of 3 rules enabled)` | 1 |

Status never changes anything (FR-009).

## 5. Time budgets

- Each command takes under 60 s, including its own check (SC-006).
- Start waits up to 30 s for the first slow answers; revert waits up to 30 s for normal answers; each check sends 2 shipping requests one after another and 3 ratings requests in parallel (deviation D6).
- Status takes under 10 s (SC-007); measured 9.1 to 9.5 s with the fault on, 4.1 to 5.4 s with it off.
- Start after a restart includes installing the plugin, a few seconds (Finding 10).

## 6. Never

- No command restarts MySQL or any pod.
- No command writes to the shop's tables (FR-006).
- No command starts, stops or changes the load generator.

## 7. Rule text

The three rows the script writes to `query_rewrite.rewrite_rules`, all with `pattern_database` as shown, `enabled` `YES`, then `CALL query_rewrite.flush_rewrite_rules()`. The statement text is what the shop sends (`research.md:674-675`, `:681`) with each value replaced by `?`; the replacement puts a one-row table `(select sleep(<s>)) as db_delay` in front of the shop table (`research.md:702`, `:753`; sleeps from Finding 12).

| Rule | `pattern_database` | Sleep | Pattern (`pattern`) |
|---|---|---|---|
| 1 | `cities` | 2.5 s | `select city0_.uuid as uuid1_0_, city0_.city as city2_0_, city0_.country_code as country_3_0_, city0_.latitude as latitude4_0_, city0_.longitude as longitud5_0_, city0_.name as name6_0_, city0_.region as region7_0_ from cities city0_ where city0_.country_code=? and (city0_.city like ?)` |
| 2 | `cities` | 2.5 s | `select city0_.uuid as uuid1_0_, city0_.city as city2_0_, city0_.country_code as country_3_0_, city0_.latitude as latitude4_0_, city0_.longitude as longitud5_0_, city0_.name as name6_0_, city0_.region as region7_0_ from cities city0_ where city0_.country_code=?` |
| 3 | `ratings` | 0.5 s | `select avg_rating, rating_count from ratings where sku = ?` |

Replacements: rules 1 and 2 are the pattern with `from cities city0_` changed to `from (select sleep(2.5)) as db_delay, cities city0_`; rule 3 is `select avg_rating, rating_count from (select sleep(0.5)) as db_delay, ratings where sku = ?`.
