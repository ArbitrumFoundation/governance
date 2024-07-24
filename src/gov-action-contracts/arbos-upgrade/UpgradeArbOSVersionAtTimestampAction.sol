// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/precompiles/ArbOwner.sol";

/// @notice should be included in an operation batch in the L1 timelock along with SetWasmModuleRootAction
contract UpgradeArbOSVersionAtTimestampAction {
    uint64 public immutable newArbOSVersion;
    uint64 public immutable upgradeTimestamp;

    constructor(uint64 _newArbOSVersion, uint64 _upgradeTimestamp) {
        newArbOSVersion = _newArbOSVersion;
        upgradeTimestamp = _upgradeTimestamp;
    }

    function perform() external {
        ArbOwner arbOwner = ArbOwner(0x0000000000000000000000000000000000000070);
        arbOwner.scheduleArbOSUpgrade({
            newVersion: newArbOSVersion,
            timestamp: upgradeTimestamp
        });
    }
}
