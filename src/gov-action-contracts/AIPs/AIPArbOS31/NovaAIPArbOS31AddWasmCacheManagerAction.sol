// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./parent_contracts/AIPArbOS31AddWasmCacheManagerAction.sol";

/// @notice for deplpoyment on Nova
contract NovaAIPArbOS31AddWasmCacheManagerAction is AIPArbOS31AddWasmCacheManagerAction {
    constructor()
        AIPArbOS31AddWasmCacheManagerAction(
            0x20586F83bF11a7cee0A550C53B9DC9A5887de1b7, // wasm cache manager
            31 // target arb os version
        )
    {}
}
