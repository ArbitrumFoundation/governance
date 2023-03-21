// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetL1PricingRewardRateAction {
    function perform(uint64 newWeiPerUnit) external {
        ArbOwnerLib.arbOwner.setL1PricingRewardRate(newWeiPerUnit);
    }
}
