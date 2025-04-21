#!/bin/bash

# Upgrade Executor Update (PROP1)
PROP1_CHAIN_IDS=(1 42161 42170)
PROP1_ADDRESSES=(
  0xBB86bBd4871728938B30A54Cc08E0eb2bC75302d  # Ethereum
  0x734B78823c4d979045EC23F38B54A070df7769FF  # Arbitrum One
  0x7d91da41daf1c2e1c3dbc6143289e077e0dba1ef  # Arbitrum Nova
)
PROP1_DATAS=(
  $(cast calldata "perform(address,address,address)" 0x5613AF0474EB9c528A34701A5b1662E3C8FA0678 0x3ffFbAdAF827559da092217e474760E2b2c3CeDd 0xDE505e42D50abd07c8D39Dcf692920d56cBA35Da)
  $(cast calldata "perform(address,address,address)" 0xdb216562328215E010F819B5aBe947bad4ca961e 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827 0x12B1389Fbf261E781bdc3094d28636Abfb03C5b3)
  $(cast calldata "perform(address,address,address)" 0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9 0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482 0xebb11Bbd7d72165FaC86bb5AB1B07A602540b286)
)
PROP1_ACTION_TYPES=(0 0 0)
PROP1_VALUES=(0 0 0)

# Disable USDT Gateway (PROP2)
PROP2_CHAIN_IDS=(1)
PROP2_ADDRESSES=(
  0x8d3425f7039645223517F6F6e60Ef04C28f4188F
)
PROP2_DATAS=(
  $(cast calldata "perform(address[], uint, uint, uint)" "[0xdac17f958d2ee523a2206206994597c13d831ec7]" 0 0 $(cast to-wei 0.0005))
)
PROP2_ACTION_TYPES=(0)
PROP2_VALUES=(
  $(cast to-wei 0.0005)
)

# Timeboost Fee Split (PROP3)
PROP3_CHAIN_IDS=(42161 42170)
PROP3_ADDRESSES=(
  0x5fcb496a31b7AE91e7c9078Ec662bd7A55cd3079  # Arbitrum One ELA
  0xa5aBADAF73DFcf5261C7f55420418736707Dc0db  # Arbitrum Nova ELA
)
PROP3_DATAS=(
  $(cast calldata "setBeneficiary(address)" 0xA4A8a4E2fe847Af59D340926aDCdeF6e988bB1f1) # Arbitrum One
  $(cast calldata "setBeneficiary(address)" 0x9D537C5519B05f58CCddE6d77aEDa3B87F642Bbf) # Arbitrum Nova
)
PROP3_ACTION_TYPES=(1 1) # executeCall
PROP3_VALUES=(0 0)

# SC Key Rotation Upgrade (PROP4)
PROP4_CHAIN_IDS=(42161)
PROP4_ADDRESSES=(0x86E93E21AD108CaE7ADe482C34C230Bfd94D4A8B)
PROP4_DATAS=(
  $(cast calldata "perform()")
)
PROP4_ACTION_TYPES=(0)
PROP4_VALUES=(0)

# Generate proposal data
yarn gen:proposalData \
  --govChainProviderRPC https://arb1.arbitrum.io/rpc \
  --actionChainIds \
    ${PROP1_CHAIN_IDS[@]} \
    ${PROP2_CHAIN_IDS[@]} \
    ${PROP3_CHAIN_IDS[@]} \
    ${PROP4_CHAIN_IDS[@]} \
  --actionAddresses \
    ${PROP1_ADDRESSES[@]} \
    ${PROP2_ADDRESSES[@]} \
    ${PROP3_ADDRESSES[@]} \
    ${PROP4_ADDRESSES[@]} \
  --upgradeDatas \
    ${PROP1_DATAS[@]} \
    ${PROP2_DATAS[@]} \
    ${PROP3_DATAS[@]} \
    ${PROP4_DATAS[@]} \
  --actionTypes \
    ${PROP1_ACTION_TYPES[@]} \
    ${PROP2_ACTION_TYPES[@]} \
    ${PROP3_ACTION_TYPES[@]} \
    ${PROP4_ACTION_TYPES[@]} \
  --upgradeValues \
    ${PROP1_VALUES[@]} \
    ${PROP2_VALUES[@]} \
    ${PROP3_VALUES[@]} \
    ${PROP4_VALUES[@]} \
  --predecessor \
    0x0000000000000000000000000000000000000000000000000000000000000000 \
  --writeToJsonPath \
    ./scripts/proposals/OmnibusApr25/data.json

