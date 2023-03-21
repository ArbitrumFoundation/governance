// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetPerBatchGasChargeAction {
    function perform(int64 cost) external {
        ArbOwnerLib.arbOwner.setPerBatchGasCharge(cost);
    }
}
