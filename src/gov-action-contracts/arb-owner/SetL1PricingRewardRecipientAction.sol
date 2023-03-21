// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetL1PricingRewardRecipientAction {
    function perform(address newRecipient) external {
        ArbOwnerLib.arbOwner.setL1PricingRewardRecipient(newRecipient);
    }
}
