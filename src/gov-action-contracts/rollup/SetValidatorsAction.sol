// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract SetValidatorsAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address[] calldata _validators, bool[] calldata _values) external {
        IRollupAdmin(address(addressRegistry.rollup())).setValidator(_validators, _values);
    }
}
