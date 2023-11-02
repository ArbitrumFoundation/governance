// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/SetWasmModuleRootAction.sol";
import "../../address-registries/L1AddressRegistry.sol";

/// @notice action deployed on L1 to set nova's wasm module root for ARBOS11 upgrade
contract SetNovaArbOS11ModuleRootAction is SetWasmModuleRootAction {
    constructor()
        SetWasmModuleRootAction(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635),
            bytes32(0x92a7978d7ef64fa82a33c9d9af77647d9014c345a24ebf41635bc89e1c45e35b)
        )
    {}
}
