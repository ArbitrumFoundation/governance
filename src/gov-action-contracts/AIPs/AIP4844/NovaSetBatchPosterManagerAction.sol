// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./SetBatchPosterManager.sol";

/// @notice set gnosis safe to batch-poster-manager role for Nova SequencerInbox
contract NovaSetBatchPosterManagerAction is SetBatchPosterManager {
    constructor()
        SetBatchPosterManager(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635), // L1 address registry for Nova
            0xd0FDA6925f502a3a94986dfe7C92FE19EBbD679B // batch poster manager (gnosis safe)
        )
    {}
}
