// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetMinimumL2BaseFeeAction {
    function perform(uint256 newMinimumL2BaseFee) external {
        ArbPrecompilesLib.arbOwner.setMinimumL2BaseFee(newMinimumL2BaseFee);
    }
}
