// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";
import "../../address-registries/interfaces.sol";

contract RollupUpgradePrimaryAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address newPrimaryLogic) public {
        DoubleLogicUUPSUpgradeable(address(addressRegistry.rollup())).upgradeTo(newPrimaryLogic);
    }
}
