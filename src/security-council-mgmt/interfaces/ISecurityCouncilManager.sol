// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

enum Cohort {
    MARCH,
    SEPTEMBER
}

struct Roles {
    address admin;
    address[] cohortUpdators;
    address memberAdder;
    address memberRemover;
    address memberRotator;
}

struct TargetContracts {
    address govChainEmergencySecurityCouncilUpgradeExecutor;
    address govChainNonEmergencySecurityCouncilUpgradeExecutor;
    address l1SecurityCouncilUpdateRouter;
}

interface ISecurityCouncilManager {
    function initialize(
        address[] memory _marchCohort,
        address[] memory _septemberCohort,
        Roles memory _roles,
        TargetContracts memory _targetContracts
    ) external;
    function executeElectionResult(address[] memory _newCohort, Cohort _cohort) external;
    function addMemberToCohort(address _newMember, Cohort _cohort) external;
    function removeMember(address _member) external returns (bool);
    function setTargetContracts(TargetContracts memory _targetContracts) external;
    function getMarchCohort() external view returns (address[] memory);
    function getSeptemberCohort() external view returns (address[] memory);
}
