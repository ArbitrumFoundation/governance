// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract SetInfraFeeAccountAction {
    function perform(address newInfraFeeAccount) external {
        ArbPrecompilesLib.arbOwner.setInfraFeeAccount(newInfraFeeAccount);
    }
}
