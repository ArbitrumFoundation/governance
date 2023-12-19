// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/SetWasmModuleRootAction.sol";
import "../../address-registries/L1AddressRegistry.sol";

/// @notice action deployed on L1 to set nova's wasm module root for ARBOS11 upgrade
contract SetNovaArbOS11ModuleRootAction is SetWasmModuleRootAction {
    constructor()
        SetWasmModuleRootAction(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635),
            bytes32(0xf4389b835497a910d7ba3ebfb77aa93da985634f3c052de1290360635be40c4a)
        )
    {}
}
