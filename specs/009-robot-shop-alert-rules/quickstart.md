# Quickstart: Check the Alert Rules for the Demo Shop on Azure

This is the list of checks that prove the spec's success criteria, in order. It holds commands and what "pass" looks like. It does not hold the rule code (that is the change itself) or the limits (those are in `plan.md`, files to change). Run every command from the repo root. The details of the labels and the make target are in `contracts/alert-rules.md`, and the alerts and faults are in `data-model.md`.

"SC-nnn" means a Success Criterion in `spec.md`. "Alerts page" means the Prometheus alerts page.

## Before you start

- The Azure cluster is running. A stopped cluster is a normal state between sessions. Start it with `az aks start` (about 5 minutes) and wait until every shop and monitoring pod is Ready.
- The load generator is running. If it is not: `kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -` then `kubectl apply -f infra/azure/load-gen/load.yaml`. Without shop traffic the server-error and slow-request alerts cannot fire (EC-001).
- Get the address: `make get-service-endpoints`. The alerts page is `http://<address>/prometheus/alerts`, and the same information as JSON is `http://<address>/prometheus/api/v1/rules` and `http://<address>/prometheus/api/v1/alerts`.
- For check 7 only: `promtool` installed on your machine (version 2.47.1 to match the cluster; this is not part of the repo's setup).

Wait for a quiet shop before check 2 and check 3. The shop is ready when every deployment and stateful set in `robot-shop` is Ready: run `kubectl get deploy,sts -n robot-shop` and look at the READY column. A pod list is not enough, because a pod that does not exist yet is not listed (at the last cluster start `catalogue` and `payment` had no running pod until about 6 minutes after the others; see the correction at the end of research Finding 5). Alerts raised during start-up can linger a few minutes, so the shop counts as quiet from the first moment it is ready and the alerts page shows nothing firing.

## 1. Setup is safe to repeat and part of the one-shot setup (SC-008, SC-009)

1. Run `make setup-aks-alert-rules`. It must exit 0. Note the object's version: `kubectl get prometheusrule robot-shop-alerts -n monitoring -o jsonpath='{.metadata.resourceVersion}'`.
2. Run `make setup-aks-alert-rules` again. It must exit 0, and the version printed by the same command must be unchanged (nothing was changed).
3. Run the whole monitoring setup once more with `make setup-aks-o11y`. Before it, record `helm history prometheus-stack -n monitoring` and `kubectl get prometheusrule -A`. It must exit 0, `robot-shop-alerts` must have the same `resourceVersion` as before, and `kubectl get prometheusrule -A` must list the same objects. Record `helm history` again afterwards and report any new revision as it is (SC-008 is read as: this story's step changes nothing).
4. Check the wiring: `make -n setup-aks` prints every command the one-shot setup would run, without running them. The command that applies the rule file must appear in that list: `make -n setup-aks | grep -c "infra/azure/alert-rules/robot-shop-alerts.yaml"` prints at least 1. The full proof is to run `make setup-aks` on a new cluster and see 6 of 6 alerts on the alerts page with no extra step. That needs a new cluster. It is not run for now (developer decision, 2026-10-28), so the pull request says SC-009 is proven by this wiring check only.
5. The alerts page lists all six alert names from `data-model.md`, each as inactive when no fault runs.

## 2. The cart memory fault is seen and clears (SC-001, SC-004, SC-005, SC-006)

1. With a quiet shop, run `make aks-cart-oom-start`. It ends with `RESULT: fault active`.
2. Within 5 minutes the alerts page must show four alerts firing: `RobotShopContainerOOMKilled`, `RobotShopContainerRestarting`, `RobotShopReplicasUnavailable` and `RobotShopHTTPErrors` (for `web`).
3. The two slow-request alerts must not fire. `RobotShopHTTPErrors` fires for `web` only: cart's own error share is 100% but too few requests reach a dead cart, so it is ignored (EC-005). The restart alert fires for the pod that replaced the old one, and it does not stay on because of the old pod's count (EC-004).
4. Each firing alert must show `service`, `namespace` and `severity`, with `severity` one of the five allowed values.
5. Run `make aks-cart-oom-revert`. It ends with `RESULT: fault reverted`.
6. Every alert must clear within 10 minutes, and none may come back in the next 10 minutes.

## 3. The slow-database fault is seen and clears (SC-002, SC-004, SC-005)

1. With a quiet shop, run `make aks-db-latency-start`. It ends with `RESULT: fault active`.
2. Within 5 minutes `RobotShopShippingSlowRequests` and `RobotShopRatingsSlowRequests` must show firing.
3. The four cart-fault alerts must not fire.
4. Run `make aks-db-latency-revert`. It ends with `RESULT: fault removed`.
5. Both alerts must clear within 10 minutes and stay clear for the next 10 minutes.

## 4. A healthy shop stays quiet (SC-003)

1. Start the clock when the shop is quiet (see "Before you start"), with the load generator running and no fault active.
2. After 30 minutes, ask Prometheus whether any of the six alerts fired during that time. In the Prometheus query page run `count_over_time(ALERTS{alertstate="firing", alertname=~"RobotShop.*"}[30m])`. It must return no series.

## 5. A change is quick and needs no reinstall (SC-007)

1. Note the time. Change one limit in the rule file.
2. Run `make setup-aks-alert-rules`.
3. Within 2 minutes, the rules JSON (`api/v1/rules`) must show the changed limit in that rule's condition. The monitoring chart must not have been upgraded: `helm list -n monitoring` must show the same revision for `prometheus-stack` as before.

## 6. Other setups are untouched (SC-010)

1. Run `git diff --name-only main...HEAD`. The list must hold only this story's new files and its `specs/009-robot-shop-alert-rules/` files, plus the `makefile` change (the new `setup-aks-alert-rules` target and one prerequisite added to `setup-aks-o11y`). It must not hold `monitoring/chart-values/prometheus-values.yaml`, anything the local (k3d) setup uses, or anything the AWS setup uses.
2. The Bookinfo rule is unchanged: `kubectl get prometheusrule kube-prometheus-stack-rule-name -n monitoring` still exists, and its file has no diff.

## 7. Rule check and lint (SC-011, SC-012)

1. Run `yq '.spec' infra/azure/alert-rules/robot-shop-alerts.yaml > /tmp/spec-groups.yaml` then `promtool check rules /tmp/spec-groups.yaml`. It must report 6 rules found and no errors.
2. Run `make lint`. It must pass with 0 errors. Paste its real output into the pull request.
3. Run `make aks-cart-oom-status` and `make aks-db-latency-status` with no fault active. Each must end with its own "fault not active" message, as before (SC-011).
4. The rule file shows, for each of the three tuned limits (shipping slow, ratings slow, server-error share), the value and the reason next to it (SC-012).

## 8. No shop traffic (EC-001)

1. Stop the load generator: `kubectl -n loadgen scale deployment/load --replicas=0`. Wait 2 minutes.
2. Run `make aks-cart-oom-start`. Within 5 minutes `RobotShopContainerOOMKilled`, `RobotShopContainerRestarting` and `RobotShopReplicasUnavailable` must show firing.
3. `RobotShopHTTPErrors` must not fire, because there is no traffic to measure.
4. Run `make aks-cart-oom-revert`, then start the load generator again: `kubectl -n loadgen scale deployment/load --replicas=1`. Wait until the alerts page shows nothing firing before the next check.

## 9. Both faults at once (EC-006)

1. With a quiet shop and the load generator running, run `make aks-cart-oom-start` and then `make aks-db-latency-start`.
2. Within 5 minutes all six alerts must show firing.
3. Run `make aks-cart-oom-revert` and `make aks-db-latency-revert`. Every alert must clear within 10 minutes.

## 10. A normal redeploy stays quiet (EC-007)

1. With a quiet shop and the load generator running, run `kubectl -n robot-shop rollout restart deployment/cart` and wait for it to finish. About 3 minutes later run `kubectl -n robot-shop rollout restart deployment/shipping` and wait for it to finish.
2. During the two redeploys and for 10 minutes after the second, no alert may show firing. An alert that only shows "pending" is allowed.
