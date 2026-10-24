#!/bin/bash

# GlamsterdamForkGateAction (Ethereum): 0x3DC0938200AD42Cf0650ba98Bb368D09e98E8F5E
# - probe at 0xC202568e7c23A99F2B3f1bC7Fe6Aff00D612D930
# SetGlamsterdamGasParamsAction (Arbitrum One and Nova): 0x9d084D83BA4d3FAF2aA475A11fBee2D275F965a5

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 1 42161 42170 \
    --actionAddresses \
        0x3DC0938200AD42Cf0650ba98Bb368D09e98E8F5E \
        0x9d084D83BA4d3FAF2aA475A11fBee2D275F965a5 \
        0x9d084D83BA4d3FAF2aA475A11fBee2D275F965a5 \
    --writeToJsonPath ./scripts/proposals/Glamsterdam/data.json
