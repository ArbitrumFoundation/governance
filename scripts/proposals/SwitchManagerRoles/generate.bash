#!/bin/bash

yarn gen:proposalData --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42161 \
    --actionAddresses 0x29f3c6b8c98488FBAE0677AB3d2Eb29c77D6aD8a \
    --writeToJsonPath ./scripts/proposals/SwitchManagerRoles/SwitchManagerRoles.json \
    --nonEmergencySCproposal true