// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";
import "../../address-registries/interfaces.sol";

contract RollupUpgradePrimaryAndCallAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address newPrimaryLogic, bytes calldata data) public payable {
        DoubleLogicUUPSUpgradeable(address(addressRegistry.rollup())).upgradeToAndCall{
            value: msg.value
        }(newPrimaryLogic, data);
    }
}
