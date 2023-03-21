// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract RemoveChainOwnerAction {
    function perform(address oldOwner) external {
        ArbOwnerLib.arbOwner.removeChainOwner(oldOwner);
    }
}
