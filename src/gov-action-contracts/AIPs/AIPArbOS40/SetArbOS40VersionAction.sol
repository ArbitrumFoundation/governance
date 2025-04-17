// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/UpgradeArbOSVersionAction.sol";

/// @notice Sets the ArbOS version to 40. To be run on an arbitrum chain
/// @dev    Identical copies of this contract to be deployed on Arb One and Nova for ArbOS40 upgrades
contract SetArbOS40VersionAction is UpgradeArbOSVersionAction {
    constructor() UpgradeArbOSVersionAction(uint64(40), uint64(1 weeks)) {}
}
