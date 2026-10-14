# Quickstart: Validate the Ratings HTTP Abort on Azure

A live run that proves the feature end to end. The builder runs it once on a
fresh Azure setup and attaches the output to the PR (`evidence:attached`).
Commands and results are defined in [contracts/commands.md](contracts/commands.md);
states and pre-checks in [data-model.md](data-model.md). Every step names the
spec item it proves.

## Prerequisites

1. `make setup-aks` finished on a fresh cluster; `.env` unchanged
   (`STACK_MODE=aks`).
2. **Every shop pod is Ready**, the database-loading job included:

   ```bash
   kubectl get pods -n robot-shop
   ```

   Expect every long-running pod `2/2` (`mysql-0` `3/3`) and `mysql-seeder`
   `Completed`. Do not start while any pod is not Ready — during planning
   `shipping` stayed `1/2` because the loading job never finished (research.md,
   Finding 2 note and Quickstart note), which would fail step 6 for a reason
   unrelated to this story.
3. Load generator running (EC-001):

   ```bash
   kubectl create ns loadgen --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f infra/azure/load-gen/load.yaml
   ```

4. Grafana open on **Application Dashboard**, last 15 minutes, refresh 5 s
   (`make get-service-endpoints` prints the address).

## Steps

| # | Do | Expect | Proves |
|---|---|---|---|
| 1 | Wait 5 minutes with traffic, then look at "Non-2xx Responses by Service" | no `ratings ->` tile, or `0`, over the whole 5 minutes; "5xxs" is context only | SC-009, FR-010 |
| 2 | `make aks-ratings-abort-status` | `RESULT: fault not active`, exit 0 | FR-013 |
| 3 | `time make aks-ratings-abort-start` | `RESULT: fault active`, 10 × `500`, exit 0, under 30 s | FR-001, FR-012, SC-005 |
| 4 | Note the time; watch the dashboard | `ratings ->` tile turns red and "5xxs" rises within 60 s | SC-001, FR-007 |
| 5 | `make aks-ratings-abort-start` again | same `RESULT: fault active`, exit 0, rule unchanged | FR-004, SC-007 |
| 6 | From the web pod, 10 requests to ratings and to each other web service (command below) | ratings 10 × `500`; web, cart, catalogue, user, payment, shipping 10 × `200` each | SC-002, FR-005 |
| 7 | `make aks-ratings-abort-status` | `RESULT: fault active`, exit 0 | FR-013 |
| 7a | `kubectl rollout restart deploy/ratings -n robot-shop && kubectl rollout status deploy/ratings -n robot-shop --timeout=180s`, then `make aks-ratings-abort-status` | rollout finishes; still `RESULT: fault active`, exit 0 | EC-004, FR-003 |
| 8 | `make setup-robot-shop`, then `make aks-ratings-abort-status` | still `fault active` (research Finding 2) | EC-002 |
| 9 | `time make aks-ratings-abort-revert` | `RESULT:` fault removed, 10 × `200`, exit 0, under 30 s; 200s within 10 s | FR-002, SC-003, SC-005 |
| 10 | Watch the dashboard | ratings errors falling within 60 s, gone within 2 min | SC-003 |
| 11 | `make aks-ratings-abort-revert` again | same result, no change, exit 0 | FR-004, SC-007 |
| 12 | `make aks-ratings-abort-status` | `RESULT: fault not active`, exit 0 | FR-013 |
| 13 | `KUBECONFIG=/dev/null make aks-ratings-abort-status` | refuses: cluster not reachable, exit 3, nothing changed | FR-006, EC-005 |
| 14 | `git diff --stat main -- scenarios/scenario-01 scenarios/scenario-02 scenarios/scenario-04` and `git diff main -- makefile .env` | first prints nothing; second shows only added lines | FR-009, SC-008 |

Steps 2–12 together fit in one 2-minute demo apart from step 8 (SC-004 is
judged on steps 3, 4, 9, 10).

Step 6 command (read-only):

```bash
kubectl exec -n robot-shop deploy/web -c web -- sh -c '
for u in http://ratings/_health http://web:8080/ http://cart:8080/health http://catalogue:8080/health \
         http://user:8080/health http://payment:8080/health http://shipping:8080/health; do
  printf "%-32s" "$u"
  for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null -m 3 -w "%{http_code} " "$u"; done
  echo
done'
```

The health addresses were checked live during planning: cart, catalogue, user,
payment answered `200`; web (`http://web:8080/`) answered `200` during
`/speckit-analyze`; ratings `200` (fault off); shipping `503` while its
pod was not Ready (see prerequisite 2).

## Guides (FR-008, FR-011, SC-006)

A person new to the project follows only the scenarios guide for one start →
status → revert cycle on the running cluster, without help. The guide must
name the dashboard panels above and warn that the Istio Service Dashboard's
"Server" panels and the ratings logs stay blank, and that the `user ->` tile
is red from normal `404` answers (research Finding 5).

## Clean up

```bash
make aks-ratings-abort-revert
kubectl delete -f infra/azure/load-gen/load.yaml
```

Also run `make lint` and attach its output. There are no offline tests for
this story (plan.md, Project Structure).
