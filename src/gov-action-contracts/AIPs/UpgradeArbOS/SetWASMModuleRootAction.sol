// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/rollup/IRollupLogic.sol" as rl;
import "@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol" as rc;
import "../../address-registries/L1AddressRegistry.sol";

/// @notice should be included in an operation batch in the L1 timelock along with UpgradeArbOSVersionAction
contract SetWasmModuleRootAction {
    address public immutable rollup;
    bytes32 public immutable newWasmModuleRoot;

    constructor(L1AddressRegistry _l1AddressRegistry, bytes32 _newWasmModuleRoot) {
        rollup = address(_l1AddressRegistry.rollup());
        newWasmModuleRoot = _newWasmModuleRoot;
    }

    function perform() external {
        rl.IRollupAdmin(rollup).setWasmModuleRoot(newWasmModuleRoot);

        // verify:
        require(
            rc.IRollupCore(rollup).wasmModuleRoot() == newWasmModuleRoot,
            "SetWasmModuleRootAction: wasm module root not set"
        );
    }
}
