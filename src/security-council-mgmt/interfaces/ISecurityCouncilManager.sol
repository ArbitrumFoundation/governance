// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Security councils members are members of one of two cohorts.
///         Periodically all the positions on a cohort are put up for election,
///         and the members replaced with new ones.
enum Cohort {
    FIRST,
    SECOND
}

/// @notice Addresses to be given specific roles on the Security Council Manager
struct SecurityCouncilManagerRoles {
    address admin;
    address cohortUpdator;
    address memberAdder;
    address[] memberRemovers;
    address memberRotator;
}

interface ISecurityCouncilManager {
    // TODO
    // function initialize(
    //     address[] memory _marchCohort,
    //     address[] memory _septemberCohort,
    //     SecurityCouncilManagerRoles memory _roles
    // ) external;
    /// @notice Replaces a whole cohort.
    /// @dev    Initiaties cross chain messages to update the individual Security Councils
    /// @param _newCohort   New cohort members to replace existing cohort. Must have 6 members.
    /// @param _cohort      Cohort to replace.
    function replaceCohort(address[] memory _newCohort, Cohort _cohort) external;
    /// @notice Add a member to the specified cohort
    ///         Cohorts cannot have more than 6 members, so the cohort must have less than 6 in order to call this.
    ///         New member cannot already be a member of either cohort
    /// @dev    Initiaties cross chain messages to update the individual Security Councils
    /// @param _newMember   New member to add
    /// @param _cohort      Cohort to add member to
    function addMember(address _newMember, Cohort _cohort) external;
    /// @notice Remove a member
    /// @dev    Searches both cohorts for the member.
    ///         Initiaties cross chain messages to update the individual Security Councils
    /// @param _member  Member to remove
    function removeMember(address _member) external;
    /// @notice Replace a member in a council - equivalent to removing a member, then adding another in its place
    /// @dev    Initiaties cross chain messages to update the individual Security Councils
    /// @param _memberToReplace Security Council member to remove
    /// @param _newMember       Security Council member to add in their place
    function replaceMember(address _memberToReplace, address _newMember) external;
    /// @notice All members of the first cohort
    function getFirstCohort() external view returns (address[] memory);
    /// @notice All members of the second cohort
    function getSecondCohort() external view returns (address[] memory);
}
