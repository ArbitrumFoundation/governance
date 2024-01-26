// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/UpgradeArbOSVersionAction.sol";
import "../../address-registries/L1AddressRegistry.sol";

/// @notice identical copies of this contract to be deployed on Arb One and Nova for ArbOS11 upgrades
contract SetArbOS11VersionAction is UpgradeArbOSVersionAction {
    constructor() UpgradeArbOSVersionAction(uint64(11), uint64(1 weeks)) {}
}
