// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract DisableValidatorWhitelistAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        IRollupAdmin(address(addressRegistry.rollup())).setValidatorWhitelistDisabled(true);
    }
}
