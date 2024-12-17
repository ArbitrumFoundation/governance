#!/bin/bash

# OfficeHoursAction: TODO

# arb1 RollupUpgradeSecondaryAction: 0x2A3a4BDbC7c00d5115d297d83A31358B317d4740
# - new impl at 0x5c93BAB9Ff2Fa3884b643bd8545C625De0633517
# nova RollupUpgradeSecondaryAction: 0x8E1c1555b2Fe22870e7a0A454789b0c92e494ADC
# - new impl at 0x5c93BAB9Ff2Fa3884b643bd8545C625De0633517

# arb1 BoldUpgradeAction: 0xf795ec38701234664f69Dbd761Ee9c511F25ac1D
# nova BoldUpgradeAction: 0xd25B258B55765c9fb5567eCABB6114b03b0f78b5

# nova SetValidatorsAction: 0x2f845d909058200e4E56855C2735975a004a4922

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --predecessor 0x0000000000000000000000000000000000000000000000000000000000000000 \
    --upgradeValues 0 0 0 0 0 0 \
    --actionChainIds 1 1 1 1 1 1 \
    --actionAddresses \
        0x000000000000000000000000000000000000dead \
        0x2A3a4BDbC7c00d5115d297d83A31358B317d4740 \
        0x8E1c1555b2Fe22870e7a0A454789b0c92e494ADC \
        0xf795ec38701234664f69Dbd761Ee9c511F25ac1D \
        0xd25B258B55765c9fb5567eCABB6114b03b0f78b5 \
        0x2f845d909058200e4E56855C2735975a004a4922 \
    --upgradeDatas \
        $(cast calldata "perform()") \
        $(cast calldata "perform(address)" 0x5c93BAB9Ff2Fa3884b643bd8545C625De0633517) \
        $(cast calldata "perform(address)" 0x5c93BAB9Ff2Fa3884b643bd8545C625De0633517) \
        $(cast calldata "perform(address[])" "[]") \
        $(cast calldata "perform(address[])" "[0x1732BE6738117e9d22A84181AF68C8d09Cd4FF23,0x3B0369CAD35d257793F51c28213a4Cf4001397AC,0x54c0D3d6C101580dB3be8763A2aE2c6bb9dc840c,0x658e8123722462F888b6fa01a7dbcEFe1D6DD709,0xDfB23DFE9De7dcC974467195C8B7D5cd21C9d7cB,0xE27d4Ed355e5273A3D4855c8e11BC4a8d3e39b87,0x57004b440Cc4eb2FEd8c4d1865FaC907F9150C76,0x24Ca61c31C7f9Af3ab104dB6B9A444F28e9071e3,0xB51EDdfc9A945e2B909905e4F242C4796Ac0C61d]") \
        $(cast calldata "perform(address[], bool[])" "[0x0fF813f6BD577c3D1cDbE435baC0621BE6aE34B4]" "[true]") \
    --writeToJsonPath ./scripts/proposals/BOLD/data.json
