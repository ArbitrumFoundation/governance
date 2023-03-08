// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./SequencerActionLib.sol";

contract AddSequencerAction {
    ISequencerInboxGetter public immutable addressRegistry;

    constructor(ISequencerInboxGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address sequencer) external {
        SequencerActionLib.addSequencer(addressRegistry, sequencer);
    }
}
