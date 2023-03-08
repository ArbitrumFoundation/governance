// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

library SequencerActionLib {
    modifier notZeroAddress(address sequencer) {
        require(sequencer != address(0), "SequencerActionLib sequencer param cannot be address(0)");
        _;
    }

    function removeSequencer(ISequencerInboxGetter addressRegistry, address sequencer)
        internal
        notZeroAddress(sequencer)
    {
        addressRegistry.sequencerInbox().setIsBatchPoster(sequencer, false);
    }

    function addSequencer(ISequencerInboxGetter addressRegistry, address sequencer)
        internal
        notZeroAddress(sequencer)
    {
        addressRegistry.sequencerInbox().setIsBatchPoster(sequencer, true);
    }
}
