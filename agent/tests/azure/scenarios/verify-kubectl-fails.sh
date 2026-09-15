# shellcheck shell=bash disable=SC2034
# verify-kubectl-fails: `kubectl get namespaces` fails (missing kubectl or a
# bad kubeconfig). The verifier must fail closed — a failed read is a
# mismatch, never an empty-cluster pass (T034 regression guard).
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
KUBECTL_NAMESPACES_FAIL=1
