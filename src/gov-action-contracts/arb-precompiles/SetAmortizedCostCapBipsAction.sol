// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "./ArbPrecompilesLib.sol";

contract SetAmortizedCostCapBipsAction {
    function perform(uint56 newAmortizedCostCapBips) external {
        ArbPrecompilesLib.arbOwner.setAmortizedCostCapBips(newAmortizedCostCapBips);
    }
}
