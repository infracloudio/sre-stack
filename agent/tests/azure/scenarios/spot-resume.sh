# shellcheck shell=bash disable=SC2034
# spot-resume (T050): group, cluster and two spot workload pools exist; the
# spot quota is partly consumed by them (current 14/30) and the remaining
# pools must continue in spot mode with the spot flags — never flip to
# regular, never demand room for the existing pools.
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_POOLS="app persistent"
POOL_MODE=spot
SPOT_CURRENT=14
SPOT_LIMIT=30
DSV5_CURRENT=2
DSV5_LIMIT=50
FSV2_LIMIT=50
