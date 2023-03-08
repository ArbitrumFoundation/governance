// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./OutboxActionLib.sol";

contract BridgeRemoveOutboxesAction {
    IBridgeGetter public immutable addressRegistry;

    constructor(IBridgeGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address[] calldata outboxes) external {
        OutboxActionLib.bridgeRemoveOutboxes(addressRegistry, outboxes);
    }
}
