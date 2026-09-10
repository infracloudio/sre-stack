# shellcheck shell=bash disable=SC2034
# rbac-mg-unrelated: the only create-capable assignment sits on a management
# group that does not contain the subscription; Azure never returns it, so
# the run must refuse (and create nothing).
SIGNED_IN=1
RBAC_ROLE=Reader
RBAC_MG_SCOPE=unrelated
