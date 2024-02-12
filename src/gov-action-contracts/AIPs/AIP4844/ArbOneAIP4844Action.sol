// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./AIP4844Action.sol";

/// @notice Upgrade ArbOne core contracts in preparation for 4844
contract ArbOneAIP4844Action is AIP4844Action {
    constructor()
        AIP4844Action(
            L1AddressRegistry(0xd514C2b3aaBDBfa10800B9C96dc1eB25427520A0), // L1 address registry for Arb One,
            0x8b104a2e80ac6165dc58b9048de12f301d70b02a0ab51396c22b4b4b802a16a4, // arbos20 wasm module root, built from https://github.com/OffchainLabs/nitro/commit/cf2eadfcc1039eca9594c4f71477a50f550d7749
            0x31DA64D19Cd31A19CD09F4070366Fe2144792cf7, // new sequencer inbox impl
            0xE129b8Aa61dF65cBDbAE4345eE3fb40168DfD566, // new challenge manager impl
            ProxyAdmin(0x554723262467F125Ac9e1cDFa9Ce15cc53822dbD), // L1 core contracts proxy admin for Arb One
            0xC6E1E6dB03c3F475bC760FE20ed93401EC5c4F7e // new one step proof
        )
    {}
}
