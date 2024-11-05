// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "../address-registries/interfaces.sol";
import "./SequencerActionLib.sol";

contract RemoveSequencerAction {
    ISequencerInboxGetter public immutable addressRegistry;

    constructor(ISequencerInboxGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address sequencer) external {
        SequencerActionLib.removeSequencer(addressRegistry, sequencer);
    }
}
