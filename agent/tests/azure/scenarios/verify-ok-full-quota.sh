# shellcheck shell=bash disable=SC2034
# verify-ok-full-quota (T050): the same full regular cluster as
# regular-full-resume. The verifier only reads, so it must pass without any
# free capacity for a second cluster.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
POOL_MODE=regular
DSV5_CURRENT=24
DSV5_LIMIT=24
FSV2_CURRENT=4
FSV2_LIMIT=4
SPOT_CURRENT=0
SPOT_LIMIT=3
