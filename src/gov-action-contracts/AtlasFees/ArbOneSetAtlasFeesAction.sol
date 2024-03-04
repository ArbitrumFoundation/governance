// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../arb-precompiles/ArbPrecompilesLib.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbGasInfo.sol";

contract ArbOneSetAtlasFeesAction {
    uint64 public constant NEW_MIN_BASE_FEE = 0.01 gwei;
    uint64 public constant NEW_L1_REWARD_RATE = 0;

    function perform() external {
        ArbPrecompilesLib.arbOwner.setMinimumL2BaseFee(NEW_MIN_BASE_FEE);
        ArbPrecompilesLib.arbOwner.setL1PricingRewardRate(NEW_L1_REWARD_RATE);

        // verify:
        ArbGasInfo arbGasInfo = ArbGasInfo(0x000000000000000000000000000000000000006C);
        require(
            arbGasInfo.getMinimumGasPrice() == NEW_MIN_BASE_FEE,
            "ArbOneSetAtlasFeesAction: min L2 gas price"
        );
        require(
            arbGasInfo.getL1RewardRate() == NEW_L1_REWARD_RATE,
            "ArbOneSetAtlasFeesAction: L1 reward rate"
        );
    }
}
