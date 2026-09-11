# shellcheck shell=bash disable=SC2034
# setup-group-read-error (T057): the very first existence read fails. Setup
# must stop with a plain error and create nothing — never treat the failed
# read as "absent" and run group create.
SIGNED_IN=1
GROUP_READ_FAIL=1
