// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract SetNetworkFeeAccountAction {
    function perform(address newNetworkFeeAccount) external {
        ArbOwnerLib.arbOwner.setNetworkFeeAccount(newNetworkFeeAccount);
    }
}
