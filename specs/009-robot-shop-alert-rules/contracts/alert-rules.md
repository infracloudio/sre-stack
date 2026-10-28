# Contract: Alert Rules for the Demo Shop on Azure

Two things in this story are used by other people or other stories, so they are written down as promises. Nothing else here is an interface.

## Contract 1: The labels every alert carries

The later Keep stories (#123 onward) read these. Keep turns Prometheus labels into top-level alert fields, so a Keep rule on `namespace == "robot-shop"` works (`keep-tryout-findings.md` line 58).

| Label | Value | Promise |
|---|---|---|
| `severity` | one of `critical`, `error`, `high`, `warning`, `info` | Always present, always one of these five (FR-008). Keep accepts exactly these (`keep-tryout-findings.md` line 47). The repo's old `P1` value would show as info in Keep, so it is not used. |
| `namespace` | `robot-shop` | Always present (FR-007). |
| `service` | the shop service the alert is about, such as `cart` | Always present (FR-007). It is not the ready-made `service` label on the pod metrics, which names the monitoring tool (Finding 2). Each rule builds it. |

Every alert also carries the alert name (the rule's name) and a plain `summary` that names the service. Alert names are unique and start with `RobotShop`.

**What a later story may rely on:** these three labels exist on all six alerts. **What it may not rely on:** any other label, or the exact limits and wait times, which can change (FR-015).

## Contract 2: Installing and changing the rules

| Item | Promise |
|---|---|
| Command | `make setup-aks-alert-rules` |
| What it does | Applies the `robot-shop-alerts` rule object to the cluster in the `monitoring` namespace. |
| Safe to run twice | Yes. The second run exits 0 and changes nothing (principle I, FR-014, SC-008). |
| Changing a rule | Edit the rule file, then run the same command. It does not reinstall or upgrade the monitoring chart (FR-015). |
| Part of the one-shot setup | It is a prerequisite of `setup-aks-o11y` (placed after `setup-aks-prometheus-stack`), and `setup-aks` already calls `setup-aks-o11y`. No extra step (FR-014, SC-009). |
| Needs | The monitoring chart installed first, because the rule object type (`prometheusrules.monitoring.coreos.com`) comes from it. |
| Azure only | It is not part of the local (k3d) or AWS setups, and no file those setups use changes (FR-013, SC-010). |
| Not covered | Sending alerts anywhere. That is the next stories. |
