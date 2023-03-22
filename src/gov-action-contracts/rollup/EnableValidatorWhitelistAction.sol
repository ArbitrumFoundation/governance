// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract EnableValidatorWhitelistAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        addressRegistry.rollup().setValidatorWhitelistDisabled(false);
    }
}
