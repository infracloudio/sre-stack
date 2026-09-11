# shellcheck shell=bash disable=SC2034
# setup-storage-read-error (T057): everything exists except the storage
# setting, whose read fails. Setup must stop with a plain error and apply
# nothing — never treat the failed read as "absent".
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
KUBECTL_SC_FAIL=1
