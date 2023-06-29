// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./SecurityCouncilMgmtUtils.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../ArbitrumTimelock.sol";
import "../UpgradeExecutor.sol";
import "../L1ArbitrumTimelock.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "./SecurityCouncilUpgradeAction.sol";

contract SecurityCouncilManager is
    Initializable,
    AccessControlUpgradeable,
    ISecurityCouncilManager
{
    using ECDSA for bytes32;

    // cohort arrays are source-of-truth for security council; the maximum 12 owners security council owners should always be equal to the
    // sum of these two arrays (or have pending x-chain messages on their way to updating them)
    address[] public firstCohort;
    address[] public secondCohort;

    // address of l1 timelock used for core govervor proposals
    address public l1CoreGovTimelock;
    // address of l2 timelock used for core govervor proposals
    address payable public l2CoreGovTimelock;

    // security councils to manage; can span multiple chains
    SecurityCouncilData[] public securityCouncils;

    bytes32 public constant ELECTION_EXECUTOR_ROLE = keccak256("ELECTION_EXECUTOR");
    bytes32 public constant MEMBER_ADDER_ROLE = keccak256("MEMBER_ADDER");
    bytes32 public constant MEMBER_ROTATOR_ROLE = keccak256("MEMBER_ROTATOR");
    bytes32 public constant MEMBER_REMOVER_ROLE = keccak256("MEMBER_REMOVER");

    event ElectionResultHandled(address[] newCohort, Cohort indexed cohort);
    event MemberAdded(address indexed newMember, Cohort indexed cohort);
    event MemberRemoved(address indexed member, Cohort indexed cohort);
    event SecurityCouncilAdded(
        address securityCouncil,
        address indexed upgradeExecutor,
        address updateAction,
        address indexed inbox
    );

    event SecurityCouncilRemoved(
        address securityCouncil,
        address indexed upgradeExecutor,
        address updateAction,
        address indexed inbox
    );
    event L1TimelockDelaySet(uint256 minL1TimelockDelay);

    uint256 public updateNonce = 0;

    // this should be kept in sync with the timelock delay on the core gov L1ArbitrumTimelock
    uint256 minL1TimelockDelay;

    // Used as a magic value to indicate that a retryable ticket should be created by the L1 timelock
    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _firstCohort,
        address[] memory _secondCohort,
        SecurityCouncilData[] memory _securityCouncils,
        Roles memory _roles,
        address _l1CoreGovTimelock,
        address _l2CoreGovTimelock,
        uint256 _minL1TimelockDelay
    ) external initializer {
        firstCohort = _firstCohort;
        secondCohort = _secondCohort;
        // TODO: ensure first + second cohort = all signers?
        _grantRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(ELECTION_EXECUTOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        for (uint256 i = 0; i < _roles.memberRemovers.length; i++) {
            _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemovers[i]);
        }
        _grantRole(MEMBER_ROTATOR_ROLE, _roles.memberRotator);

        l1CoreGovTimelock = _l1CoreGovTimelock;
        l2CoreGovTimelock = payable(_l2CoreGovTimelock);

        _setMinL1TimelockDelay(_minL1TimelockDelay);

        for (uint256 i = 0; i < _securityCouncils.length; i++) {
            _addSecurityCouncil(_securityCouncils[i]);
        }
    }

    /// @notice callable only by Election Governer. Updates cohort in this contract's state and triggers update.
    /// @param _newCohort new cohort to replace existing cohort. New cohort is result of election, so should always have 6 members.
    /// @param _cohort cohort to replace.
    function executeElectionResult(address[] memory _newCohort, Cohort _cohort)
        external
        onlyRole(ELECTION_EXECUTOR_ROLE)
    {
        require(_newCohort.length == 6, "SecurityCouncilManager: invalid cohort length");
        // TODO: ensure no duplicates accross cohorts; this should be enforced in nomination process. If there are duplicates, this call will revert in the Gnosis safe contract
        if (_cohort == Cohort.FIRST) {
            firstCohort = _newCohort;
        } else if (_cohort == Cohort.SECOND) {
            secondCohort = _newCohort;
        }

        _scheduleUpdate();
        emit ElectionResultHandled(_newCohort, _cohort);
    }

    /// @notice callable only by 9 of 12 SC. Adds member in this contract's state and triggers update.
    /// new member cannot already be member of either of either cohort
    /// @param _newMember member to add
    /// @param _cohort cohort to add member to
    function addMemberToCohort(address _newMember, Cohort _cohort)
        external
        onlyRole(MEMBER_ADDER_ROLE)
    {
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

        _scheduleUpdate();
        emit MemberAdded(_newMember, _cohort);
    }

    /// @notice callable only by SC Removal Governor.
    /// Don't need to specify cohort since duplicate members aren't allowed (so always unambiguous)
    /// @param _member member to remove
    function removeMember(address _member) external onlyRole(MEMBER_REMOVER_ROLE) returns (bool) {
        if (_removeMemberFromCohort(_member, firstCohort)) {
            emit MemberRemoved(_member, Cohort.FIRST);
            return true;
        }
        if (_removeMemberFromCohort(_member, secondCohort)) {
            emit MemberRemoved(_member, Cohort.SECOND);
            return true;
        }

        revert("SecurityCouncilManager: member not found");
    }

    /// @notice Removes member in this contract's state and triggers update
    /// @param _member member to remove
    /// @param _cohort cohort to remove member from
    function _removeMemberFromCohort(address _member, address[] storage _cohort)
        internal
        returns (bool)
    {
        for (uint256 i = 0; i < _cohort.length; i++) {
            if (_member == _cohort[i]) {
                _cohort[i] = _cohort[_cohort.length - 1];
                _cohort.pop();
                _scheduleUpdate();
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
            !SecurityCouncilMgmtUtils.isInArray(_newAddress, firstCohort)
                && !SecurityCouncilMgmtUtils.isInArray(_newAddress, secondCohort),
            "SecurityCouncilManager: new member already included"
        );
        address[] storage cohort;
        if (SecurityCouncilMgmtUtils.isInArray(_currentAddress, firstCohort)) {
            cohort = firstCohort;
        } else if (SecurityCouncilMgmtUtils.isInArray(_currentAddress, secondCohort)) {
            cohort = secondCohort;
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
                _scheduleUpdate();
            }
        }
    }

    /// @notice Get data to sign for a key rotation. Uses an incremented nonce
    /// @param _currentAddress Address to rotate out
    /// @param _newAddress Address to rotate in
    function getRotateDataToSign(address _currentAddress, address _newAddress)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_currentAddress, _newAddress, updateNonce));
    }

    /// @notice Add new security council to be included in security council management system. Only DAO can call.
    /// @param _securityCouncilData data for security council to be added
    function addSecurityCouncil(SecurityCouncilData memory _securityCouncilData)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addSecurityCouncil(_securityCouncilData);
    }

    /// @notice Remove security council from management system. Only DAO can call.
    /// @param _index index in securityCouncils of data to be remoed
    function removeSecurityCouncil(uint256 _index) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SecurityCouncilData storage securityCouncilToRemove = securityCouncils[_index];
        SecurityCouncilData storage lastSecurityCouncil =
            securityCouncils[securityCouncils.length - 1];

        securityCouncils[_index] = lastSecurityCouncil;
        securityCouncils.pop();
        emit SecurityCouncilRemoved(
            securityCouncilToRemove.securityCouncil,
            securityCouncilToRemove.upgradeExecutor,
            securityCouncilToRemove.updateAction,
            securityCouncilToRemove.inbox
        );
    }

    function _addSecurityCouncil(SecurityCouncilData memory _securityCouncilData) internal {
        require(
            _securityCouncilData.updateAction != address(0),
            "SecurityCouncilManager: zero updateAction"
        );
        require(
            _securityCouncilData.upgradeExecutor != address(0),
            "SecurityCouncilManager: zero upgradeExecutor"
        );

        require(
            _securityCouncilData.securityCouncil != address(0),
            "SecurityCouncilManager: zero securityCouncil"
        );
        securityCouncils.push(_securityCouncilData);
        emit SecurityCouncilAdded(
            _securityCouncilData.securityCouncil,
            _securityCouncilData.upgradeExecutor,
            _securityCouncilData.updateAction,
            _securityCouncilData.inbox
        );
    }
    /// @notice Set delay for messages to the L1 timelock. This should only be used to keep the minTimelockDelay value in sync with L1 (i.e., if the L1 side is updated, this should be too)
    /// @param _minL1TimelockDelay new  L1 timelock delay value

    function setMinL1TimelockDelay(uint256 _minL1TimelockDelay)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setMinL1TimelockDelay(_minL1TimelockDelay);
    }

    function _setMinL1TimelockDelay(uint256 _minL1TimelockDelay) internal {
        minL1TimelockDelay = _minL1TimelockDelay;
        emit L1TimelockDelaySet(_minL1TimelockDelay);
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

    function getFirstCohort() external view returns (address[] memory) {
        return firstCohort;
    }

    function getSecondCohort() external view returns (address[] memory) {
        return secondCohort;
    }

    /// @notice generate unique salt for timelock scheduling
    /// @param _members data to input / hash
    function generateSalt(address[] memory _members) external view returns (bytes32) {
        return keccak256(abi.encodePacked(_members, updateNonce));
    }

    /// @notice build new security council members array from first and second cohort and schedule a sequence of cross chain messages to update all security councils accordingly.
    function _scheduleUpdate() internal {
        // build array of security council members
        address[] memory newMembers = new address[](secondCohort.length + firstCohort.length);
        for (uint256 i = 0; i < firstCohort.length; i++) {
            newMembers[i] = firstCohort[i];
        }
        for (uint256 i = 0; i < secondCohort.length; i++) {
            newMembers[firstCohort.length + i] = secondCohort[i];
        }

        // build batch call to L1 timellck
        uint256[] memory valuesForL1TimelockOpertaions = new uint256[](securityCouncils.length);
        address[] memory targetsForL1TimelockOperations = new address[](securityCouncils.length);
        bytes[] memory payloadsForL1TimelockOperations = new bytes[](securityCouncils.length);
        for (uint256 i = 0; i < securityCouncils.length; i++) {
            // values are all always 0
            valuesForL1TimelockOpertaions[i] = 0;

            SecurityCouncilData memory securityCouncilData = securityCouncils[i];

            // call for upgrade executor; call "execute" to the target action contract.
            bytes memory upgradeExecutorCallData = abi.encodeWithSelector(
                UpgradeExecutor.execute.selector,
                securityCouncilData.updateAction,
                abi.encodeWithSelector(
                    SecurityCouncilUpgradeAction.updateMembers.selector, newMembers
                ) // data for upgrade executor's delegatecall to action contract
            );
            // inbox(0) check is check for the security council being on l1.
            // if it is, the L1timelock should call the upgrade executor directly
            if (securityCouncilData.inbox == address(0)) {
                // upgrade executor address/calldata is sent to the L1timelock top level for L1 execution (see L1ArbitrumTimelock.execute)
                targetsForL1TimelockOperations[i] = securityCouncilData.upgradeExecutor;
                payloadsForL1TimelockOperations[i] = upgradeExecutorCallData;
            } else {
                // If the security council is on L1, this is signalled with target RETRYABLE_TICKET_MAGIC and the call to the upgrade executor is encoded in the payload (see L1ArbitrumTimelock.execute for expected encoding)
                targetsForL1TimelockOperations[i] = RETRYABLE_TICKET_MAGIC;
                payloadsForL1TimelockOperations[i] = abi.encode(
                    securityCouncilData.inbox,
                    securityCouncilData.upgradeExecutor,
                    0,
                    0,
                    0,
                    upgradeExecutorCallData
                );
            }
            // finally, we build the call data to schedule a batch of operations to the L1Timelock
            bytes memory l1TimelockCallData = abi.encodeWithSelector(
                L1ArbitrumTimelock.scheduleBatch.selector,
                targetsForL1TimelockOperations,
                valuesForL1TimelockOpertaions,
                payloadsForL1TimelockOperations,
                bytes32(0),
                this.generateSalt(newMembers),
                minL1TimelockDelay // use the minL1TimelockDelay, which always match the minimum delay value set on the L1 Timelock
            );
            // schedule a call to the L2 timelock to execute an l2 to l1 message via ArbSys precompile
            ArbitrumTimelock(l2CoreGovTimelock).schedule({
                target: address(100), // ArbSys address
                value: 0,
                data: abi.encodeWithSelector(
                    ArbSys.sendTxToL1.selector, l1CoreGovTimelock, l1TimelockCallData
                    ), // call to ArbSys; target the L1 timelock with the calldata previously constucted
                predecessor: bytes32(0),
                salt: this.generateSalt(newMembers),
                delay: ArbitrumTimelock(l2CoreGovTimelock).getMinDelay()
            });

            updateNonce++;
        }
    }
}
