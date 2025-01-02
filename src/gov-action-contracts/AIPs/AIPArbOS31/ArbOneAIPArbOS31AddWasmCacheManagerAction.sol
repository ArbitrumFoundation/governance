// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./parent_contracts/AIPArbOS31AddWasmCacheManagerAction.sol";

/// @notice for deloployment on Arb One
contract ArbOneAIPArbOS31AddWasmCacheManagerAction is AIPArbOS31AddWasmCacheManagerAction {
    constructor()
        AIPArbOS31AddWasmCacheManagerAction(
            0x51dEDBD2f190E0696AFbEE5E60bFdE96d86464ec, // wasm cache manager
            31 // target arb os version
        )
    {}
}
