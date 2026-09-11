# shellcheck shell=bash disable=SC2034
# verify-extra-pool (T060): the five documented pools match, but a sixth User
# pool with ten nodes also exists. The verifier must exit non-zero naming the
# unexpected pool — the current checker wrongly passes this.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
EXTRA_POOLS="extra:User:10:Standard_D2s_v5"
