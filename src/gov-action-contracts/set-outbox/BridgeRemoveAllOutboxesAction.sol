// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./OutboxActionLib.sol";

contract BridgeRemoveAllOutboxesAction {
    IBridgeGetter public immutable addressRegistry;

    constructor(IBridgeGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        OutboxActionLib.bridgeRemoveAllOutboxes(addressRegistry);
    }
}
