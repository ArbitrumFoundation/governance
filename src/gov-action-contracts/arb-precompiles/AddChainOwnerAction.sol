// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract AddChainOwnerAction {
    function perform(address newOwner) external {
        ArbPrecompilesLib.arbOwner.addChainOwner(newOwner);
    }
}
