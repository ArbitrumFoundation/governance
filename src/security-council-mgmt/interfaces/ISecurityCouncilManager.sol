// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

enum Cohort {
    MARCH,
    SEPTEMBER
}

struct Roles {
    address admin;
    address cohortUpdator;
    address memberAdder;
    address[] memberRemovers;
    address memberRotator;
}

interface ISecurityCouncilManager {
    function initialize(
        address[] memory _marchCohort,
        address[] memory _septemberCohort,
        Roles memory _roles,
        address _targetContracts,
        uint256 minDelay
    ) external;
    function executeElectionResult(address[] memory _newCohort, Cohort _cohort) external;
    function addMemberToCohort(address _newMember, Cohort _cohort) external;
    function removeMember(address _member) external returns (bool);
    function setL1SecurityCouncilUpdateRouter(address _l1SecurityCouncilUpdateRouter) external;
    function getMarchCohort() external view returns (address[] memory);
    function getSeptemberCohort() external view returns (address[] memory);
}
