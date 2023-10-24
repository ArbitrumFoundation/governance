// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "../set-outbox/OutboxActionLib.sol";
import "../sequencer/SequencerActionLib.sol";

/// @notice pause inbox and rollup, remove all outboxes and sequencers
contract PauseAllAction {
    IL1AddressRegistry public immutable addressRegistry;
    address[] sequencersToRemove;

    constructor(IL1AddressRegistry _addressRegistry, address[] memory _sequencersToRemove) {
        addressRegistry = _addressRegistry;
        sequencersToRemove = _sequencersToRemove;
    }

    function perform() external {
        addressRegistry.inbox().pause();
        addressRegistry.rollup().pause();
        OutboxActionLib.bridgeRemoveAllOutboxes(addressRegistry);
        for (uint256 i = 0; i < sequencersToRemove.length; i++) {
            SequencerActionLib.removeSequencer(addressRegistry, sequencersToRemove[i]);
        }
    }
}
