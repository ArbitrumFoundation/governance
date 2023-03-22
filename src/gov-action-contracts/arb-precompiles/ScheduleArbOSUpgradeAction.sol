// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbPrecompilesLib.sol";

contract ScheduleArbOSUpgradeAction {
    function perform(uint64 newVersion, uint64 timestamp) external {
        ArbPrecompilesLib.arbOwner.scheduleArbOSUpgrade(newVersion, timestamp);
    }
}
