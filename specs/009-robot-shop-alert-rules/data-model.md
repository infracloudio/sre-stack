# Data Model: Alert Rules for the Demo Shop on Azure

This file says what the six alert rules are, what every alert carries, and what states an alert goes through. It holds no rule code and no limits. The limits and wait times are in `plan.md` (files to change), each with its reason. "Finding N" points at `research.md`.

## Entity 1: Alert rule

One rule says "raise an alert when this condition stays true". There are six, all in one `PrometheusRule` object named `robot-shop-alerts`, in the `monitoring` namespace, with the label `release: prometheus-stack` (Finding 1). They are in one group.

| Field | Meaning | Rule |
|---|---|---|
| Name | Unique alert name | Starts with `RobotShop`. Must not match a Bookinfo name (`reviewsHTTPError`, `productpageHTTPError`, `ratingsHTTPError`, `detailsHTTPError`), because Alertmanager will later group by alert name and namespace (AD-012). |
| Condition | The question asked of the metrics | Written in `plan.md` (files to change) |
| Wait before firing | How long the condition must stay true | Set in `plan.md` from Findings 5 and 6 (FR-009) |
| Severity | How serious | One of critical, error, high, warning, info (FR-008) |
| Service label | Which shop service | Built by the rule from the label that holds the name on its metric (Findings 2 and 3) |
| Namespace label | Which part of the cluster | Always `robot-shop` (FR-007) |
| Summary | One plain sentence naming the service | Required |

### The six rules

| Alert name | What it says in plain words | Severity | Raised by |
|---|---|---|---|
| `RobotShopContainerOOMKilled` | A shop container was stopped for using too much memory | critical | cart memory fault |
| `RobotShopContainerRestarting` | A shop container keeps restarting | high | cart memory fault |
| `RobotShopReplicasUnavailable` | A shop service has fewer working copies than it should | warning | cart memory fault |
| `RobotShopHTTPErrors` | A high share of a service's requests got a server error | high | cart memory fault (fires for `web`; cart's own errors are ignored because too few requests reach it, Finding 8) |
| `RobotShopShippingSlowRequests` | The shipping cost lookup is slow | warning | slow-database fault |
| `RobotShopRatingsSlowRequests` | The ratings lookup is slow | warning | slow-database fault |

Severity follows the earlier Keep try-out, which Keep accepted (`keep-tryout-findings.md` lines 47 and 52). "No ready copy" stays at warning because Finding 6 showed that number also rises during a normal redeploy while the shop still has a working copy. The levels `error` and `info` are unused.

## Entity 2: Alert

What a person sees on the alerts page when a rule's condition is true.

| Field | Meaning |
|---|---|
| Alert name | The rule's name |
| `severity`, `namespace`, `service` | The three labels every alert promises (see `contracts/alert-rules.md`) |
| Summary | The plain sentence from the rule |
| State | One of the states below |

## State changes

```
inactive -> pending -> firing -> inactive
```

- **inactive**: the condition is false.
- **pending**: the condition is true but has not lasted the wait time yet. A blip stays here and never fires (FR-009).
- **firing**: the condition has stayed true for the whole wait. This is what the alerts page shows as an alert.
- Back to **inactive**: the condition ended. The alert clears with no action from anyone (FR-010). The alerts look at the last few minutes, so one can stay on for a while after a fix (EC-003).

## Which fault should raise which alert (SC-001, SC-002, SC-005)

| Alert | Cart memory fault | Slow-database fault |
|---|---|---|
| `RobotShopContainerOOMKilled` | fires | must not fire (Finding 7) |
| `RobotShopContainerRestarting` | fires | must not fire (Finding 7) |
| `RobotShopReplicasUnavailable` | fires | must not fire (Finding 7) |
| `RobotShopHTTPErrors` | fires (for `web`) | must not fire (Finding 7) |
| `RobotShopShippingSlowRequests` | must not fire | fires |
| `RobotShopRatingsSlowRequests` | must not fire | fires |

With no fault and the load generator running, none fire (SC-003). With the load generator stopped, the two kinds that need traffic (server errors and slow requests) cannot fire (EC-001).
