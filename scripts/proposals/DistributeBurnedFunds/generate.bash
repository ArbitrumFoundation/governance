#!/bin/bash

L2_RECIPIENT_ADDRESS=0x000000000000000000000000000000000000DEAD

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
    --actionChainIds \
        1 \
    --actionAddresses \
        0x3d456FCd62f5baBCf3263B72fb4ac8fF8cc5a322 \
    --upgradeValues \
        0 \
    --upgradeDatas \
        "$(cast calldata "execute(address,address,uint256,uint256,uint256,address,uint256,bytes,address)" \
            0x554723262467F125Ac9e1cDFa9Ce15cc53822dbD \
            0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f \
            100000 \
            10000000000000 \
            0 \
            $L2_RECIPIENT_ADDRESS \
            30764667401709008927568 \
            0x \
            0x0000000000000000000000000000000000000DA0 \
            )" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/DistributeBurnedFunds/data.json