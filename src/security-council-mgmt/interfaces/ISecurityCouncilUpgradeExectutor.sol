// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface ISecurityCouncilUpgradeExectutor {
    function updateMembers(address[] calldata _membersToAdd, address[] calldata _membersToRemove)
        external;
    function addMember(address _member) external;
    function removeMember(address _prevMemberInLinkedList, address _member) external;
}
