// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract ReleaseL1PricerSurplusFundsAction {
    function perform(uint256 maxWeiToRelease) external {
        ArbPrecompilesLib.arbOwner.releaseL1PricerSurplusFunds(maxWeiToRelease);
    }
}
