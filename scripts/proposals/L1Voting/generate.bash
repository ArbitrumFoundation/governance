#!/bin/bash

# Grants EXECUTOR_ROLE to the L1 voting timelock on the L1 UpgradeExecutor
# and to its alias on the Arb One and Nova UpgradeExecutors, and sets the constitution hash

# Address from DeployL1Voting.s.sol (forge v1.8.3):
NEW_L1_TIMELOCK=0xD1159d41EE8781e8AB34C4C9B5B6bD6B31BB747a
NEW_L1_TIMELOCK_ALIAS=0xe2269d41EE8781E8aB34C4c9B5b6Bd6B31BB858b

L1_UPGRADE_EXECUTOR=0x3ffFbAdAF827559da092217e474760E2b2c3CeDd
ARB1_UPGRADE_EXECUTOR=0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827
NOVA_UPGRADE_EXECUTOR=0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482
ARB1_CONSTITUTION=0x1D62fFeB72e4c360CcBbacf7c965153b00260417
# TODO: replace dummy hash with the real constitution hash
NEW_CONSTITUTION_HASH=0x0000000000000000000000000000000000000000000000000000000000000001
EXECUTOR_ROLE=$(cast call --rpc-url https://arb1.arbitrum.io/rpc $ARB1_UPGRADE_EXECUTOR "EXECUTOR_ROLE()(bytes32)")

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionTypes \
        1 \
        1 \
        1 \
        1 \
    --actionChainIds \
        1 \
        42161 \
        42170 \
        42161 \
    --actionAddresses \
        $L1_UPGRADE_EXECUTOR \
        $ARB1_UPGRADE_EXECUTOR \
        $NOVA_UPGRADE_EXECUTOR \
        $ARB1_CONSTITUTION \
    --upgradeValues \
        0 \
        0 \
        0 \
        0 \
    --upgradeDatas \
        "$(cast calldata "grantRole(bytes32,address)" $EXECUTOR_ROLE $NEW_L1_TIMELOCK)" \
        "$(cast calldata "grantRole(bytes32,address)" $EXECUTOR_ROLE $NEW_L1_TIMELOCK_ALIAS)" \
        "$(cast calldata "grantRole(bytes32,address)" $EXECUTOR_ROLE $NEW_L1_TIMELOCK_ALIAS)" \
        "$(cast calldata "setConstitutionHash(bytes32)" $NEW_CONSTITUTION_HASH)" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/L1Voting/data.json
