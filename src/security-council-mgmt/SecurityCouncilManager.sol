// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../ArbitrumTimelock.sol";
import "../UpgradeExecutor.sol";
import "../L1ArbitrumTimelock.sol";
import "./SecurityCouncilMgmtUtils.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "./SecurityCouncilUpgradeAction.sol";
import "../UpgradeExecRouterBuilder.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./Common.sol";

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
    event SecurityCouncilAdded(
        address securityCouncil, address updateAction, uint256 securityCouncilsLength
    );
    event SecurityCouncilRemoved(
        address securityCouncil, address updateAction, uint256 securityCouncilsLength
    );
    event UpgradeExecRouterBuilderSet(address upgradeExecRouterBuilder);

    // The Security Council members are separated into two cohorts, allowing a whole cohort to be replaced, as
    // specified by the Arbitrum Constitution.
    // These two cohort arrays contain the source of truth for the members of the Security Council. When a membership
    // change needs to be made, a change to these arrays is first made here locally, then pushed to each of the Security Councils
    // A member cannot be in both cohorts at the same time
    address[] internal firstCohort;
    address[] internal secondCohort;

    /// @notice Address of the l2 timelock used by core governance
    address payable public l2CoreGovTimelock;

    /// @notice The list of Security Councils under management. Any changes to the cohorts in this manager
    ///         will be pushed to each of these security councils, ensuring that they all stay in sync
    SecurityCouncilData[] public securityCouncils;

    /// @notice Address of UpgradeExecRouterBuilder. Used to help create security council updates
    UpgradeExecRouterBuilder public router;

    // TODO: benchmark for reasonable number
    /// @notice Maximum possible number of Security Councils to manage
    /// @dev    Since the councils array will be iterated this provides a safety check to make too many Sec Councils
    ///         aren't added to the array.
    uint256 public immutable MAX_SECURITY_COUNCILS = 500;

    /// @notice Nonce to ensure that scheduled updates create unique entries in the timelocks
    uint256 public updateNonce;

    uint256 public constant STANDARD_COHORT_LENGTH = 6;

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
        SecurityCouncilData[] memory _securityCouncils,
        SecurityCouncilManagerRoles memory _roles,
        address payable _l2CoreGovTimelock,
        UpgradeExecRouterBuilder _router
    ) external initializer {
        // CHRIS: TODO: ensure that the first and second cohort are disjoint
        // TODO: ensure first + second cohort = all signers?
        require(
            _firstCohort.length == _secondCohort.length,
            "SecurityCouncilManager: cohorts must be the same length"
        );
        firstCohort = _firstCohort;
        secondCohort = _secondCohort;
        _grantRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(ELECTION_EXECUTOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        for (uint256 i = 0; i < _roles.memberRemovers.length; i++) {
            _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemovers[i]);
        }
        _grantRole(MEMBER_ROTATOR_ROLE, _roles.memberRotator);
        _grantRole(MEMBER_REPLACER_ROLE, _roles.memberReplacer);

        l2CoreGovTimelock = _l2CoreGovTimelock;

        _setUpgradeExecRouterBuilder(_router);
        for (uint256 i = 0; i < _securityCouncils.length; i++) {
            _addSecurityCouncil(_securityCouncils[i]);
        }
    }

    /// @inheritdoc ISecurityCouncilManager
    function replaceCohort(address[] memory _newCohort, Cohort _cohort)
        external
        onlyRole(ELECTION_EXECUTOR_ROLE)
    {
        if (_newCohort.length != STANDARD_COHORT_LENGTH) {
            revert InvalidNewCohortLength({cohort: _newCohort});
        }
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
        if (cohort.length == STANDARD_COHORT_LENGTH) {
            revert CohortFull({cohort: _cohort});
        }
        if (firstCohortIncludes(_newMember)) {
            revert MemberInCohort({member: _newMember, cohort: Cohort.FIRST});
        }
        if (secondCohortIncludes(_newMember)) {
            revert MemberInCohort({member: _newMember, cohort: Cohort.SECOND});
        }

        cohort.push(_newMember);
    }

    function _removeMemberFromCohortArray(address _member) internal returns (Cohort) {
        for (uint256 i = 0; i < 2; i++) {
            address[] storage cohort = i == 0 ? firstCohort : secondCohort;
            for (uint256 j = 0; j < cohort.length; j++) {
                if (_member == cohort[j]) {
                    cohort[j] = cohort[cohort.length - 1];
                    cohort.pop();
                    return i == 0 ? Cohort.FIRST : Cohort.SECOND;
                }
            }
        }
        revert NotAMember({member: _member});
    }

    /// @inheritdoc ISecurityCouncilManager
    function addMember(address _newMember, Cohort _cohort) external onlyRole(MEMBER_ADDER_ROLE) {
        if (_newMember == address(0)) {
            revert ZeroAddress();
        }
        _addMemberToCohortArray(_newMember, _cohort);
        _scheduleUpdate();
        emit MemberAdded(_newMember, _cohort);
    }

    /// @inheritdoc ISecurityCouncilManager
    function removeMember(address _member) external onlyRole(MEMBER_REMOVER_ROLE) {
        if (_member == address(0)) {
            revert ZeroAddress();
        }
        Cohort cohort = _removeMemberFromCohortArray(_member);
        _scheduleUpdate();
        emit MemberRemoved({member: _member, cohort: cohort});
    }

    /// @inheritdoc ISecurityCouncilManager
    function replaceMember(address _memberToReplace, address _newMember)
        external
        onlyRole(MEMBER_REPLACER_ROLE)
    {
        Cohort cohort = _swapMembers(_memberToReplace, _newMember);
        emit MemberReplaced({
            replacedMember: _memberToReplace,
            newMember: _newMember,
            cohort: cohort
        });
    }

    /// @inheritdoc ISecurityCouncilManager
    function rotateMember(address _currentAddress, address _newAddress)
        external
        onlyRole(MEMBER_ROTATOR_ROLE)
    {
        Cohort cohort = _swapMembers(_currentAddress, _newAddress);
        emit MemberRotated({
            replacedAddress: _currentAddress,
            newAddress: _newAddress,
            cohort: cohort
        });
    }

    function _swapMembers(address _addressToRemove, address _addressToAdd)
        internal
        returns (Cohort)
    {
        if (_addressToRemove == address(0) || _addressToAdd == address(0)) {
            revert ZeroAddress();
        }
        Cohort cohort = _removeMemberFromCohortArray(_addressToRemove);
        _addMemberToCohortArray(_addressToAdd, cohort);
        _scheduleUpdate();
        return cohort;
    }

    function _addSecurityCouncil(SecurityCouncilData memory _securityCouncilData) internal {
        if (securityCouncils.length == MAX_SECURITY_COUNCILS) {
            revert MaxSecurityCouncils(securityCouncils.length);
        }

        if (
            _securityCouncilData.updateAction == address(0)
                || _securityCouncilData.securityCouncil == address(0)
        ) {
            revert ZeroAddress();
        }

        if (_securityCouncilData.chainId == 0) {
            revert SecurityCouncilZeroChainID(_securityCouncilData);
        }

        if (!router.upExecLocationExists(_securityCouncilData.chainId)) {
            revert SecurityCouncilNotInRouter(_securityCouncilData);
        }

        for (uint256 i = 0; i < securityCouncils.length; i++) {
            SecurityCouncilData storage existantSecurityCouncil = securityCouncils[i];

            if (
                existantSecurityCouncil.chainId == _securityCouncilData.chainId
                    && existantSecurityCouncil.securityCouncil == _securityCouncilData.securityCouncil
            ) {
                revert SecurityCouncilAlreadyInRouter(_securityCouncilData);
            }
        }

        securityCouncils.push(_securityCouncilData);
        emit SecurityCouncilAdded(
            _securityCouncilData.securityCouncil,
            _securityCouncilData.updateAction,
            securityCouncils.length
        );
    }

    /// @inheritdoc ISecurityCouncilManager
    function addSecurityCouncil(SecurityCouncilData memory _securityCouncilData)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addSecurityCouncil(_securityCouncilData);
    }

    /// @inheritdoc ISecurityCouncilManager
    function removeSecurityCouncil(SecurityCouncilData memory _securityCouncilData)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        for (uint256 i = 0; i < securityCouncils.length; i++) {
            SecurityCouncilData storage securityCouncilData = securityCouncils[i];
            if (
                securityCouncilData.securityCouncil == _securityCouncilData.securityCouncil
                    && securityCouncilData.chainId == _securityCouncilData.chainId
                    && securityCouncilData.updateAction == _securityCouncilData.updateAction
            ) {
                SecurityCouncilData storage lastSecurityCouncil =
                    securityCouncils[securityCouncils.length - 1];

                securityCouncils[i] = lastSecurityCouncil;
                securityCouncils.pop();
                emit SecurityCouncilRemoved(
                    securityCouncilData.securityCouncil,
                    securityCouncilData.updateAction,
                    securityCouncils.length
                );
                return true;
            }
        }
        revert SecurityCouncilNotInManager(_securityCouncilData);
    }

    /// @inheritdoc ISecurityCouncilManager
    function setUpgradeExecRouterBuilder(UpgradeExecRouterBuilder _router)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setUpgradeExecRouterBuilder(_router);
    }

    function _setUpgradeExecRouterBuilder(UpgradeExecRouterBuilder _router) internal {
        address routerAddress = address(_router);

        if (!Address.isContract(routerAddress)) {
            revert NotAContract({account: routerAddress});
        }

        router = _router;
        emit UpgradeExecRouterBuilderSet(routerAddress);
    }

    /// @inheritdoc ISecurityCouncilManager
    function getFirstCohort() external view returns (address[] memory) {
        return firstCohort;
    }

    /// @inheritdoc ISecurityCouncilManager
    function getSecondCohort() external view returns (address[] memory) {
        return secondCohort;
    }

    /// @inheritdoc ISecurityCouncilManager
    function getBothCohorts() public view returns (address[] memory) {
        address[] memory members = new address[](firstCohort.length + secondCohort.length);
        for (uint256 i = 0; i < firstCohort.length; i++) {
            members[i] = firstCohort[i];
        }
        for (uint256 i = 0; i < secondCohort.length; i++) {
            members[firstCohort.length + i] = secondCohort[i];
        }
        return members;
    }

    function securityCouncilsLength() public view returns (uint256) {
        return securityCouncils.length;
    }

    /// @inheritdoc ISecurityCouncilManager
    function firstCohortIncludes(address account) public view returns (bool) {
        return cohortIncludes(Cohort.FIRST, account);
    }

    /// @inheritdoc ISecurityCouncilManager
    function secondCohortIncludes(address account) public view returns (bool) {
        return cohortIncludes(Cohort.SECOND, account);
    }

    function cohortIncludes(Cohort cohort, address account) public view returns (bool) {
        address[] memory cohortMembers = cohort == Cohort.FIRST ? firstCohort : secondCohort;
        return SecurityCouncilMgmtUtils.isInArray(account, cohortMembers);
    }

    /// @notice Generate unique salt for timelock scheduling
    /// @param _members Data to input / hash
    function generateSalt(address[] memory _members) external view returns (bytes32) {
        // CHRIS: TODO: make this func pure by providing the update nonce
        return keccak256(abi.encodePacked(_members, updateNonce));
    }

    // CHRIS: TODO: docs
    function getScheduleUpdateData()
        public
        view
        returns (address[] memory, address, bytes memory)
    {
        // build a union array of security council members
        address[] memory newMembers = getBothCohorts();

        // build batch call to L1 timelock
        address[] memory actionAddresses = new address[](securityCouncils.length);
        bytes[] memory actionDatas = new bytes[](securityCouncils.length);
        uint256[] memory chainIds = new uint256[](securityCouncils.length);

        for (uint256 i = 0; i < securityCouncils.length; i++) {
            SecurityCouncilData memory securityCouncilData = securityCouncils[i];

            actionAddresses[i] = securityCouncilData.updateAction;
            chainIds[i] = securityCouncilData.chainId;
            actionDatas[i] = abi.encodeWithSelector(
                SecurityCouncilUpgradeAction.perform.selector,
                securityCouncilData.securityCouncil,
                newMembers
            );
        }

        (address to, bytes memory data) = router.createActionRouteData(
            chainIds,
            actionAddresses,
            new uint256[](securityCouncils.length), // all values are always 0
            actionDatas,
            this.generateSalt(newMembers) // must be unique as the proposal hash is used for replay protection in the L1 timelock
        );
        return (newMembers, to, data);
    }

    /// @dev Create a union of the second and first cohort, then update all Security Councils under management with that unioned array.
    ///      Councils on other chains will need to be scheduled through timelocks and target upgrade executors
    function _scheduleUpdate() internal {
        // always update the nonce - this is used to ensure that proposals in the timelocks are unique
        updateNonce++;
        // TODO: enforce ordering (on the L1 side) with a nonce? is no contract level ordering guarunee for updates ok?
        (address[] memory newMembers, address to, bytes memory data) = this.getScheduleUpdateData();

        ArbitrumTimelock(l2CoreGovTimelock).schedule({
            target: to, // ArbSys address - this will trigger a call from L2->L1
            value: 0,
            // call to ArbSys.sendTxToL1; target the L1 timelock with the calldata previously constucted
            data: data,
            predecessor: bytes32(0),
            salt: this.generateSalt(newMembers), // must be unique as the proposal hash is used for replay protection in the L2 timelock
            delay: ArbitrumTimelock(l2CoreGovTimelock).getMinDelay()
        });
    }
}
