# shellcheck shell=bash disable=SC2034
# usage-strings (T058): the allowance answer carries numeric strings ("30")
# instead of numbers (30), as the real CLI does. The helper must parse them
# by field name and still choose spot when it fits.
SIGNED_IN=1
USAGE_NUMERIC_STRINGS=1
SPOT_LIMIT=30
DSV5_LIMIT=50
FSV2_LIMIT=50
POOL_MODE=spot
