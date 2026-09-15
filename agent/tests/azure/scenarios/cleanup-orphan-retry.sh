# shellcheck shell=bash disable=SC2034
# cleanup-orphan-retry (T051): the main group is already gone, but the exact
# predicted node resource group lingers. A retry after a partial delete must
# still find and warn about that one group, name the removal command, and
# exit non-zero — and never delete anything on a guess.
SIGNED_IN=1
PRE_GROUP=0
MC_LINGERS=1
