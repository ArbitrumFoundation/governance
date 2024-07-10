// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./parent_contracts/AIPArbOS30AddWasmCacheManagerAction.sol";

/// @notice for deloployment on Arb One
contract ArbOneAIPArbOS30AddWasmCacheManagerAction is AIPArbOS30AddWasmCacheManagerAction {
    constructor()
        AIPArbOS30AddWasmCacheManagerAction(
            0x51dEDBD2f190E0696AFbEE5E60bFdE96d86464ec, // wasm cache manager
            30 // target arb os version
        )
    {}
}
