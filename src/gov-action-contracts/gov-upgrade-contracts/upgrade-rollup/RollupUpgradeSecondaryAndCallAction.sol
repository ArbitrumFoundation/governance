// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";
import "../../address-registries/interfaces.sol";

contract RollupUpgradeSecondaryAndCallAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address newSecondaryLogic, bytes calldata data) public payable {
        DoubleLogicUUPSUpgradeable(address(addressRegistry.rollup())).upgradeSecondaryToAndCall{
            value: msg.value
        }(newSecondaryLogic, data);
    }
}
