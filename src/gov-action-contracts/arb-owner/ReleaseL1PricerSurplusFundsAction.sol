// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOwnerLib.sol";

contract ReleaseL1PricerSurplusFundsAction {
    function perform(uint256 maxWeiToRelease) external {
        ArbOwnerLib.arbOwner.releaseL1PricerSurplusFunds(maxWeiToRelease);
    }
}
