# Data Model: Slow Database Fault for the Demo Shop on Azure

The fault stores nothing outside the database. Everything below was checked against `research.md` Findings 9, 10, 12, 13 and 14.

## The three rules (the fault itself)

| Rule | Applies to | Added wait |
|---|---|---|
| 1 | Shipping lookup of cities by country and city name (`GET /match/...`) | 2.5 s |
| 2 | Shipping lookup of all cities in a country (`GET /cities/...`) | 2.5 s |
| 3 | Ratings lookup by product (`GET /api/fetch/<sku>`) | 0.5 s (the ratings request takes about twice this, Finding 12) |

The rules live in `query_rewrite.rewrite_rules` inside MySQL. Each has an `enabled` column (`YES` or `NO`). The exact statement text each rule matches is a contract item (`contracts/`).

## Fault state

| State | How status recognises it | Start does | Revert does |
|---|---|---|---|
| **Not installed** (fresh database, or after a restart) | The `query_rewrite` schema is missing | Installs the plugin, adds the three rules, enables them, flushes | Nothing; reports "not active" |
| **Off** | Plugin present, `Rewriter_number_loaded_rules` is 0 | Enables the rules, flushes | Nothing; reports "not active" |
| **On** | `Rewriter_number_loaded_rules` is 3 and all three rules are enabled | Nothing; reports "active" | Disables the rules, flushes |
| **Partial** | Any other number loaded, or the rule rows differ from the table above | Puts all three rules back and enables them | Disables every rule, flushes |

The state is read from the database, so there is no local file and anyone with cluster access can run status (EC-005). Not installed and Off both read as "not active" to the presenter.

## Test request (FR-008, FR-009)

| Lookup | Request sent from the `web` pod | Slow means |
|---|---|---|
| Shipping | `GET http://shipping:8080/match/de/ber` | more than 2 s |
| Ratings | `GET http://ratings/api/fetch/Watson` | more than 0.5 s |

A few of each are sent. Status reports "slow for another reason" when the state is Off or Not installed but the requests are slow (EC-007).

## Data

The fault writes nothing to the shop's data (FR-006). The data checks are the `cities` row count and checksum and the two shipping output hashes (Finding 12). Ratings has no fixed baseline: its rows come from shop traffic (Finding 14).
