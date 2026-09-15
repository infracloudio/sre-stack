# shellcheck shell=bash disable=SC2034
# already-there: group, cluster, all four workload pools and the StorageClass
# pre-exist; the run must record zero create calls. The reused cluster runs
# 1.33 while .env pins 1.34, so the run must also warn about the drift
# without touching the cluster (T043).
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_SC=1
PRE_POOLS="app persistent o11y loadgen"
K8S_VERSION=1.33
