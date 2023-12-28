// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../address-registries/interfaces.sol";
import "../../sequencer/SetSequencerInboxMaxTimeVariationAction.sol";

contract AIPSetSequencerInboxMaxTimeVariationArbOneAction is
    SetSequencerInboxMaxTimeVariationAction
{
    // TODO: confirm / finalize values
    constructor()
        SetSequencerInboxMaxTimeVariationAction(
            0xd514C2b3aaBDBfa10800B9C96dc1eB25427520A0,
            5760,
            64,
            86_400,
            768
        )
    {}
}
