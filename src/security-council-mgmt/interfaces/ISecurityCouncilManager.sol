// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../UpgradeExecRouteBuilder.sol";
import "../Common.sol";

/// @notice Addresses to be given specific roles on the Security Council Manager
struct SecurityCouncilManagerRoles {
    address admin;
    address cohortUpdator;
    address memberAdder;
    address[] memberRemovers;
    address memberRotator;
    address memberReplacer;
    address minRotationPeriodSetter;
}

/// @notice Data for a Security Council to be managed
struct SecurityCouncilData {
    /// @notice Address of the Security Council
    address securityCouncil;
    /// @notice Address of the update action contract that contains the logic for
    ///         updating council membership. Will be delegate called by the upgrade executor
    address updateAction;
    uint256 chainId;
}

interface ISecurityCouncilManager {
    // security council cohort errors
    error NotAMember(address member);
    error MemberInCohort(address member, Cohort cohort);
    error CohortFull(Cohort cohort);
    error InvalidNewCohortLength(address[] cohort, uint256 cohortSize);
    error CohortLengthMismatch(address[] cohort1, address[] cohort2);
    error InvalidCohort(Cohort cohort);

    // security council data errors
    error MaxSecurityCouncils(uint256 securityCouncilCount);
    error SecurityCouncilZeroChainID(SecurityCouncilData securiyCouncilData);
    error SecurityCouncilNotInRouter(SecurityCouncilData securiyCouncilData);
    error SecurityCouncilNotInManager(SecurityCouncilData securiyCouncilData);
    error SecurityCouncilAlreadyInRouter(SecurityCouncilData securiyCouncilData);

    // rotation errors
    error RotationTooSoon(address rotator, uint256 rotatableWhen);
    error GovernorNotReplacer();
    error NewMemberIsContender(uint256 proposalId, address newMember);
    error NewMemberIsNominee(uint256 proposalId, address newMember);
    error InvalidNewAddress(address newAddress);

    function rotatedTo(address) external view returns (address);
    function rotationNonce(address) external view returns (uint256);

    /// @notice There is a minimum period between when an address can be rotated
    ///         This is to ensure a single member cannot do many rotations in a row
    function minRotationPeriod() external view returns (uint256);
    function MIN_ROTATION_PERIOD_SETTER_ROLE() external view returns (bytes32);
    function MEMBER_REMOVER_ROLE() external view returns (bytes32);

    /// @notice initialize SecurityCouncilManager.
    /// @param _firstCohort addresses of first cohort
    /// @param _secondCohort addresses of second cohort
    /// @param _securityCouncils data of all security councils to manage
    /// @param _roles permissions for triggering modifications to security councils
    /// @param  _l2CoreGovTimelock timelock for core governance / constitutional proposal
    /// @param _router UpgradeExecRouteBuilder address
    /// @param _minRotationPeriod The minimum amount of time that must happen between address rotations by the same council member
    ///                           Rotations are in race conditions with other actions, so care must be taken to set this parameter to be
    ///                           greater than the time taken for other actions. An example of this is if the removal governor has the removal
    ///                           role it may try to remove an address, but doing so requires passing a vote and in the meantime the address may
    ///                           rotate. If the address is only allowed to rotate once during this period the manager can keep track of this and still
    ///                           and still remove the address, however if the rotation period allows for two rotations the address will not get removed
    ///                           A general rule for setting the min rotation period is: make sure it is longer that the amount of time taken to conduct
    ///                           any other actions on the sec council manager.
    function initialize(
        address[] memory _firstCohort,
        address[] memory _secondCohort,
        SecurityCouncilData[] memory _securityCouncils,
        SecurityCouncilManagerRoles memory _roles,
        address payable _l2CoreGovTimelock,
        UpgradeExecRouteBuilder _router,
        uint256 _minRotationPeriod
    ) external;
    /// @notice Set the min rotation period. This is the minimum period that must occur
    ///         between two consecutive rotations by the same member
    /// @param _minRotationPeriod   The new minimum rotation period to be set
    function setMinRotationPeriod(uint256 _minRotationPeriod) external;
    /// @notice Replaces a whole cohort.
    /// @dev    Initiates cross chain messages to update the individual Security Councils.
    /// @param _newCohort   New cohort members to replace existing cohort. Must have 6 members.
    /// @param _cohort      Cohort to replace.
    function replaceCohort(address[] memory _newCohort, Cohort _cohort) external;
    /// @notice Add a member to the specified cohort.
    ///         Cohorts cannot have more than 6 members, so the cohort must have less than 6 in order to call this.
    ///         New member cannot already be a member of either cohort.
    /// @dev    Initiates cross chain messages to update the individual Security Councils.
    ///         When adding a member, make sure that the key does not conflict with any contenders/nominees of ongoing elections.
    /// @param _newMember   New member to add
    /// @param _cohort      Cohort to add member to
    function addMember(address _newMember, Cohort _cohort) external;
    /// @notice Remove a member.
    /// @dev    Searches both cohorts for the member.
    ///         Initiates cross chain messages to update the individual Security Councils
    /// @param _member  Member to remove
    function removeMember(address _member) external;
    /// @notice Replace a member in a council - equivalent to removing a member, then adding another in its place.
    /// @dev    Initiates cross chain messages to update the individual Security Councils.
    ///         When replacing a member, make sure that the key does not conflict with any contenders/nominees of ongoing electoins.
    /// @param _memberToReplace Security Council member to remove
    /// @param _newMember       Security Council member to add in their place
    function replaceMember(address _memberToReplace, address _newMember) external;
    /// @notice Get the hash to be signed for an existing member rotation
    /// @param from     The address that will be rotated out. Included in the hash so that other members cant use this message to rotate their address
    /// @param nonce    The message nonce. Must be equal to the rotationNonce for the member being rotated out
    function getRotateMemberHash(address from, uint256 nonce) external view returns (bytes32);
    /// @notice Security council member can rotate out their address for a new one
    /// @dev    Initiates cross chain messages to update the individual Security Councils.
    ///         Cannot rotate to a contender in an ongoing election, as this could cause a clash that would stop the election result executing
    /// @param newMemberAddress         The new member address to be rotated to
    /// @param memberElectionGovernor   The current member election governor - must have the COHORT_REPLACER_ROLE role
    /// @param signature                A signature from the new member address over the 712 rotateMember hash
    function rotateMember(
        address newMemberAddress,
        address memberElectionGovernor,
        bytes calldata signature
    ) external;
    /// @notice Is the account a member of the first cohort
    function firstCohortIncludes(address account) external view returns (bool);
    /// @notice Is the account a member of the second cohort
    function secondCohortIncludes(address account) external view returns (bool);
    /// @notice Is the account a member of the specified cohort
    function cohortIncludes(Cohort cohort, address account) external view returns (bool);
    /// @notice All members of the first cohort
    function getFirstCohort() external view returns (address[] memory);
    /// @notice All members of the second cohort
    function getSecondCohort() external view returns (address[] memory);
    /// @notice All members of both cohorts
    function getBothCohorts() external view returns (address[] memory);
    /// @notice Length of security councils array
    function securityCouncilsLength() external view returns (uint256);
    /// @notice Size of cohort under ordinary circumstances
    function cohortSize() external view returns (uint256);
    /// @notice Add new security council to be included in security council management system.
    /// @param _securityCouncilData Security council info
    function addSecurityCouncil(SecurityCouncilData memory _securityCouncilData) external;
    /// @notice Remove security council from management system.
    /// @param _securityCouncilData   security council to be removed
    function removeSecurityCouncil(SecurityCouncilData memory _securityCouncilData)
        external
        returns (bool);
    /// @notice UpgradeExecRouteBuilder is immutable, so in lieu of upgrading it, it can be redeployed and reset here
    /// @param _router new router address
    function setUpgradeExecRouteBuilder(UpgradeExecRouteBuilder _router) external;
    /// @notice Gets the data that will be used to update each of the security councils
    /// @param nonce The nonce used to generate the timelock salts
    /// @return The new members to be added to the councils
    /// @return The address of the contract that will be called by the l2 timelock
    /// @return The data that will be called from the l2 timelock
    function getScheduleUpdateInnerData(uint256 nonce)
        external
        view
        returns (address[] memory, address, bytes memory);
    /// @notice Generate the salt used in the timelocks when scheduling an update
    /// @param _members The new members to be added
    /// @param nonce    The manager nonce to make the salt unique - current nonce can be found by calling updateNonce
    function generateSalt(address[] memory _members, uint256 nonce)
        external
        pure
        returns (bytes32);
    /// @notice Each update increments an internal nonce that keeps updates unique, current value stored here
    function updateNonce() external returns (uint256);
    /// @notice Upgrade an existing contract and add rotation params
    function postUpgradeInit(uint256 _minRotationPeriod, address minRotationPeriodSetter)
        external;
}
