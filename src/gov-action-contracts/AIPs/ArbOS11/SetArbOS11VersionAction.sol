// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/UpgradeArbOSVersionAction.sol";
import "../../address-registries/L1AddressRegistry.sol";

contract SetArbOS11VersionAction is UpgradeArbOSVersionAction {
    constructor()
        UpgradeArbOSVersionAction(
            uint64(11),
            // TODO:
            uint64(0)
        )
    {
        require(upgradeTimeDelaySeconds != uint64(0), "TODO: remove");
    }
}
