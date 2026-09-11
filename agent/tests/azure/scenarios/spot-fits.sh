# shellcheck shell=bash disable=SC2034
# spot-fits: 30 spot vCPU available >= 26 needed for the workload pools, and
# DSv5 room 2 is exactly what the always-regular system pool needs (not the
# regular-mode 24); every workload pool add carries the spot flags, the
# system pool's create carries none.
SIGNED_IN=1
SPOT_LIMIT=30
DSV5_LIMIT=2
POOL_MODE=spot
