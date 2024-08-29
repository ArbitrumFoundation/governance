// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import "./ArbPrecompilesLib.sol";

contract SetL1PricingInertiaAction {
    function perform(uint64 newInertia) external {
        ArbPrecompilesLib.arbOwner.setL1PricingInertia(newInertia);
    }
}
