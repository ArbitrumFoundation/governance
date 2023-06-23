// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "./interfaces/IL1SecurityCouncilUpdateRouter.sol";
import "./SecurityCouncilMgmtUtils.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISecurityCouncilManager.sol";

/// @notice Manages the security council updates.
///         Receives election results (replace cohort with 6 new members), add-member actions, and remove-member actions,
///         and dispatches them to all security councils on all relevant chains
contract SecurityCouncilManager is
    Initializable,
    AccessControlUpgradeable,
    ISecurityCouncilManager
{
    using ECDSA for bytes32;

    // cohort arrays are source-of-truth for security council; the maximum 12 owners security council owners should always be equal to the
    // sum of these two arrays (or have pending x-chain messages on their way to updating them)
    address[] public marchCohort;
    address[] public septemberCohort;

    bytes32 public constant ELECTION_EXECUTOR_ROLE = keccak256("ELECTION_EXECUTOR");
    bytes32 public constant MEMBER_ADDER_ROLE = keccak256("MEMBER_ADDER");
    bytes32 public constant MEMBER_ROTATOR_ROLE = keccak256("MEMBER_ROTATOR");
    bytes32 public constant MEMBER_REMOVER_ROLE = keccak256("MEMBER_REMOVER");

    address public l1SecurityCouncilUpdateRouter;

    event L1SecurityCouncilUpdateRouterSet(address indexed l1SecurityCouncilUpdateRouter);
    event ElectionResultHandled(address[] newCohort, Cohort indexed cohort);
    event MemberAdded(address indexed newMember, Cohort indexed cohort);
    event MemberRemoved(address indexed member, Cohort indexed cohort);

    uint256 public rotationNonce = 0;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _marchCohort,
        address[] memory _septemberCohort,
        Roles memory _roles,
        address _l1SecurityCouncilUpdateRouter
    ) external initializer {
        marchCohort = _marchCohort;
        septemberCohort = _septemberCohort;
        // TODO: ensure march + september cohort = all signers?
        _grantRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(ELECTION_EXECUTOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        for (uint256 i = 0; i < _roles.memberRemovers.length; i++) {
            _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemovers[i]);
        }
        _grantRole(MEMBER_ROTATOR_ROLE, _roles.memberRotator);

        _setL1SecurityCouncilUpdateRouter(_l1SecurityCouncilUpdateRouter);
    }

    /// @notice callable only by Election Governer. Updates cohort in this contract's state and triggers dispatch.
    /// @param _newCohort new cohort to replace existing cohort. New cohort is result of election, so should always have 6 members.
    /// @param _cohort cohort to replace.
    function executeElectionResult(address[] memory _newCohort, Cohort _cohort)
        external
        onlyRole(ELECTION_EXECUTOR_ROLE)
    {
        require(_newCohort.length == 6, "SecurityCouncilManager: invalid cohort length");
        // TODO: ensure no duplicates accross cohorts; this should be enforced in nomination process. If there are duplicates, this call will revert in the Gnosis safe contract
        address[] memory previousMembersCopy;
        if (_cohort == Cohort.MARCH) {
            previousMembersCopy = SecurityCouncilMgmtUtils.copyAddressArray(marchCohort);
            marchCohort = _newCohort;
        } else if (_cohort == Cohort.SEPTEMBER) {
            previousMembersCopy = SecurityCouncilMgmtUtils.copyAddressArray(septemberCohort);
            septemberCohort = _newCohort;
        }

        _dispatchUpdateMembers(_newCohort, previousMembersCopy);
        emit ElectionResultHandled(_newCohort, _cohort);
    }

    /// @notice callable only by 9 of 12 SC. Adds member in this contract's state and triggers dispatch.
    /// new member cannot already be member of either of either cohort
    /// @param _newMember member to add
    /// @param _cohort cohort to add member to
    function addMemberToCohort(address _newMember, Cohort _cohort)
        external
        onlyRole(MEMBER_ADDER_ROLE)
    {
        address[] storage cohort = _cohort == Cohort.MARCH ? marchCohort : septemberCohort;
        require(cohort.length < 6, "SecurityCouncilManager: cohort is full");
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newMember, marchCohort),
            "SecurityCouncilManager: member already in march cohort"
        );
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newMember, septemberCohort),
            "SecurityCouncilManager: member already in septemberCohort cohort"
        );

        cohort.push(_newMember);

        address[] memory membersToAdd;
        membersToAdd[0] = (_newMember);

        address[] memory membersToRemove;
        _dispatchUpdateMembers(membersToAdd, membersToRemove);
        emit MemberAdded(_newMember, _cohort);
    }

    /// @notice callable only by SC Removal Governor.
    /// Don't need to specify cohort since duplicate members aren't allowed (so always unambiguous)
    /// @param _member member to remove
    function removeMember(address _member) external onlyRole(MEMBER_REMOVER_ROLE) returns (bool) {
        if (_removeMemberFromCohort(_member, marchCohort)) {
            emit MemberRemoved(_member, Cohort.MARCH);
            return true;
        }
        if (_removeMemberFromCohort(_member, septemberCohort)) {
            emit MemberRemoved(_member, Cohort.SEPTEMBER);
            return true;
        }

        revert("SecurityCouncilManager: member not found");
    }

    /// @notice Removes member in this contract's state and triggers dispatch
    /// @param _member member to remove
    /// @param _cohort cohort to remove member from
    function _removeMemberFromCohort(address _member, address[] storage _cohort)
        internal
        returns (bool)
    {
        for (uint256 i = 0; i < _cohort.length; i++) {
            if (_member == _cohort[i]) {
                delete _cohort[i];
                address[] memory membersToAdd;
                address[] memory membersToRemove;
                membersToRemove[0] = _member;
                _dispatchUpdateMembers(membersToAdd, membersToRemove);
                return true;
            }
        }
        return false;
    }

    /// @notice Security council member can rotate out their address for a new one.
    /// Rotation must be initiated by the security council, and member rotating out must give explicit
    /// consent via signature
    /// @param _currentAddress Address to rotate out
    /// @param _newAddress Address to rotate in
    /// @param _signature Signature from _currentAddress
    function rotateMember(address _currentAddress, address _newAddress, bytes memory _signature)
        external
        onlyRole(MEMBER_ROTATOR_ROLE)
    {
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newAddress, marchCohort)
                && !SecurityCouncilMgmtUtils.isInArray(_newAddress, septemberCohort),
            "SecurityCouncilManager: new member already included"
        );
        address[] storage cohort;
        if (SecurityCouncilMgmtUtils.isInArray(_currentAddress, marchCohort)) {
            cohort = marchCohort;
        } else if (SecurityCouncilMgmtUtils.isInArray(_currentAddress, septemberCohort)) {
            cohort = septemberCohort;
        } else {
            revert("SecurityCouncilManager: current address not in either cohort");
        }

        // TODO: double check that this makes sense
        bytes32 data = getRotateDataToSign(_currentAddress, _newAddress);
        require(
            _verify(data, _signature, _currentAddress), "SecurityCouncilManager: invalid signature"
        );
        for (uint256 i = 0; i < cohort.length; i++) {
            if (cohort[i] == _currentAddress) {
                cohort[i] = _newAddress;

                address[] memory membersToAdd;
                address[] memory membersToRemove;
                membersToAdd[0] = _newAddress;
                membersToRemove[0] = _currentAddress;
                _dispatchUpdateMembers(membersToAdd, membersToRemove);
            }
        }
        rotationNonce += 1;
    }

    /// @notice Get data to sign for a key rotation. Uses an incremented nonce
    /// @param _currentAddress Address to rotate out
    /// @param _newAddress Address to rotate in
    function getRotateDataToSign(address _currentAddress, address _newAddress)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_currentAddress, _newAddress, rotationNonce));
    }

    /// @notice Verify signature over data
    /// @param data Signed data
    /// @param signature over data
    /// @param account signer
    /// @return true if signature is valid and from account
    function _verify(bytes32 data, bytes memory signature, address account)
        public
        pure
        returns (bool)
    {
        return data.toEthSignedMessageHash().recover(signature) == account;
    }

    /// @notice initates update to all Security Council Multisigs (gov chain, L1, and all others governed L2 chains).
    /// Handles election results (add 6, remove 6 or fewer), add member (add one, remove none), and remove member (add none, remove one)
    /// @param _membersToAdd array of members to add. can be empty.
    /// @param _membersToRemove array of members to remove. can be empty.
    function _dispatchUpdateMembers(
        address[] memory _membersToAdd,
        address[] memory _membersToRemove
    ) internal {
        // A candidate new be relected, which case they appear in both the arrays; removing and re-added is a no-op. We instead remove them from both arrays; this simplifies the logic of updating them in the gnosis safes.
        (address[] memory newMembers, address[] memory oldMembers) =
            SecurityCouncilMgmtUtils.removeSharedAddresses(_membersToAdd, _membersToRemove);
        // Initiate L2 to L1 message to handle updating remaining secuirity councils
        bytes memory data = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.scheduleUpdateMembers.selector,
            abi.encode(_membersToAdd, _membersToRemove)
        );
        ArbSys(0x0000000000000000000000000000000000000064).sendTxToL1(
            l1SecurityCouncilUpdateRouter, data
        );
    }

    /// @notice admin can update the l1SecurityCouncilUpdateRouter address
    /// @param _l1SecurityCouncilUpdateRouter  new  l1SecurityCouncilUpdateRouter addresses
    function setL1SecurityCouncilUpdateRouter(address _l1SecurityCouncilUpdateRouter)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setL1SecurityCouncilUpdateRouter(_l1SecurityCouncilUpdateRouter);
    }

    /// @param _l1SecurityCouncilUpdateRouter new  l1SecurityCouncilUpdateRouter addresses
    function _setL1SecurityCouncilUpdateRouter(address _l1SecurityCouncilUpdateRouter) internal {
        require(
            _l1SecurityCouncilUpdateRouter != address(0),
            "SecurityCouncilManager: invalid l1SecurityCouncilUpdateRouter"
        );
        l1SecurityCouncilUpdateRouter = _l1SecurityCouncilUpdateRouter;
        emit L1SecurityCouncilUpdateRouterSet(l1SecurityCouncilUpdateRouter);
    }

    function getMarchCohort() external view returns (address[] memory) {
        return marchCohort;
    }

    function getSeptemberCohort() external view returns (address[] memory) {
        return septemberCohort;
    }
}
