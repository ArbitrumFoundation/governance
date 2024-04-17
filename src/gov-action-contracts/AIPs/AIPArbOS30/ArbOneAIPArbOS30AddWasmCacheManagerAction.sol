// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./parent_contracts/AIPArbOS30AddWasmCacheManagerAction.sol";

/// @notice for deloployment on Arb One
contract ArbOneAIPArbOS30AddWasmCacheManagerAction is AIPArbOS30AddWasmCacheManagerAction {
    constructor()
        AIPArbOS30AddWasmCacheManagerAction(
            address(0), // wasm cache manager TODO
            30 // target arb os version
        )
    {}
}
