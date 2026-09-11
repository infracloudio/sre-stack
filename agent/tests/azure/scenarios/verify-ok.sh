# shellcheck shell=bash disable=SC2034
# verify-ok: a healthy cluster — one system pool plus the four workload pools
# matching the data-model §3 table, regular mode (the default allowance), and
# only the built-in namespaces. PRE_* knobs make the read-only verifier see
# the cluster without any setup call; it must print ✓ for everything, report
# zero mismatches, and exit 0.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
