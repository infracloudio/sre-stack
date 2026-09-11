# shellcheck shell=bash disable=SC2034
# setup-cluster-read-error (T057): the group exists but the cluster state
# cannot be read. Setup must stop with a plain error and create nothing —
# never treat the failed read as "absent" and run aks create.
SIGNED_IN=1
PRE_GROUP=1
CLUSTER_READ_FAIL=1
