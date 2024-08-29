// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import "./ArbPrecompilesLib.sol";

contract RemoveChainOwnerAction {
    function perform(address oldOwner) external {
        ArbPrecompilesLib.arbOwner.removeChainOwner(oldOwner);
    }
}
