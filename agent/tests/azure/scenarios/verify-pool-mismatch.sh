# shellcheck shell=bash disable=SC2034
# verify-pool-mismatch: four malformed rows — app count 99, persistent with
# the wrong size, o11y with its taint dropped, loadgen missing entirely — so
# the verifier must exit non-zero with one ✗ per problem (4 mismatches).
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
POOL_MUTATIONS="app.count=99 persistent.size=Standard_D8s_v5 o11y.taints=none loadgen.missing=1"
