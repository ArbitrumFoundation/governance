// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

enum Cohort {
    FIRST,
    SECOND
}

struct SecurityCouncilManagerRoles {
    address admin;
    address cohortUpdator;
    address memberAdder;
    address[] memberRemovers;
    address memberRotator;
}

// data for a security council to be managed
struct SecurityCouncilData {
    address securityCouncil;
    address updateActionAddr;
    address upgradeExecutor;
    address inbox; // address(0) for inbox means the security council is on L1
}

interface ISecurityCouncilManager {
    function initialize(
        address[] memory _marchCohort,
        address[] memory _septemberCohort,
        SecurityCouncilData[] memory _securityCouncils,
        SecurityCouncilManagerRoles memory _roles,
        address _l1CoreGovTimelock,
        address payable _l2CoreGovTimelock,
        uint256 _minL1TimelockDelay
    ) external;
    function replaceCohort(address[] memory _newCohort, Cohort _cohort) external;
    function addMember(address _newMember, Cohort _cohort) external;
    function removeMember(address _member) external;
    function getFirstCohort() external view returns (address[] memory);
    function getSecondCohort() external view returns (address[] memory);
    function addSecurityCouncil(SecurityCouncilData memory _securityCouncilData) external;
    function removeSecurityCouncil(uint256 _index) external;
    function setMinL1TimelockDelay(uint256 _minL1TimelockDelay) external;
}
