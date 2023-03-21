// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetL1PricingEquilibrationUnitsAction {
    function perform(uint256 newUnits) external {
        ArbOwnerLib.arbOwner.setL1PricingEquilibrationUnits(newUnits);
    }
}
