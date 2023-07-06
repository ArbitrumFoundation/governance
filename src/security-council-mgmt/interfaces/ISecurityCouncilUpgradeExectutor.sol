// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface ISecurityCouncilUpgradeExectutor {
    function perform(address[] memory _membersToAdd, address[] memory _membersToRemove) external;
}
