// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract SetSequencerInboxMaxTimeVariationAction {
    ISequencerInbox public immutable sequencerInbox;
    uint256 public immutable delayBlocks;
    uint256 public immutable futureBlocks;
    uint256 public immutable delaySeconds;
    uint256 public immutable futureSeconds;

    constructor(
        ISequencerInboxGetter _addressRegistry,
        uint256 _delayBlocks,
        uint256 _futureBlocks,
        uint256 _delaySeconds,
        uint256 _futureSeconds
    ) {
        sequencerInbox = _addressRegistry.sequencerInbox();
        delayBlocks = _delayBlocks;
        futureBlocks = _futureBlocks;
        delaySeconds = _delaySeconds;
        futureSeconds = _futureSeconds;
    }

    function perform() external {
        sequencerInbox.setMaxTimeVariation(
            ISequencerInbox.MaxTimeVariation({
                delayBlocks: delayBlocks,
                futureBlocks: futureBlocks,
                delaySeconds: delaySeconds,
                futureSeconds: futureSeconds
            })
        );
    }
}
