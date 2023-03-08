// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";
import "../../address-registries/interfaces.sol";

contract RollupUpgradeSecondaryAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address newSecondaryLogic) public {
        DoubleLogicUUPSUpgradeable(address(addressRegistry.rollup())).upgradeSecondaryTo(
            newSecondaryLogic
        );
    }
}
