# shellcheck shell=bash disable=SC2034
# mc-lingers: the group exists; after delete the exact MC_ node resource group
# still exists → plain warning + exit non-zero, no second delete. Other
# people's MC_ groups exist in this world and must never be listed, searched,
# or reported; the script may only ask about our own exact MC_ name.
SIGNED_IN=1
PRE_GROUP=1
MC_LINGERS=1
OTHER_MC_GROUPS="MC_alice-rg_sre-stack-alice_eastus2 MC_bob-rg_sre-stack-bob_westus2"
