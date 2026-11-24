#!/bin/bash

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionTypes \
        1 \
    --actionChainIds \
        42161 \
    --actionAddresses \
        0x912CE59144191C1204E64559FE8253a0e49E6548 \
    --upgradeValues \
        0 \
    --upgradeDatas \
        "$(cast calldata "adjustTotalDelegation(int256)" -51165859783310262738992786)" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/AdjustTotalDvp/data.json