#!/bin/bash

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --predecessor 0x0000000000000000000000000000000000000000000000000000000000000000 \
    --upgradeValues $(cast to-wei 0.0005) \
    --actionChainIds 1 \
    --actionAddresses \
        0x8d3425f7039645223517F6F6e60Ef04C28f4188F \
    --upgradeDatas \
        $(cast calldata \
            "perform(address[], uint, uint, uint)" \
            "[0xdac17f958d2ee523a2206206994597c13d831ec7]" 0 0 $(cast to-wei 0.0005) \
        ) \
    --writeToJsonPath ./scripts/proposals/disable-usdt-gateway/data.json
