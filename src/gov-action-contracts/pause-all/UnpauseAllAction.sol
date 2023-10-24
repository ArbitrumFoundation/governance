// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "../set-outbox/OutboxActionLib.sol";
import "../sequencer/SequencerActionLib.sol";

/// @notice unpause inbox and rollup, add outboxes and sequencers (i.e., undoes PauseAllAction)
contract UnPauseAllAction {
    IL1AddressRegistry public immutable addressRegistry;

    constructor(IL1AddressRegistry _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform() external {
        addressRegistry.inbox().unpause();
        addressRegistry.rollup().resume();
        OutboxActionLib.bridgeAddOutboxes(addressRegistry, addressRegistry.getOutboxes());
        address[] memory sequencersToAdd = addressRegistry.getSequencers();
        for (uint256 i = 0; i < sequencersToAdd.length; i++) {
            SequencerActionLib.addSequencer(addressRegistry, sequencersToAdd[i]);
        }
    }
}
