// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";

// ArbOwner interface will include addWasmCacheManager as of stylus upgrade
interface IUpdatedArbOwner {
    function addWasmCacheManager(address manager) external;
}

// @notice For deployment on an Arbitrum chain;
// adds wasm cache manager only when the stylus ArbOS upgrade activates.
// Should be called via retryable ticket so that if executed before the ArbOS upgrade,
// it reverts can be retried until the target ArbOS version number is active.
contract AIPArbOS30AddWasmCacheManagerAction {
    // wasm cache manager to add
    address public immutable wasmCachemanager;

    // ArbOS version; use value as it's set and commonly used, NOT the value returned by
    // ArbSys, which adds 55. E.g., the value here should be 30, not 85
    uint256 public immutable targetArbOSVersion;

    constructor(address _wasmCachemanager, uint256 _targetArbOSVersion) {
        wasmCachemanager = _wasmCachemanager;
        targetArbOSVersion = _targetArbOSVersion;
    }

    function perform() external {
        // getter returns a value offset by 55: https://github.com/OffchainLabs/nitro/blob/a20a1c70cc11ac52c7cfe6a20f00c880c2009a8f/precompiles/ArbSys.go#L64
        uint256 currentArbOsVersion =
            ArbSys(0x0000000000000000000000000000000000000064).arbOSVersion() - 55;
        // revert if target arbos version not reached; since this is executed by a retryable, can be re-executed until target version is reached
        require(
            targetArbOSVersion == currentArbOsVersion,
            "AIPArbOS30AddWasmCacheManagerAction: ArbOS version"
        );

        IUpdatedArbOwner(0x0000000000000000000000000000000000000070).addWasmCacheManager(
            wasmCachemanager
        );
    }
}
