// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./AIP4844Action.sol";

/// @notice Upgrade Nova core contracts in preparation for 4844
contract NovaAIP4844Action is AIP4844Action {
    constructor()
        AIP4844Action(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635), // L1 address registry for Nova,
            0x8b104a2e80ac6165dc58b9048de12f301d70b02a0ab51396c22b4b4b802a16a4, // arbos20 wasm module root, built from https://github.com/OffchainLabs/nitro/commit/cf2eadfcc1039eca9594c4f71477a50f550d7749
            0x31DA64D19Cd31A19CD09F4070366Fe2144792cf7, // new sequencer inbox impl
            0xE129b8Aa61dF65cBDbAE4345eE3fb40168DfD566, // new challenge manager impl
            ProxyAdmin(0x71D78dC7cCC0e037e12de1E50f5470903ce37148), //  L1 core contracts proxy admin for Nova
            0xC6E1E6dB03c3F475bC760FE20ed93401EC5c4F7e // new one step proof
        )
    {}
}
