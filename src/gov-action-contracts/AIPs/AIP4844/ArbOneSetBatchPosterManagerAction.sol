// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./SetBatchPosterManager.sol";

/// @notice set gnosis safe to batch-poster-manager role for ArbOne SequencerInbox
contract ArbOneSetBatchPosterManagerAction is SetBatchPosterManager {
    constructor()
        SetBatchPosterManager(
            L1AddressRegistry(0xd514C2b3aaBDBfa10800B9C96dc1eB25427520A0), // L1 address registry for Arb One
            0xd0FDA6925f502a3a94986dfe7C92FE19EBbD679B // batch poster manager (gnosis safe)
        )
    {}
}
