# shellcheck shell=bash disable=SC2034
# verify-wrong-mode (T060): all five pools exist with matching counts/sizes,
# but the app workload pool runs as mode System instead of User. The verifier
# must exit non-zero naming the mode mismatch.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
POOL_MUTATIONS="app.mode=System"
