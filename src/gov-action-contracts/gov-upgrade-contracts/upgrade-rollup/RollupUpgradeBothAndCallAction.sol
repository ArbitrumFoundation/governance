// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";
import "../../address-registries/interfaces.sol";

contract RollupUpgradeBothAndCallAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(
        address newPrimaryLogic,
        address newSecondaryLogic,
        uint256 valueForPrimary,
        uint256 valueForSecondary,
        bytes calldata dataForPrimary,
        bytes calldata dataForSecondary
    ) public payable {
        require(
            msg.value == valueForPrimary + valueForSecondary,
            "RollupUpgradeBothAndCallAction: callvalue mismatches with params"
        );
        address rollupAddress = address(addressRegistry.rollup());

        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeToAndCall{value: valueForPrimary}(
            newPrimaryLogic, dataForPrimary
        );
        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeSecondaryToAndCall{
            value: valueForSecondary
        }(newSecondaryLogic, dataForSecondary);
    }
}
