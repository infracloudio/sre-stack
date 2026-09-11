# shellcheck shell=bash disable=SC2034
# verify-namespace-extra: the pools match, but a leftover `team-a` namespace
# exists. FR-008 says the cluster must still be empty, so the verifier must
# exit non-zero and name that namespace.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
FAKE_NAMESPACES="default kube-system kube-public kube-node-lease team-a"
