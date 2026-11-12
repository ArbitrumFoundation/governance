#!/bin/bash
set -euo pipefail

L2_FROM_ADDRESS=0x0000000000000000000000000000000000000DA0
L2_RECIPIENT_ADDRESS=0xd9fD39103674CB061D64D9C3b73B878Dbe610b80
L2_ARB_TOKEN_ADDRESS=0x912CE59144191C1204E64559FE8253a0e49E6548

MAX_FEE_PER_GAS=1000000000000
ETH_TX_GAS_LIMIT=50000
ARB_TX_GAS_LIMIT=200000

# The frozen address pays the L2 gas of both txs from its own ETH balance,
# so send the balance minus the max gas fee of both txs.
L2_FROM_BALANCE=$(cast balance $L2_FROM_ADDRESS --rpc-url https://arb1.arbitrum.io/rpc)
ETH_VALUE=$(echo "$L2_FROM_BALANCE - ($ETH_TX_GAS_LIMIT + $ARB_TX_GAS_LIMIT) * $MAX_FEE_PER_GAS" | bc)
echo "frozen address balance: $L2_FROM_BALANCE wei, ETH value: $ETH_VALUE wei"

# Action function signature:
# function execute(
#     address proxyAdmin,
#     address inbox,
#     uint256 gasLimit,
#     uint256 maxFeePerGas,
#     uint256 nonce,
#     address to,
#     uint256 value,
#     bytes calldata data,
#     address from
# ) external {

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionTypes \
        0 \
        0 \
    --actionChainIds \
        1 \
        1 \
    --actionAddresses \
        0x3d456FCd62f5baBCf3263B72fb4ac8fF8cc5a322 \
        0x3d456FCd62f5baBCf3263B72fb4ac8fF8cc5a322 \
    --upgradeValues \
        0 \
        0 \
    --upgradeDatas \
        "$(cast calldata "execute(address,address,uint256,uint256,uint256,address,uint256,bytes,address)" \
            0x554723262467F125Ac9e1cDFa9Ce15cc53822dbD \
            0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f \
            $ETH_TX_GAS_LIMIT \
            $MAX_FEE_PER_GAS \
            1 \
            $L2_RECIPIENT_ADDRESS \
            $ETH_VALUE \
            0x \
            $L2_FROM_ADDRESS \
            )" \
        "$(cast calldata "execute(address,address,uint256,uint256,uint256,address,uint256,bytes,address)" \
            0x554723262467F125Ac9e1cDFa9Ce15cc53822dbD \
            0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f \
            $ARB_TX_GAS_LIMIT \
            $MAX_FEE_PER_GAS \
            2 \
            $L2_ARB_TOKEN_ADDRESS \
            0 \
            "$(cast calldata "transfer(address,uint256)" $L2_RECIPIENT_ADDRESS 74559805200000000000000000)" \
            $L2_FROM_ADDRESS \
            )" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/DistributeBurnedFunds/data.json