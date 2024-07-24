// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/UpgradeArbOSVersionAtTimestampAction.sol";

/// @notice Sets the ArbOS version to 31. To be run on an arbitrum chain
/// @dev    Identical copies of this contract to be deployed on Arb One and Nova for ArbOS31 upgrades
contract SetArbOS31VersionAction is UpgradeArbOSVersionAtTimestampAction {
    constructor() UpgradeArbOSVersionAtTimestampAction(uint64(31), 1725382800) {}
}
