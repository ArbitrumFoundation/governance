// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./OutboxActionLib.sol";

contract RollupSetOutboxAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(IOutbox outbox) external {
        OutboxActionLib.rollupSetOutboxAction(addressRegistry, outbox);
    }
}
