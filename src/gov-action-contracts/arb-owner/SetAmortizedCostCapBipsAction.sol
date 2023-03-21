// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetAmortizedCostCapBipsAction {
    function perform(uint56 newAmortizedCostCapBips) external {
        ArbOwnerLib.arbOwner.setAmortizedCostCapBips(newAmortizedCostCapBips);
    }
}
