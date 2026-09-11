#!/bin/bash
# fake-kubectl.sh — offline stand-in for `kubectl` used by the aks setup
# script (specs/001-azure-aks-setup T011 harness). Records every call to
# $FAKE_AZ_LOG (same log as fake-az.sh) and answers with no network:
# - `kubectl get storageclass gp2` succeeds once the apply ran, or the
#   scenario sets PRE_SC=1 (it "pre-exists").
# - `kubectl apply -f infra/azure/gp2-storageclass.yaml` records and
#   succeeds.
# - `kubectl get namespaces --output name` answers the namespace list:
#   FAKE_NAMESPACES (default the four built-in ones) names what exists;
#   KUBECTL_NAMESPACES_FAIL=1 makes the read fail (bad kubeconfig) so the
#   verifier's fail-closed check (T034) can be exercised offline.

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
                grep -q '^kubectl apply -f .*gp2-storageclass.yaml' "${FAKE_AZ_LOG}" 2>/dev/null \
                    || [ "${PRE_SC:-0}" = "1" ] || exit 1
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
            *) echo "fake-kubectl: unknown get target: $2" >&2; exit 1 ;;
        esac
        ;;
    apply)
        ;;
    *) echo "fake-kubectl: unknown command: $1" >&2; exit 1 ;;
esac
exit 0
