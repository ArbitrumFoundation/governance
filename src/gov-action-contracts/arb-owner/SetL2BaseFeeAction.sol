// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetL2BaseFeeAction {
    function perform(uint256 newL2BaseFee) external {
        ArbOwnerLib.arbOwner.setL2BaseFee(newL2BaseFee);
    }
}
