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

/// @notice Data for a Security Council to be managed
struct SecurityCouncilData {
    /// @notice Address of the Security Council
    address securityCouncil;
    /// @notice Address of the upgrade executor that has the rights to update
    ///         council membership
    address upgradeExecutor;
    /// @notice Address of the update action contract that contains the logic for
    ///         updating council membership. Will be delegate called by the upgrade executor
    address updateAction;
    /// @notice If the upgrade executor can only be reached by going through an Inbox
    ///         that address is supplied here.
    ///         address(0) can be supplied here, in which case the upgrade executor is called directly
    ///         rather than being passed through an inbox.
    address inbox;
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
    /// @notice Add new security council to be included in security council management system.
    /// @param _securityCouncilData Security council info
    function addSecurityCouncil(SecurityCouncilData memory _securityCouncilData) external;
    /// @notice Remove security council from management system.
    /// @param _index   Index in securityCouncils of data to be removed
    function removeSecurityCouncil(uint256 _index) external;
    /// @notice Set delay for messages to the L1 timelock. This should only be used to keep the minTimelockDelay value in sync with L1 (i.e., if the L1 side is updated, this should be too)
    /// @param _minL1TimelockDelay new  L1 timelock delay value
    function setMinL1TimelockDelay(uint256 _minL1TimelockDelay) external;
}
