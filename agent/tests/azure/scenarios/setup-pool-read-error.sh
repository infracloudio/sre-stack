# shellcheck shell=bash disable=SC2034
# setup-pool-read-error (T057): group, cluster and app exist; the persistent
# pool state cannot be read. Setup must stop with a plain error and add
# nothing — never treat the failed read as "absent" and run nodepool add.
SIGNED_IN=1
PRE_GROUP=1
PRE_CLUSTER=1
PRE_POOLS="app"
POOL_READ_FAIL=persistent
