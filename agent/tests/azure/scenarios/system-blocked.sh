# shellcheck shell=bash disable=SC2034
# system-blocked: spot vCPU covers the workload pools (30 >= 26) but the
# DSv5 family limit is 1, below the 2 vCPU the always-regular system pool
# needs → refusal names DSv5; nothing created.
SIGNED_IN=1
SPOT_LIMIT=30
DSV5_LIMIT=1
