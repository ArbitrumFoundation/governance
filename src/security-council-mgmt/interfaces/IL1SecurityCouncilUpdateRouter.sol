// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IL1SecurityCouncilUpdateRouter {
    function handleUpdateCohort(
        address[] calldata _membersToAdd,
        address[] calldata _membersToRemove
    ) external;
    function handleAddMember(address _member) external;
    function handleRemoveMember(address _prevMemberInLinkedList, address _member) external;
}
