// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

interface IUpgradeExecutor is IAccessControlUpgradeable {
    function execute(address upgrade, bytes memory upgradeCallData) external;
    function ADMIN_ROLE() external returns (bytes32);
    function EXECUTOR_ROLE() external returns (bytes32);
}
