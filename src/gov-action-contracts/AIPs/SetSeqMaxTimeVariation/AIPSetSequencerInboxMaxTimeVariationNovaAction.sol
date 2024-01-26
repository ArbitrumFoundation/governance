// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../address-registries/interfaces.sol";
import "../../sequencer/SetSequencerInboxMaxTimeVariationAction.sol";

/// @notice Set the future blocks / future seconds to 64 blocks and 64 * 12 seconds so that small L1 reorgs don't cause batches to revert. Delay blocks / delay seconds remain their current values.
contract AIPSetSequencerInboxMaxTimeVariationNovaAction is
    SetSequencerInboxMaxTimeVariationAction
{
    constructor()
        SetSequencerInboxMaxTimeVariationAction(
            ISequencerInboxGetter(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635), // Nova Address Registry
            5760, // Delay blocks (same as current value)
            64, // New future blocks value
            86_400, //  Delay seconds (same as current value)
            768 // New future seconds value (future blocks * 12)
        )
    {}
}
