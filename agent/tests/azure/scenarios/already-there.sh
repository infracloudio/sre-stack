# shellcheck shell=bash disable=SC2034
# already-there: group, cluster, all four workload pools and the StorageClass
# pre-exist; the run must record zero create calls.
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_SC=1
PRE_POOLS="app persistent o11y loadgen"
