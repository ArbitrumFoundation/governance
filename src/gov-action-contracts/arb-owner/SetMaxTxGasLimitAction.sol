// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetMaxTxGasLimitAction {
    function perform(uint64 newMaxTxGasLimit) external {
        ArbOwnerLib.arbOwner.setMaxTxGasLimit(newMaxTxGasLimit);
    }
}
