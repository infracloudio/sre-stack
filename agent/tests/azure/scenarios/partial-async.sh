# shellcheck shell=bash disable=SC2034
# partial-async (T056): `az aks create --no-wait` is accepted, then every
# provisioningState read fails. Setup must stop and report the cluster under
# "Submitted but not confirmed" — never under "Not created" — and delete
# nothing.
SIGNED_IN=1
CLUSTER_STATE_FAIL=1
