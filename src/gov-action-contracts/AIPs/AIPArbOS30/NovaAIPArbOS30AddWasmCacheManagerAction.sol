// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./parent_contracts/AIPArbOS30AddWasmCacheManagerAction.sol";

/// @notice for deplpoyment on Nova
contract NovaAIPArbOS30AddWasmCacheManagerAction is AIPArbOS30AddWasmCacheManagerAction {
    constructor()
        AIPArbOS30AddWasmCacheManagerAction(
            0x20586F83bF11a7cee0A550C53B9DC9A5887de1b7, // wasm cache manager
            30 // target arb os version
        )
    {}
}
