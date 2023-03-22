// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetL1PricingRewardRecipientAction {
    function perform(address newRecipient) external {
        ArbPrecompilesLib.arbOwner.setL1PricingRewardRecipient(newRecipient);
    }
}
