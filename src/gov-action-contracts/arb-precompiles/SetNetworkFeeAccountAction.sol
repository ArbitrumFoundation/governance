// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetNetworkFeeAccountAction {
    function perform(address newNetworkFeeAccount) external {
        ArbPrecompilesLib.arbOwner.setNetworkFeeAccount(newNetworkFeeAccount);
    }
}
