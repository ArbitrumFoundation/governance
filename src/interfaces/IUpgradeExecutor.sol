// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

// TODO: import from @offchainlabs/upgrade-executor@1.1.1
interface IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
    function ADMIN_ROLE() external view returns (bytes32);
    function EXECUTOR_ROLE() external view returns (bytes32);
}
