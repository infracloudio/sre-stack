# shellcheck shell=bash disable=SC2034
# cleanup-mc-read-fail (T059): the main group exists and deletes cleanly, but
# the follow-up node-group read fails. Cleanup must not say "Nothing was
# deleted" — the main group is already gone — and must report the unknown
# node-group state with a non-zero exit.
SIGNED_IN=1
PRE_GROUP=1
MC_READ_FAIL=1
