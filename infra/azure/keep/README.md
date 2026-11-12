# Keep on AKS: runbook

Keep 0.1.97 (app 0.54.3) installs on the AKS demo cluster with `make setup-keep`, which `make setup-aks` runs as its
second-to-last step. The install reads one values file and four Kubernetes Secrets built from local files. Nothing
secret is in git.

## Before you run it

- **Helm v3.14.4 first on PATH.** The script refuses any other version. Example:
  `PATH="$HOME/.local/opt/helm-3.14.4:$PATH" make setup-keep`.
- **Bash 4 or newer, from PATH.** The makefile calls `bash` from PATH. macOS `/bin/bash` is 3.2 and is refused.
- **`KEEP_SECRETS_DIR` in `.env`.** The shipped value is `~/.secrets/keep`. Only a leading `~/` is expanded. A bare `~`
  and a literal `$HOME` are refused. The folder must be outside the repository and must not be a root, home or temp folder.
- **The AI key file.** `fireworks.key` inside that folder, non-empty, and mode 600. It is never committed. If the mode is
  wrong, the script stops and names the fix. Run `chmod 600 ~/.secrets/keep/fireworks.key` yourself; the script does not
  change the file.

## Install

```bash
make setup-keep
```

The script checks the key file first, then the folder, Helm and the cluster. It creates `db-password` and
`nextauth-secret` in the folder if they are missing (mode 600). It creates these Secrets only when missing:

| Secret | Keys |
|---|---|
| `sre-keep-db` | `DATABASE_CONNECTION_STRING`, `mysql-root-password` |
| `sre-keep-ai-env` | `fireworks.key` |
| `sre-keep-ai-frontend` | `OPEN_AI_API_KEY` |
| `sre-keep-auth` | `NEXTAUTH_SECRET` |

Then it runs `helm upgrade --install keep keep --repo https://keephq.github.io/helm-charts --version 0.1.97`
with `infra/azure/chart-values/keep.yaml`, `--wait --timeout 10m`. It prints success only after Helm succeeds.

**Running it again changes nothing.** Existing Secrets are not overwritten, because a new UID or creation time
would break the FR-008 check. Do not use `kubectl apply` on these Secrets.

## Chain mode (`setup-aks`)

`setup-aks` runs `KEEP_SKIP_IF_NO_KEY=1 make setup-keep`. That flag is set only in that recipe, never in `.env`.
With the flag, a missing or empty key file, or an unset `KEEP_SECRETS_DIR`, skips Keep with a message and the rest of
the setup continues. Run on its own, the same conditions stop with an error.

## Rotating the AI key

Both AI Secrets come from the same key file, so rotate them together:

1. Replace `fireworks.key` in the local folder.
2. Delete both `sre-keep-ai-env` and `sre-keep-ai-frontend` in the namespace.
3. Run `make setup-keep` again. It creates both Secrets from the new file.
4. Restart the pods: `kubectl rollout restart deployment/keep-backend deployment/keep-frontend -n <namespace>`.

## Uninstall and cleanup

Use only the documented uninstall command:

```bash
helm uninstall keep -n <namespace> --no-hooks
```

A plain `helm uninstall` runs the chart's pre-delete hook, which deletes every `keep-*` Secret in the namespace. The
`--no-hooks` form does not. Our `sre-keep-*` Secrets remain after either form.

Keep-generated Secrets remain after the documented uninstall. An administrator removes them with the manual procedure:

```bash
DRY_RUN=1 EXPECTED_CONTEXT=<kube-context> bash infra/azure/keep/tests/keep-manual-cleanup.sh <namespace>
EXPECTED_CONTEXT=<kube-context> bash infra/azure/keep/tests/keep-manual-cleanup.sh <namespace>
```

The script lists the names, asks for the namespace name to be typed, and deletes only the names that begin with
`keep-`. It never reads or prints a Secret value.

**Reinstalling right after an uninstall can fail.** On the disposable cluster, the database claim `keep-pvc` was still
`Terminating`, and the reinstall failed with `persistentvolumeclaims "keep-pvc" not found`. Wait until
`kubectl get pvc -n <namespace>` shows no `keep-pvc`, then run `make setup-keep` again.

## Checks

- Offline: `bash infra/azure/keep/tests/fr009-missing-key.sh`, `bash infra/azure/keep/tests/render-checks.sh` (needs Helm
  v3.14.4 on PATH), and the five other offline suites in `infra/azure/keep/tests/`.
- Live (disposable cluster only): `infra/azure/keep/tests/fr008-second-run.sh`, and the control and no-hooks scripts.
- The test folder's README (`infra/azure/keep/tests/README.md`) records what has and has not been proven.

## Known limits

- Nothing here has run on AKS. The throwaway AKS installs of 2026-10-29 used earlier values.
- `NEXTAUTH_SECRET` is generated, not the chart default. Story 6a adds the login and extends `sre-keep-auth`.
- Keep sends no usage reports in the browser run and the backend log. See `evidence/playwright-run.txt` in the story.
- The database claim is `gp2`. On k3d that name is backed by the local-path provisioner, not an Azure disk.
- Secrets are never overwritten. A changed key file needs the rotation steps above.
