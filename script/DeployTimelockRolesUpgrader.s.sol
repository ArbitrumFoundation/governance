// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseDeployer} from "script/BaseDeployer.sol";
import {TimelockRolesUpgrader} from
    "src/gov-action-contracts/gov-upgrade-contracts/update-timelock-roles/TimelockRolesUpgrader.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";

contract DeployTimelockRolesUpgrader is BaseDeployer, SharedGovernorConstants {
    function run() public returns (TimelockRolesUpgrader timelockRolesUpgrader) {
        vm.startBroadcast();
        timelockRolesUpgrader = new TimelockRolesUpgrader(
            L2_CORE_GOVERNOR_TIMELOCK,
            L2_CORE_GOVERNOR,
            L2_CORE_GOVERNOR_ONCHAIN,
            L2_TREASURY_GOVERNOR_TIMELOCK,
            L2_TREASURY_GOVERNOR,
            L2_TREASURY_GOVERNOR_ONCHAIN
        );
        vm.stopBroadcast();
    }
}
