# shellcheck shell=bash disable=SC2034
# verify-wrong-context (T055): kubectl points at a different cluster. The
# verifier must refuse to trust the kubectl reads: one ✗ naming the context,
# non-zero exit, and no namespace/workload claims.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
FAKE_CONTEXT="someone-elses-cluster"
