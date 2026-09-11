# shellcheck shell=bash disable=SC2034
# spot-resume-short (T050): the existing workload pools run on spot and the
# location's spot allowance is exhausted (14/14), so the missing pools cannot
# be added in the existing mode. The run must refuse naming the spot
# allowance — not silently flip the cluster to regular machines.
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_POOLS="app persistent"
POOL_MODE=spot
SPOT_CURRENT=14
SPOT_LIMIT=14
DSV5_CURRENT=2
DSV5_LIMIT=50
FSV2_LIMIT=50
