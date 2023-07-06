// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../ArbitrumTimelock.sol";
import "../UpgradeExecutor.sol";
import "../L1ArbitrumTimelock.sol";
import "./SecurityCouncilMgmtUtils.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "./SecurityCouncilUpgradeAction.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../CoreProposalCreator.sol";
import "./SecurityCouncilUpgradeAction.sol";

/// @title  The Security Council Manager
/// @notice The source of truth for an array of Security Council that are under management
///         Can be used to change members, and replace whole cohorts, ensuring that all managed
///         Security Councils stay in sync
contract SecurityCouncilManager is
    Initializable,
    AccessControlUpgradeable,
    ISecurityCouncilManager
{
    event CohortReplaced(address[] newCohort, Cohort indexed cohort);
    event MemberAdded(address indexed newMember, Cohort indexed cohort);
    event MemberRemoved(address indexed member, Cohort indexed cohort);
    event MemberReplaced(address indexed replacedMember, address indexed newMember, Cohort cohort);
    event MemberRotated(address indexed replacedAddress, address indexed newAddress, Cohort cohort);

    // The Security Council members are separated into two cohorts, allowing a whole cohort to be replaced, as
    // specified by the Arbitrum Constitution.
    // These two cohort arrays contain the source of truth for the members of the Security Council. When a membership
    // change needs to be made, a change to these arrays is first made here locally, then pushed to each of the Security Councils
    // A member cannot be in both cohorts at the same time
    address[] internal firstCohort;
    address[] internal secondCohort;

    /// @notice Address of the l2 timelock used by core governance
    ArbitrumTimelock l2CoreGovTimelock;

    CoreProposalCreator public coreProposalCreator;
    // TODO: benchmark for reasonable number
    /// @notice Maximum possible number of Security Councils to manage
    /// @dev    Since the councils array will be iterated this provides a safety check to make too many Sec Councils
    ///         aren't added to the array.
    uint256 public immutable MAX_SECURITY_COUNCILS = 500;

    /// @notice Nonce to ensure that scheduled updates create unique entries in the timelocks
    uint256 public updateNonce;

    /// @notice Min delay for the L1 timelock
    uint256 minL1TimelockDelay;

    /// @notice Magic value used by the L1 timelock to indicate that a retryable ticket should be created
    ///         Value is defined in L1ArbitrumTimelock contract https://etherscan.io/address/0xE6841D92B0C345144506576eC13ECf5103aC7f49#readProxyContract#F5
    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;

    bytes32 public constant ELECTION_EXECUTOR_ROLE = keccak256("ELECTION_EXECUTOR");
    bytes32 public constant MEMBER_ADDER_ROLE = keccak256("MEMBER_ADDER");
    bytes32 public constant MEMBER_REPLACER_ROLE = keccak256("MEMBER_REPLACER");
    bytes32 public constant MEMBER_ROTATOR_ROLE = keccak256("MEMBER_ROTATOR");
    bytes32 public constant MEMBER_REMOVER_ROLE = keccak256("MEMBER_REMOVER");

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _firstCohort,
        address[] memory _secondCohort,
        SecurityCouncilManagerRoles memory _roles,
        ArbitrumTimelock _l2CoreGovTimelock,
        CoreProposalCreator _coreProposalCreator
    ) external initializer {
        firstCohort = _firstCohort;
        secondCohort = _secondCohort;
        coreProposalCreator = _coreProposalCreator;
        l2CoreGovTimelock = _l2CoreGovTimelock;
        // TODO: ensure first + second cohort = all signers?
        _grantRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(ELECTION_EXECUTOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        for (uint256 i = 0; i < _roles.memberRemovers.length; i++) {
            _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemovers[i]);
        }
        _grantRole(MEMBER_ROTATOR_ROLE, _roles.memberRotator);
    }

    /// @inheritdoc ISecurityCouncilManager
    function replaceCohort(address[] memory _newCohort, Cohort _cohort)
        external
        onlyRole(ELECTION_EXECUTOR_ROLE)
    {
        require(_newCohort.length == 6, "SecurityCouncilManager: invalid cohort length");
        // TODO: ensure no duplicates accross cohorts, and that there are no address(0)s. This should be enforced in nomination process.
        if (_cohort == Cohort.FIRST) {
            firstCohort = _newCohort;
        } else if (_cohort == Cohort.SECOND) {
            secondCohort = _newCohort;
        }

        _scheduleUpdate();
        emit CohortReplaced(_newCohort, _cohort);
    }

    function _addMemberToCohortArray(address _newMember, Cohort _cohort) internal {
        address[] storage cohort = _cohort == Cohort.FIRST ? firstCohort : secondCohort;
        require(cohort.length < 6, "SecurityCouncilManager: cohort is full");
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newMember, firstCohort),
            "SecurityCouncilManager: member already in march cohort"
        );
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newMember, secondCohort),
            "SecurityCouncilManager: member already in secondCohort cohort"
        );
        cohort.push(_newMember);
    }

    function _removeMemberFromCohortArray(address _member) internal returns (Cohort) {
        for (uint256 i = 0; i < 2; i++) {
            address[] storage cohort = i == 0 ? firstCohort : secondCohort;
            for (uint256 j = 0; j < cohort.length; j++) {
                if (_member == cohort[j]) {
                    cohort[j] = cohort[cohort.length - 1];
                    cohort.pop();
                    return j == 0 ? Cohort.FIRST : Cohort.SECOND;
                }
            }
        }
        revert("SecurityCouncilManager: member to remove not found");
    }

    /// @inheritdoc ISecurityCouncilManager
    function addMember(address _newMember, Cohort _cohort) external onlyRole(MEMBER_ADDER_ROLE) {
        require(
            _newMember != address(0), "SecurityCouncilManager: new member can't be zero address"
        );
        _addMemberToCohortArray(_newMember, _cohort);
        _scheduleUpdate();
        emit MemberAdded(_newMember, _cohort);
    }

    /// @inheritdoc ISecurityCouncilManager
    function removeMember(address _member) external onlyRole(MEMBER_REMOVER_ROLE) {
        require(_member != address(0), "SecurityCouncilManager: member can't be zero address");
        Cohort cohort = _removeMemberFromCohortArray(_member);
        _scheduleUpdate();
        emit MemberRemoved({member: _member, cohort: cohort});
    }

    /// @inheritdoc ISecurityCouncilManager
    function replaceMember(address _memberToReplace, address _newMember)
        external
        onlyRole(MEMBER_REPLACER_ROLE)
    {
        require(
            _memberToReplace != address(0) && _newMember != address(0),
            "SecurityCouncilManager: members can't be zero address"
        );
        Cohort cohort = _removeMemberFromCohortArray(_memberToReplace);
        _addMemberToCohortArray(_newMember, cohort);
        _scheduleUpdate();
        emit MemberReplaced({
            replacedMember: _memberToReplace,
            newMember: _newMember,
            cohort: cohort
        });
    }

    /// @notice Security council member can rotate out their address for a new one; _currentAddress and _newAddress are of the same identity.
    ///         Rotation must be initiated by the security council, and member rotating out must give explicit
    ///         consent via signature
    /// @param _currentAddress  Address to rotate out
    /// @param _newAddress      Address to rotate in
    function rotateMember(address _currentAddress, address _newAddress)
        external
        onlyRole(MEMBER_ROTATOR_ROLE)
    {
        require(
            _currentAddress != address(0) && _newAddress != address(0),
            "SecurityCouncilManager: members can't be zero address"
        );
        Cohort cohort = _removeMemberFromCohortArray(_currentAddress);
        _addMemberToCohortArray(_newAddress, cohort);
        _scheduleUpdate();
        emit MemberRotated({
            replacedAddress: _currentAddress,
            newAddress: _newAddress,
            cohort: cohort
        });
    }
    /// @inheritdoc ISecurityCouncilManager

    function getFirstCohort() external view returns (address[] memory) {
        return firstCohort;
    }

    /// @inheritdoc ISecurityCouncilManager
    function getSecondCohort() external view returns (address[] memory) {
        return secondCohort;
    }

    /// @dev Create a union of the second and first cohort, then update all Security Councils under management with that unioned array.
    ///      Councils on other chains will need to be scheduled through timelocks and target upgrade executors
    function _scheduleUpdate() internal {
        // build new security council members array
        address[] memory newMembers = new address[](firstCohort.length + secondCohort.length);
        for (uint256 i = 0; i < firstCohort.length; i++) {
            newMembers[i] = firstCohort[i];
        }
        for (uint256 i = 0; i < secondCohort.length; i++) {
            newMembers[firstCohort.length + i] = secondCohort[i];
        }

        // get all security councils to update
        CoreProposalCreator.SecurityCouncil[] memory securityCouncils =
            coreProposalCreator.allSecurityCouncils();
        uint256 len = securityCouncils.length;

        // build operation data for core proposal creator
        uint256[] memory targetChainIDs = new uint256[](len);
        address[] memory govActionContracts = new address[](len);
        bytes[] memory payloads = new bytes[](len);
        uint256[] memory values = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            targetChainIDs[i] = securityCouncils[i].chainID;
            govActionContracts[i] = securityCouncils[i].updateAction;
            payloads[i] = abi.encodeWithSelector(
                SecurityCouncilUpgradeAction.perform.selector,
                securityCouncils[i].securityCouncilAddress,
                newMembers
            );
        }

        // prepare data to submit to l2 timelock
        bytes memory data = abi.encodeWithSelector(
            CoreProposalCreator.createProposalBatch.selector,
            targetChainIDs,
            govActionContracts,
            payloads,
            values,
            bytes32(0),
            coreProposalCreator.generateSalt(),
            coreProposalCreator.defaultL1TimelockDelay()
        );

        l2CoreGovTimelock.schedule({
            target: address(coreProposalCreator),
            value: 0,
            data: data,
            predecessor: bytes32(0),
            salt: coreProposalCreator.generateSalt(),
            delay: l2CoreGovTimelock.getMinDelay()
        });
    }
}
