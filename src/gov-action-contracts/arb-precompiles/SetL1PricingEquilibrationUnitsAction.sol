// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetL1PricingEquilibrationUnitsAction {
    function perform(uint256 newUnits) external {
        ArbPrecompilesLib.arbOwner.setL1PricingEquilibrationUnits(newUnits);
    }
}
