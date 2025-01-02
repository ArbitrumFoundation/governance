#!/bin/bash

# We call ProxyUpgradeAction::perform(address admin, address payable target, address newLogic)

# ProxyUpgradeAction contracts:
# L1: 0xBB86bBd4871728938B30A54Cc08E0eb2bC75302d
# Arb1: 0x734B78823c4d979045EC23F38B54A070df7769FF
# Nova: 0x7d91da41DaF1C2e1c3dBC6143289E077E0DbA1eF

# UpgradeExecutor ProxyAdmins:
# L1: 0x5613AF0474EB9c528A34701A5b1662E3C8FA0678
# Arb1: 0xdb216562328215E010F819B5aBe947bad4ca961e
# Nova: 0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9

# UpgradeExecutor Proxies:
# L1: 0x3ffFbAdAF827559da092217e474760E2b2c3CeDd
# Arb1: 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827
# Nova: 0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482

# UpgradeExecutor Logics:
# L1: 0xDE505e42D50abd07c8D39Dcf692920d56cBA35Da
# Arb1: 0x12B1389Fbf261E781bdc3094d28636Abfb03C5b3
# Nova: 0xebb11Bbd7d72165FaC86bb5AB1B07A602540b286

# First generate a proposal to upgrade the UpgradeExecutor on all 3 chains
yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --predecessor 0x0000000000000000000000000000000000000000000000000000000000000000 \
    --upgradeValues 0 0 0 \
    --actionChainIds 1 42161 42170 \
    --actionAddresses \
        0xBB86bBd4871728938B30A54Cc08E0eb2bC75302d \
        0x734B78823c4d979045EC23F38B54A070df7769FF \
        0x7d91da41DaF1C2e1c3dBC6143289E077E0DbA1eF \
    --upgradeDatas \
        $(cast calldata \
            "perform(address, address, address)" \
            0x5613AF0474EB9c528A34701A5b1662E3C8FA0678 \
            0x3ffFbAdAF827559da092217e474760E2b2c3CeDd \
            0xDE505e42D50abd07c8D39Dcf692920d56cBA35Da \
        ) \
        $(cast calldata \
            "perform(address, address, address)" \
            0xdb216562328215E010F819B5aBe947bad4ca961e \
            0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827 \
            0x12B1389Fbf261E781bdc3094d28636Abfb03C5b3 \
        ) \
        $(cast calldata \
            "perform(address, address, address)" \
            0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9 \
            0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482 \
            0xebb11Bbd7d72165FaC86bb5AB1B07A602540b286 \
        ) \
    --writeToJsonPath ./scripts/proposals/timeboost-extra-items/data.json


# Second, patch the proposal with the fee sweep
yarn ts-node ./scripts/proposals/NovaFeeSweep/patchProposal.ts ./scripts/proposals/timeboost-extra-items/data.json
