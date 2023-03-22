// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetL1PricingRewardRateAction {
    function perform(uint64 newWeiPerUnit) external {
        ArbPrecompilesLib.arbOwner.setL1PricingRewardRate(newWeiPerUnit);
    }
}
