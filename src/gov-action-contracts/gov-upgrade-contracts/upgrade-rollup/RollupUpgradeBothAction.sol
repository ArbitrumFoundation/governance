// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";
import "../../address-registries/interfaces.sol";

contract UpgradeRollupBothAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address newPrimaryLogic, address newSecondaryLogic) public {
        address rollupAddress = address(addressRegistry.rollup());
        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeTo(newPrimaryLogic);
        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeSecondaryTo(newSecondaryLogic);
    }
}
