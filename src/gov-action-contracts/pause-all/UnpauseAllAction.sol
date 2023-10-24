// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "../set-outbox/OutboxActionLib.sol";
import "../sequencer/SequencerActionLib.sol";

/// @notice unpause inbox and rollup, add outboxes and sequencers (i.e., undoes PauseAllAction)
contract UnPauseAllAction {
    IL1AddressRegistry public immutable addressRegistry;
    address[] sequencersToAdd;
    address[] outboxesToAdd;

    constructor(
        IL1AddressRegistry _addressRegistry,
        address[] memory _sequencersToAdd,
        address[] memory outboxesToAdd
    ) {
        addressRegistry = _addressRegistry;
        sequencersToAdd = _sequencersToAdd;
        outboxesToAdd = outboxesToAdd;
    }

    function perform() external {
        addressRegistry.inbox().unpause();
        addressRegistry.rollup().resume();
        OutboxActionLib.bridgeAddOutboxes(addressRegistry, outboxesToAdd);
        for (uint256 i = 0; i < sequencersToAdd.length; i++) {
            SequencerActionLib.addSequencer(addressRegistry, sequencersToAdd[i]);
        }
    }
}
