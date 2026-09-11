# shellcheck shell=bash disable=SC2034
# cleanup-delete-fail (T056): the group exists but its delete fails. Cleanup
# must report the failure, confirm by a read that the group still exists, and
# exit non-zero without claiming success or deleting anything else.
SIGNED_IN=1
PRE_GROUP=1
DELETE_FAIL=1
