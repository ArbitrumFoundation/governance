// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetSpeedLimitAction {
    function perform(uint64 newSpeedLimit) external {
        ArbPrecompilesLib.arbOwner.setSpeedLimit(newSpeedLimit);
    }
}
