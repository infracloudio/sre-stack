# shellcheck shell=bash disable=SC2034
# cleanup-read-error (T051): the very first existence read fails (network or
# sign-in). Cleanup must report the failed read with a non-zero exit and
# delete nothing — it must never print "Nothing to clean" on an unreadable
# state.
SIGNED_IN=1
PRE_GROUP=1
GROUP_READ_FAIL=1
