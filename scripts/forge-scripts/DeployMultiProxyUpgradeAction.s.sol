// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import {Script} from "forge-std/Script.sol";
import {
    MultiProxyUpgradeAction
} from "src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/MultiProxyUpgradeAction.sol";
import {DeployConstants} from "scripts/forge-scripts/DeployConstants.sol";

/// @title DeployMultiProxyUpgradeAction.
/// @notice Script to deploy the `MultiProxyUpgradeAction` contract.
/// @dev `MultiProxyUpgradeAction` contract is used to upgrade multiple governor proxies in a single transaction.
contract DeployMultiProxyUpgradeAction is DeployConstants, Script {
    function run(address _newGovernorImplementationAddress)
        public
        returns (MultiProxyUpgradeAction multiProxyUpgradeAction)
    {
        vm.startBroadcast();
        multiProxyUpgradeAction = new MultiProxyUpgradeAction(
            L2_PROXY_ADMIN_CONTRACT,
            L2_CORE_GOVERNOR,
            L2_TREASURY_GOVERNOR,
            _newGovernorImplementationAddress
        );
        vm.stopBroadcast();
    }
}
