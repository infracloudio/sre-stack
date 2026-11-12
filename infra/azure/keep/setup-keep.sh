#!/usr/bin/env bash
# setup-keep.sh: install-time steps for Keep on AKS (story #123). Group 1 of the implementation. Order: Bash 4 check;
# lexical guard on the KEEP_SECRETS_DIR string; FR-009 key check; physical path and inside-repo refusal; Helm and
# cluster checks; creation of the local secret files (mode re-read after every chmod); creation of the four Kubernetes
# Secrets when missing; then the Helm install with --wait. Success is printed only after Helm succeeds.
#
# The makefile must call this script with `bash` from PATH (Homebrew bash 5 on macOS). /bin/bash is 3.2 and refuses.
#
# Environment:
#   KEEP_SECRETS_DIR      required. Never defaults to ~/.secrets/keep.
#   KEEP_SKIP_IF_NO_KEY=1 set only by the setup-aks recipe. A missing AI key then skips Keep instead of failing.
# Exit codes: 0 done or skipped, 1 refused or unreachable, 2 configuration error.

# Bash 4 check first: this block must parse and run on macOS Bash 3.2.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "setup-keep: needs Bash 4 or newer (found ${BASH_VERSION:-unknown})" >&2
  exit 2
fi

set -u
set -C

ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)" || { echo "setup-keep: cannot resolve the repository root" >&2; exit 2; }

if [ -z "${KEEP_SECRETS_DIR:-}" ]; then
  if [ "${KEEP_SKIP_IF_NO_KEY:-0}" = "1" ]; then
    echo "setup-keep: skipped, KEEP_SECRETS_DIR is not set (set it in .env)"
    exit 0
  fi
  echo "setup-keep: KEEP_SECRETS_DIR is not set (set it in .env or the environment)" >&2
  exit 2
fi

# Only a leading ~/ is expanded, and only here, before the lexical guard. A bare ~ or a literal $HOME is not expanded
# and is refused below.
# shellcheck disable=SC2088 # the quotes make the pattern match a literal ~/, which is what must be expanded here
case "$KEEP_SECRETS_DIR" in
  "~/"*) KEEP_SECRETS_DIR="$HOME/${KEEP_SECRETS_DIR#"~/"}" ;;
esac

# Lexical guard: string only, no filesystem access. Strips trailing slashes, then refuses root, home, temp folders,
# and the unexpanded forms ~ and $HOME.
LEXICAL="$KEEP_SECRETS_DIR"
while [ "${#LEXICAL}" -gt 1 ] && [ "${LEXICAL%/}" != "$LEXICAL" ]; do
  LEXICAL="${LEXICAL%/}"
done
TMP_LEXICAL="${TMPDIR:-}"
TMP_LEXICAL="${TMP_LEXICAL%/}"
case "$LEXICAL" in
  /|"$HOME"|"$TMP_LEXICAL"|/tmp|/private/tmp|"~"|"\$HOME")
    echo "setup-keep: refusing KEEP_SECRETS_DIR=$KEEP_SECRETS_DIR (root, home, temp folder, or unexpanded ~ or \$HOME)" >&2
    exit 2 ;;
esac

KEY_FILE="$KEEP_SECRETS_DIR/fireworks.key"

# FR-009: the key check runs before any kubectl or helm call. An empty file counts as missing.
if [ ! -s "$KEY_FILE" ]; then
  if [ "${KEEP_SKIP_IF_NO_KEY:-0}" = "1" ]; then
    echo "setup-keep: skipped, AI key file missing or empty: $KEY_FILE"
    exit 0
  fi
  echo "setup-keep: AI key file missing or empty: $KEY_FILE" >&2
  exit 1
fi

# The key file must be mode 600. The script never changes the key file's mode; it stops and names the fix. This check
# also stops in chain mode: a permission problem is not a missing key, so it must not be skipped silently.
KEY_MODE="$(if [ "$(uname -s)" = "Darwin" ]; then stat -f '%Lp' "$KEY_FILE"; else stat -c '%a' "$KEY_FILE"; fi)"
if [ "$KEY_MODE" != "600" ]; then
  echo "setup-keep: $KEY_FILE has mode $KEY_MODE, expected 600. Run: chmod 600 $KEY_FILE (setup-keep did not change it; nothing was created)" >&2
  exit 1
fi

# Preflight: the folder must be outside the repository, and Helm must be the pinned v3.14.4.
REAL_DIR="$(cd "$KEEP_SECRETS_DIR" && pwd -P)" || { echo "setup-keep: cannot open $KEEP_SECRETS_DIR" >&2; exit 2; }
case "$REAL_DIR" in
  "$ROOT"|"$ROOT"/*)
    echo "setup-keep: KEEP_SECRETS_DIR is inside the repository: $REAL_DIR" >&2
    exit 2 ;;
esac
REAL_HOME="$(cd "$HOME" && pwd -P)"
REAL_TMP="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
case "$REAL_DIR" in
  /|"$REAL_HOME"|"$REAL_TMP"|/tmp|/private/tmp)
    echo "setup-keep: refusing KEEP_SECRETS_DIR; it resolves to a root, home or temp folder: $REAL_DIR" >&2
    exit 2 ;;
esac

HELM_VERSION="$(helm version --short 2>/dev/null || true)"
case "$HELM_VERSION" in
  v3.14.4*) ;;
  *)
    echo "setup-keep: needs Helm v3.14.4 on PATH (found: ${HELM_VERSION:-none}). Prefix PATH with \$HOME/.local/opt/helm-3.14.4." >&2
    exit 2 ;;
esac

# Cluster check before any change. Read-only.
if ! kubectl get --raw /version >/dev/null 2>&1; then
  echo "setup-keep: the cluster cannot be reached from the current kubectl context; nothing was changed" >&2
  exit 1
fi

# Local secret files (AD-008): created only when missing, reused otherwise. No value is ever printed.
file_mode() {
  if [ "$(uname -s)" = "Darwin" ]; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}

expect_mode() {
  local got
  got="$(file_mode "$1")"
  if [ "$got" != "$2" ]; then
    echo "setup-keep: mode of $1 is $got, expected $2; stopped" >&2
    exit 1
  fi
}

if [ "$(file_mode "$REAL_DIR")" != "700" ]; then
  chmod 700 "$REAL_DIR"
  expect_mode "$REAL_DIR" 700
fi

make_secret_file() {
  local path="$REAL_DIR/$1"
  if [ -s "$path" ]; then
    if ! grep -Eq '^[0-9a-f]+$' "$path"; then
      echo "setup-keep: existing file is not lowercase hex, stopped: $path" >&2
      exit 1
    fi
    echo "setup-keep: reused $path"
  else
    ( umask 077; openssl rand -hex 24 >| "$path" ) || { echo "setup-keep: could not create $path" >&2; exit 1; }
    echo "setup-keep: created $path"
  fi
  if [ "$(file_mode "$path")" != "600" ]; then
    chmod 600 "$path"
    expect_mode "$path" 600
  fi
}

make_secret_file "db-password"
make_secret_file "nextauth-secret"
echo "setup-keep: local secret files ready in $REAL_DIR (values not printed)"

# T009: Kubernetes Secrets built from the local files. A Secret that already exists is never overwritten, so its UID
# and creation time stay stable for the FR-008 test. Values reach kubectl only through --from-file, never on a command
# line. Newlines are stripped in private copies in a work folder, which is removed on exit.
NS="${KEEP_NAMESPACE:-keep}"
WORK="$(mktemp -d)" || { echo "setup-keep: cannot create a work folder" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
require_non_empty() { # FILE LABEL
  if [ ! -s "$1" ]; then
    echo "setup-keep: $2 is empty after preparation, stopped; no Secret was created from it" >&2
    exit 1
  fi
}
strip_newline() {
  tr -d '\n' < "$1" > "$2"
  chmod 600 "$2"
  require_non_empty "$2" "$(basename "$1")"
}
strip_newline "$REAL_DIR/fireworks.key" "$WORK/fireworks.key"
strip_newline "$REAL_DIR/db-password" "$WORK/db-password"
strip_newline "$REAL_DIR/nextauth-secret" "$WORK/nextauth-secret"
{ printf 'mysql+pymysql://root:'; cat "$WORK/db-password"; printf '@keep-database:3306/keep'; } > "$WORK/database-url"
chmod 600 "$WORK/database-url"
require_non_empty "$WORK/database-url" "the database connection string"

kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS" >/dev/null || {
  echo "setup-keep: could not create namespace $NS" >&2
  exit 1
}

create_secret() { # NAME then KEY=FILE arguments
  local name="$1" probe rc
  shift
  probe="$(kubectl get secret "$name" -n "$NS" 2>&1 >/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "setup-keep: Secret $name already exists, not changed"
    return 0
  fi
  if ! printf '%s\n' "$probe" | grep -q 'NotFound'; then
    echo "setup-keep: could not check Secret $name (kubectl get failed, not NotFound): $probe" >&2
    return 1
  fi
  kubectl create secret generic "$name" -n "$NS" "$@" >/dev/null || return 1
  echo "setup-keep: created Secret $name"
}
create_secret sre-keep-db --from-file="DATABASE_CONNECTION_STRING=$WORK/database-url" \
  --from-file="mysql-root-password=$WORK/db-password" || { echo "setup-keep: could not create Secret sre-keep-db" >&2; exit 1; }
create_secret sre-keep-ai-env --from-file="fireworks.key=$WORK/fireworks.key" \
  || { echo "setup-keep: could not create Secret sre-keep-ai-env" >&2; exit 1; }
create_secret sre-keep-ai-frontend --from-file="OPEN_AI_API_KEY=$WORK/fireworks.key" \
  || { echo "setup-keep: could not create Secret sre-keep-ai-frontend" >&2; exit 1; }
create_secret sre-keep-auth --from-file="NEXTAUTH_SECRET=$WORK/nextauth-secret" \
  || { echo "setup-keep: could not create Secret sre-keep-auth" >&2; exit 1; }

# T010 and T011: install and wait for readiness. Success is reported only when Helm reports success.
VALUES="$ROOT/infra/azure/chart-values/keep.yaml"
if ! helm upgrade --install keep keep --repo https://keephq.github.io/helm-charts --version 0.1.97 \
    -n "$NS" -f "$VALUES" --wait --timeout 10m; then
  echo "setup-keep: Keep did not install or become ready in namespace $NS; no success is reported" >&2
  exit 1
fi
echo "setup-keep: Keep installed in namespace $NS"
exit 0
