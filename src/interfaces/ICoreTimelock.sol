// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "./IArbitrumTimelock.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

interface ICoreTimelock is IArbitrumTimelock, IAccessControlUpgradeable {
    function TIMELOCK_ADMIN_ROLE() external returns (bytes32);
    function PROPOSER_ROLE() external returns (bytes32);
    function EXECUTOR_ROLE() external returns (bytes32);
    function CANCELLER_ROLE() external returns (bytes32);
}
