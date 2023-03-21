// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetMinimumL2BaseFeeAction {
    function perform(uint256 newMinimumL2BaseFee) external {
        ArbOwnerLib.arbOwner.setMinimumL2BaseFee(newMinimumL2BaseFee);
    }
}
