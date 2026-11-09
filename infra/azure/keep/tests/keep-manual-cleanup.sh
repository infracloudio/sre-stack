#!/usr/bin/env bash
# keep-manual-cleanup.sh: administrator-run Secret cleanup after the documented uninstall (AD-016 decision 5).
# Draft for review. Not run against any cluster.
#
# Usage:
#   EXPECTED_CONTEXT=<kube-context> [DRY_RUN=1] ./keep-manual-cleanup.sh <namespace>
#
# Fail-closed rules:
#   - Nothing is deleted unless every check passes: context, namespace, uninstall state,
#     successful discovery, a typed confirmation, and an unchanged list at delete time.
#   - A failed discovery query stops the script. Its output is never treated as "no Secrets".
#   - Only names beginning with "keep-" are deleted. Secret values are never read or printed.
#   - DRY_RUN=1 deletes nothing; it adds --dry-run=server to each delete.

set -u
set -C

NS="${1:-}"
if [ -z "$NS" ]; then
  echo "REFUSED: usage: $0 <namespace>" >&2
  exit 2
fi
if [ -z "${EXPECTED_CONTEXT:-}" ]; then
  echo "REFUSED: set EXPECTED_CONTEXT to the kubectl context for this cleanup" >&2
  exit 2
fi
case "$NS" in
  default|kube-system|kube-public|kube-node-lease|monitoring|istio-system)
    echo "REFUSED: $NS is not a Keep namespace" >&2
    exit 2 ;;
esac
for tool in kubectl helm awk mktemp cmp wc tr; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "REFUSED: missing required tool: $tool" >&2
    exit 2
  fi
done

CTX="$(kubectl config current-context 2>/dev/null)" || { echo "REFUSED: cannot read kubectl context; nothing deleted" >&2; exit 2; }
if [ "$CTX" != "$EXPECTED_CONTEXT" ]; then
  echo "REFUSED: context is $CTX, expected $EXPECTED_CONTEXT; nothing deleted" >&2
  exit 2
fi

NSX="$(kubectl get namespace "$NS" -o name --ignore-not-found 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ] || [ -z "$NSX" ]; then
  echo "REFUSED: namespace $NS was not found (or could not be read); nothing deleted" >&2
  exit 2
fi

# The release must be uninstalled. Any other status result stops the script.
HELM_OUT="$(helm status keep -n "$NS" 2>&1)"
HELM_RC=$?
if [ "$HELM_RC" -eq 0 ]; then
  echo "REFUSED: Keep is still installed in $NS; run the documented uninstall first" >&2
  exit 2
fi
case "$HELM_OUT" in
  *"not found"*) ;;
  *) echo "REFUSED: cannot confirm the uninstall in $NS: $HELM_OUT" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/keep-cleanup.XXXXXX")" || { echo "REFUSED: cannot create work folder" >&2; exit 2; }

DRYRUN_FLAG=""
if [ "${DRY_RUN:-0}" = "1" ]; then
  DRYRUN_FLAG="--dry-run=server"
  echo "DRY_RUN=1: no Secret will be deleted"
fi

# Discovery. A failure stops the script; it never means "nothing to delete".
kubectl get secrets -n "$NS" -o name > "$TMP/all-1.txt" 2> "$TMP/all-1.err"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "FAILED: Secret discovery failed (exit $RC); nothing deleted. See $TMP/all-1.err" >&2
  exit 3
fi
awk '/^secret\/keep-/' "$TMP/all-1.txt" > "$TMP/keep-names-1.txt" || { echo "FAILED: cannot filter names; nothing deleted" >&2; exit 3; }

COUNT="$(wc -l < "$TMP/keep-names-1.txt" | tr -d ' ')"
if [ "$COUNT" -eq 0 ]; then
  echo "No keep-* Secrets in $NS. Nothing to delete."
  exit 0
fi

echo "Review these $COUNT Secret names in $NS (names only; values are never read):"
cat "$TMP/keep-names-1.txt"
echo
printf 'Type the namespace name (%s) to confirm deletion of exactly these names: ' "$NS"
read -r ANSWER
if [ "$ANSWER" != "$NS" ]; then
  echo "CANCELLED: nothing deleted" >&2
  exit 2
fi

# Re-check at delete time. Any change since the review cancels the run.
kubectl get secrets -n "$NS" -o name > "$TMP/all-2.txt" 2> "$TMP/all-2.err"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "FAILED: re-check failed (exit $RC); nothing deleted" >&2
  exit 3
fi
awk '/^secret\/keep-/' "$TMP/all-2.txt" > "$TMP/keep-names-2.txt" || { echo "FAILED: cannot filter names; nothing deleted" >&2; exit 3; }
if ! cmp -s "$TMP/keep-names-1.txt" "$TMP/keep-names-2.txt"; then
  echo "CHANGED: the list changed since review; nothing deleted. Run the script again." >&2
  exit 3
fi

# Delete the reviewed names one by one. Stop at the first failure.
# Each delete gets its own stderr file. With set -C, reusing one file would make every redirect after
# the first fail, so the command would never run.
i=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  i=$((i + 1))
  # shellcheck disable=SC2086
  kubectl delete -n "$NS" "$name" $DRYRUN_FLAG > /dev/null 2> "$TMP/delete-$i.err"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "FAILED: deleting $name (exit $RC); stopped. See $TMP/delete-$i.err" >&2
    exit 3
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "dry run: the server accepted the delete of $name; nothing was deleted"
  else
    echo "deleted $name"
  fi
done < "$TMP/keep-names-1.txt"

# Verify. Remaining keep-* Secrets, or a failed check, is not success.
kubectl get secrets -n "$NS" -o name > "$TMP/all-3.txt" 2> "$TMP/all-3.err"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "FAILED: final check could not run (exit $RC). Check $NS manually." >&2
  exit 3
fi
LEFT="$(awk '/^secret\/keep-/' "$TMP/all-3.txt" | wc -l | tr -d ' ')"
if [ "$LEFT" -ne 0 ] && [ "${DRY_RUN:-0}" != "1" ]; then
  echo "FAILED: $LEFT keep-* Secret(s) remain in $NS." >&2
  exit 3
fi
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "Dry run complete. Nothing was deleted. Our own Secrets (sre-keep-*) were not matched by the filter."
else
  echo "Done. Our own Secrets (sre-keep-*) were not matched by the filter and were not touched."
fi
exit 0
