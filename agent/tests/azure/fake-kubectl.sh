#!/bin/bash
# fake-kubectl.sh — offline stand-in for `kubectl` used by the aks setup
# script (specs/001-azure-aks-setup T011 harness). Records every call to
# $FAKE_AZ_LOG (same log as fake-az.sh) and answers with no network:
# - `kubectl get storageclass gp2` succeeds once the apply ran, or the
#   scenario sets PRE_SC=1 (it "pre-exists").
# - `kubectl apply -f infra/azure/gp2-storageclass.yaml` records and
#   succeeds.
# - `kubectl config view --minify ...` answers FAKE_CONTEXT, the cluster the
#   current kubeconfig points at (the runner seeds it with the generated
#   cluster name; a scenario overrides it to prove the verifier catches a
#   wrong context, T055).
# - `kubectl get namespaces --output name` answers the namespace list:
#   FAKE_NAMESPACES (default the four built-in ones) names what exists;
#   KUBECTL_NAMESPACES_FAIL=1 makes the read fail (bad kubeconfig) so the
#   verifier's fail-closed check (T034) can be exercised offline.
# - `kubectl get deployments,… --all-namespaces --output json` answers
#   FAKE_WORKLOADS: space-separated `namespace/Kind/name` entries (default
#   none = an empty cluster beyond kube-* housekeeping), so the verifier's
#   workload check (T055) is exercised offline.

if [ -z "${FAKE_AZ_LOG:-}" ]; then
    echo "fake-kubectl: FAKE_AZ_LOG is not set." >&2
    exit 64
fi
if [ -n "${FAKE_AZ_SCENARIO:-}" ]; then
    # shellcheck disable=SC1090
    source "${FAKE_AZ_SCENARIO}"
fi
printf '%s\n' "kubectl $*" >> "${FAKE_AZ_LOG}"

case "${1:-}" in
    get)
        case "${2:-}" in
            storageclass)
                if [ "${KUBECTL_SC_FAIL:-0}" = "1" ]; then
                    echo "fake-kubectl: simulated storageclass read failure" >&2
                    exit 1
                fi
                grep -q '^kubectl apply -f .*gp2-storageclass.yaml' "${FAKE_AZ_LOG}" 2>/dev/null \
                    || [ "${PRE_SC:-0}" = "1" ] || { echo 'storageclass.storage.k8s.io "gp2" not found' >&2; exit 1; }
                ;;
            namespaces)
                if [ "${KUBECTL_NAMESPACES_FAIL:-0}" = "1" ]; then
                    echo "fake-kubectl: simulated namespaces read failure" >&2
                    exit 1
                fi
                for _ns in ${FAKE_NAMESPACES:-default kube-system kube-public kube-node-lease}; do
                    echo "namespace/${_ns}"
                done
                ;;
            deployments,statefulsets,daemonsets,jobs,cronjobs,pods)
                if [ "${KUBECTL_WORKLOADS_FAIL:-0}" = "1" ]; then
                    echo "fake-kubectl: simulated workloads read failure" >&2
                    exit 1
                fi
                FAKE_WORKLOADS="${FAKE_WORKLOADS:-}" python3 <<'PYEOF'
import json, os, sys

items = []
for spec in (os.environ.get("FAKE_WORKLOADS") or "").split():
    parts = spec.split("/")
    if len(parts) != 3 or not all(parts):
        print("fake-kubectl: workload spec must be namespace/Kind/name: " + spec,
              file=sys.stderr)
        sys.exit(2)
    namespace, kind, name = parts
    items.append({"kind": kind, "metadata": {"name": name, "namespace": namespace}})
print(json.dumps({"apiVersion": "v1", "kind": "List", "items": items}))
PYEOF
                ;;
            *) echo "fake-kubectl: unknown get target: $2" >&2; exit 1 ;;
        esac
        ;;
    config)
        case "${2:-}" in
            view|current-context)
                printf '%s\n' "${FAKE_CONTEXT:-}"
                ;;
            *) echo "fake-kubectl: unknown config target: $2" >&2; exit 1 ;;
        esac
        ;;
    apply)
        ;;
    *) echo "fake-kubectl: unknown command: $1" >&2; exit 1 ;;
esac
exit 0
