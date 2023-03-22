// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetL1PricePerUnitAction {
    function perform(uint256 newPricePerUnit) external {
        ArbPrecompilesLib.arbOwner.setL1PricePerUnit(newPricePerUnit);
    }
}
