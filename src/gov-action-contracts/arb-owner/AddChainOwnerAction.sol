// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract AddChainOwnerAction {
    function perform(address newOwner) external {
        ArbOwnerLib.arbOwner.addChainOwner(newOwner);
    }
}
