// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L1AddressRegistry.sol";

/// @notice should be included in an operation batch in the L1 timelock along with UpgradeArbOSVersionAction
contract SetWasmModuleRootAction {
    address public immutable rollup;
    bytes32 public immutable newWasmModuleRoot;

    constructor(L1AddressRegistry _l1AddressRegistry, bytes32 _newWasmModuleRoot) {
        rollup = address(_l1AddressRegistry.rollup());
        newWasmModuleRoot = _newWasmModuleRoot;
    }

    function perform() external {
        IRollupAdmin(rollup).setWasmModuleRoot(newWasmModuleRoot);

        // verify:
        require(
            IRollupCore(rollup).wasmModuleRoot() == newWasmModuleRoot,
            "SetWasmModuleRootAction: wasm module root not set"
        );
    }
}
