// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../arb-precompiles/ArbPrecompilesLib.sol";
import "../util/ActionCanExecute.sol";

interface IArbGasInfo {
    function getMinimumGasPrice() external view returns (uint256);
    function getL1RewardRate() external view returns (uint64);
}

contract ArbOneSetAtlasL1PricingRewardAction {
    uint64 public constant NEW_L1_REWARD_RATE = 0;
    ActionCanExecute public immutable actionCanExecute;

    constructor() {
        actionCanExecute = new ActionCanExecute(true, 0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941); // non-emergency Security Council can prevent execution
    }

    function perform() external {
        if (actionCanExecute.canExecute()) {
            ArbPrecompilesLib.arbOwner.setL1PricingRewardRate(NEW_L1_REWARD_RATE);
            // verify:
            IArbGasInfo arbGasInfo = IArbGasInfo(0x000000000000000000000000000000000000006C);
            require(
                arbGasInfo.getL1RewardRate() == NEW_L1_REWARD_RATE,
                "ArbOneSetAtlasL1PricingRewardAction: L1 reward rate"
            );
        }
    }
}

contract ArbOneSetAtlasMinBaseFeeAction {
    uint64 public constant NEW_MIN_BASE_FEE = 0.01 gwei;
    ActionCanExecute public immutable actionCanExecute;

    constructor() {
        actionCanExecute = new ActionCanExecute(true, 0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941); // non-emergency Security Council can prevent execution
    }

    function perform() external {
        if (actionCanExecute.canExecute()) {
            ArbPrecompilesLib.arbOwner.setMinimumL2BaseFee(NEW_MIN_BASE_FEE);
            // verify:
            IArbGasInfo arbGasInfo = IArbGasInfo(0x000000000000000000000000000000000000006C);
            require(
                arbGasInfo.getMinimumGasPrice() == NEW_MIN_BASE_FEE,
                "ArbOneSetAtlasMinBaseFeeAction: min L2 gas price"
            );
        }
    }
}
