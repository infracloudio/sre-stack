# shellcheck shell=bash disable=SC2034
# regular-full-resume (T050): a complete regular cluster already consumes
# every allowed DSv5 (24) and FSv2 (4) vCPU. A rerun has nothing to create,
# so the allowance check must pass with needs 0 instead of refusing a second
# cluster's worth of capacity.
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
POOL_MODE=regular
DSV5_CURRENT=24
DSV5_LIMIT=24
FSV2_CURRENT=4
FSV2_LIMIT=4
SPOT_CURRENT=0
SPOT_LIMIT=3
