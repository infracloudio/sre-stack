# shellcheck shell=bash disable=SC2034
# verify-workload-extra (T055): pools and namespaces look right, but an
# application Deployment exists in an allowed namespace (`default`). The
# verifier must catch it — namespace names alone are not enough — exit
# non-zero, and keep the pool lines ✓.
SIGNED_IN=1
PRE_CLUSTER=1
PRE_POOLS="app persistent o11y loadgen"
FAKE_WORKLOADS="default/Deployment/robot-shop"
