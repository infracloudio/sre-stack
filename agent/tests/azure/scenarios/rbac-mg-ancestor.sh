# shellcheck shell=bash disable=SC2034
# rbac-mg-ancestor: the create-capable assignment is Contributor on a
# management group that contains the subscription; it appears only because
# the helper asks with --include-inherited, and the run must proceed.
SIGNED_IN=1
RBAC_ROLE=Reader
RBAC_MG_SCOPE=ancestor
