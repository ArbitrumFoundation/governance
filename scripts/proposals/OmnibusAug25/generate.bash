#!/bin/bash

set -euo pipefail

# Upgrade Executor Update (PROP1)
PROP1_CHAIN_IDS=(1 42161 42170)
PROP1_ADDRESSES=(
  0xE03E930D661a729595EcC77f9e692a32BEed4260  # Ethereum
  0xE03E930D661a729595EcC77f9e692a32BEed4260  # Arbitrum One
  0xE03E930D661a729595EcC77f9e692a32BEed4260  # Arbitrum Nova
)
PROP1_DATAS=(
  $(cast calldata "perform(address admin, address target, address newLogic)" 0x5613AF0474EB9c528A34701A5b1662E3C8FA0678 0x3ffFbAdAF827559da092217e474760E2b2c3CeDd 0x3d745b8815F9be5BF053858165f8aB1F58c77932)
  $(cast calldata "perform(address admin, address target, address newLogic)" 0xdb216562328215E010F819B5aBe947bad4ca961e 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827 0x3d745b8815F9be5BF053858165f8aB1F58c77932)
  $(cast calldata "perform(address admin, address target, address newLogic)" 0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9 0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482 0x3d745b8815F9be5BF053858165f8aB1F58c77932)
)
PROP1_ACTION_TYPES=(0 0 0)
PROP1_VALUES=(0 0 0)

# Disable USDT Gateway (PROP2)
PROP2_CHAIN_IDS=(1)
PROP2_ADDRESSES=(
  0x8d3425f7039645223517F6F6e60Ef04C28f4188F
)
PROP2_DATAS=(
  $(cast calldata "perform(address[] _tokens, uint256 _maxGas, uint256 _gasPriceBid, uint256 _maxSubmissionCost)" "[0xdac17f958d2ee523a2206206994597c13d831ec7]" 0 0 $(cast to-wei 0.0005))
)
PROP2_ACTION_TYPES=(0)
PROP2_VALUES=(
  $(cast to-wei 0.0005)
)

# SetAmortizedCostCapBips (PROP3)
PROP3_CHAIN_IDS=(42170)
PROP3_ADDRESSES=(
  0x0000000000000000000000000000000000000070 # ArbOwner
)
PROP3_DATAS=(
  $(cast calldata "setAmortizedCostCapBips(uint64 cap)" 0)
)
PROP3_ACTION_TYPES=(1) # executeCall
PROP3_VALUES=(0)

# Generate proposal data
yarn gen:proposalData \
  --govChainProviderRPC https://arb1.arbitrum.io/rpc \
  --actionChainIds \
    ${PROP1_CHAIN_IDS[@]} \
    ${PROP2_CHAIN_IDS[@]} \
    ${PROP3_CHAIN_IDS[@]} \
  --actionAddresses \
    ${PROP1_ADDRESSES[@]} \
    ${PROP2_ADDRESSES[@]} \
    ${PROP3_ADDRESSES[@]} \
  --upgradeDatas \
    ${PROP1_DATAS[@]} \
    ${PROP2_DATAS[@]} \
    ${PROP3_DATAS[@]} \
  --actionTypes \
    ${PROP1_ACTION_TYPES[@]} \
    ${PROP2_ACTION_TYPES[@]} \
    ${PROP3_ACTION_TYPES[@]} \
  --upgradeValues \
    ${PROP1_VALUES[@]} \
    ${PROP2_VALUES[@]} \
    ${PROP3_VALUES[@]} \
  --predecessor \
    0x0000000000000000000000000000000000000000000000000000000000000000 \
  --writeToJsonPath \
    ./scripts/proposals/OmnibusAug25/data.json

