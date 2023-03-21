// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetInfraFeeAccountAction {
    function perform(address newInfraFeeAccount) external {
        ArbOwnerLib.arbOwner.setInfraFeeAccount(newInfraFeeAccount);
    }
}
