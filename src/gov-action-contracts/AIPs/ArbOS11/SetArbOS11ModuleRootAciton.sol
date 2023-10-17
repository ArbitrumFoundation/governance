// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../arbos-upgrade/SetWasmModuleRootAction.sol";
import "../../address-registries/L1AddressRegistry.sol";

contract SetArbOS11ModuleRootAciton is SetWasmModuleRootAction {
    constructor()
        SetWasmModuleRootAction(
            L1AddressRegistry(0xd514C2b3aaBDBfa10800B9C96dc1eB25427520A0),
            // TODO
            bytes32(0)
        )
    {
        require(newWasmModuleRoot != bytes32(0), "TODO: remove");
    }
}
