// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "../set-outbox/OutboxActionLib.sol";
import "../sequencer/SequencerActionLib.sol";

/// @notice pause inbox and rollup, remove all outboxes and sequencers
contract PauseAllAction {
    IL1AddressRegistry public immutable addressRegistry;

    constructor(IL1AddressRegistry _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        addressRegistry.inbox().pause();
        addressRegistry.rollup().pause();
        OutboxActionLib.bridgeRemoveAllOutboxes(addressRegistry);
        address[] memory sequencersToRemove = addressRegistry.getSequencers();
        for (uint256 i = 0; i < sequencersToRemove.length; i++) {
            SequencerActionLib.removeSequencer(addressRegistry, sequencersToRemove[i]);
        }
    }
}
