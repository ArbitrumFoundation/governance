// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../address-registries/interfaces.sol";
import "../../sequencer/SetSequencerInboxMaxTimeVariationAction.sol";

contract AIPSetSequencerInboxMaxTimeVariationNovaAction is
    SetSequencerInboxMaxTimeVariationAction
{
    // TODO: confirm / finalize values
    constructor()
        SetSequencerInboxMaxTimeVariationAction(
            ISequencerInboxGetter(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635),
            5760,
            64,
            86_400,
            768
        )
    {}
}
