// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

interface ISequencerDelayBuffer {
    struct BufferConfig {
        uint64 threshold;
        uint64 max;
        uint64 replenishRateInBasis;
    }

    function setBufferConfig(BufferConfig memory bufferConfig_) external;
}

contract SetBufferConfigAction {
    ISequencerInboxGetter public immutable addressRegistry;

    constructor(ISequencerInboxGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(ISequencerDelayBuffer.BufferConfig memory bufferConfig_) external {
        ISequencerDelayBuffer(address(addressRegistry.sequencerInbox())).setBufferConfig(
            bufferConfig_
        );
    }
}
