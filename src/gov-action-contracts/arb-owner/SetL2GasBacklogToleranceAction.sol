// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetL2GasBacklogToleranceAction {
    function perform(uint64 newTolerance) external {
        ArbOwnerLib.arbOwner.setL2GasBacklogTolerance(newTolerance);
    }
}
