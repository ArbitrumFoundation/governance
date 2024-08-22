// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import "./ArbPrecompilesLib.sol";

contract SetL2BaseFeeAction {
    function perform(uint256 newL2BaseFee) external {
        ArbPrecompilesLib.arbOwner.setL2BaseFee(newL2BaseFee);
    }
}
