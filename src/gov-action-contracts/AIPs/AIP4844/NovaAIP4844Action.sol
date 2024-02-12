// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./AIP4844Action.sol";

/// @notice Upgrade Nova core contracts in preparation for 4844
contract NovaAIP4844Action is AIP4844Action {
    constructor()
        AIP4844Action(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635), // L1 address registry for Nova,
            bytes32(""), // wasm module root  TODO
            0x31DA64D19Cd31A19CD09F4070366Fe2144792cf7, // new sequencer inbox impl
            0xE129b8Aa61dF65cBDbAE4345eE3fb40168DfD566, // new challenge manager impl
            ProxyAdmin(0x71d78dc7ccc0e037e12de1e50f5470903ce37148), // l1 gov proxy admin
            0xC6E1E6dB03c3F475bC760FE20ed93401EC5c4F7e // new one step proof
        )
    {}
}
