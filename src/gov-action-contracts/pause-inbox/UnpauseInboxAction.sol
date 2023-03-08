// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract UnpauseInboxAction {
    IInboxGetter public immutable addressRegistry;

    constructor(IInboxGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        addressRegistry.inbox().unpause();
    }
}
