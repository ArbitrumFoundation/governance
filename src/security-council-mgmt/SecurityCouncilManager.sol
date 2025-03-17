// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../ArbitrumTimelock.sol";
import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import "../L1ArbitrumTimelock.sol";
import "./SecurityCouncilMgmtUtils.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "./SecurityCouncilMemberSyncAction.sol";
import "../UpgradeExecRouteBuilder.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./Common.sol";

/// @title  The Security Council Manager
/// @notice The source of truth for an array of Security Councils that are under management.
///         Can be used to change members, and replace whole cohorts, ensuring that all managed
///         Security Councils stay in sync.
/// @dev    The cohorts in the Security Council Manager can be updated from a number of different sources.
///         Care must be taken in the timing of these updates to avoid race conditions, as well as to avoid
///         invalidating other operations.
///         An example of this could be replacing a member whilst there is an ongoing election. This contract
///         ensures that a member cannot be in both cohorts, so if a cohort is elected but just prior the security
///         council decides to replace a member in the previous cohort, then a member could end up in both cohorts.
///         Since the functions in this contract ensure that this cannot be case, one of the transactions will fail.
///         To avoid this care must be taken whilst elections are ongoing.
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
        address indexed securityCouncil,
        address indexed updateAction,
        uint256 securityCouncilsLength
    );
    event SecurityCouncilRemoved(
        address indexed securityCouncil,
        address indexed updateAction,
        uint256 securityCouncilsLength
    );
    event UpgradeExecRouteBuilderSet(address indexed UpgradeExecRouteBuilder);

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

    /// @notice Address of UpgradeExecRouteBuilder. Used to help create security council updates
    UpgradeExecRouteBuilder public router;

    /// @notice Maximum possible number of Security Councils to manage
    /// @dev    Since the councils array will be iterated this provides a safety check to make too many Sec Councils
    ///         aren't added to the array.
    uint256 public immutable MAX_SECURITY_COUNCILS = 500;

    /// @notice Nonce to ensure that scheduled updates create unique entries in the timelocks
    uint256 public updateNonce;

    /// @notice Size of cohort under ordinary circumstances
    uint256 public cohortSize;

    /// @notice Magic value used by the L1 timelock to indicate that a retryable ticket should be created
    ///         Value is defined in L1ArbitrumTimelock contract https://etherscan.io/address/0xE6841D92B0C345144506576eC13ECf5103aC7f49#readProxyContract#F5
    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;

    bytes32 public constant COHORT_REPLACER_ROLE = keccak256("COHORT_REPLACER");
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
        UpgradeExecRouteBuilder _router
    ) external initializer {
        if (_firstCohort.length != _secondCohort.length) {
            revert CohortLengthMismatch(_firstCohort, _secondCohort);
        }
        firstCohort = _firstCohort;
        secondCohort = _secondCohort;
        cohortSize = _firstCohort.length;
        _grantRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(COHORT_REPLACER_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        for (uint256 i = 0; i < _roles.memberRemovers.length; i++) {
            _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemovers[i]);
        }
        _grantRole(MEMBER_ROTATOR_ROLE, _roles.memberRotator);
        _grantRole(MEMBER_REPLACER_ROLE, _roles.memberReplacer);

        if (!Address.isContract(_l2CoreGovTimelock)) {
            revert NotAContract({account: _l2CoreGovTimelock});
        }
        l2CoreGovTimelock = _l2CoreGovTimelock;

        _setUpgradeExecRouteBuilder(_router);
        for (uint256 i = 0; i < _securityCouncils.length; i++) {
            _addSecurityCouncil(_securityCouncils[i]);
        }
    }

    /// @inheritdoc ISecurityCouncilManager
    function replaceCohort(address[] memory _newCohort, Cohort _cohort)
        external
        onlyRole(COHORT_REPLACER_ROLE)
    {
        if (_newCohort.length != cohortSize) {
            revert InvalidNewCohortLength({cohort: _newCohort, cohortSize: cohortSize});
        }

        // delete the old cohort
        _cohort == Cohort.FIRST ? delete firstCohort : delete secondCohort;

        for (uint256 i = 0; i < _newCohort.length; i++) {
            _addMemberToCohortArray(_newCohort[i], _cohort);
        }

        _scheduleUpdate();
        emit CohortReplaced(_newCohort, _cohort);
    }

    function _addMemberToCohortArray(address _newMember, Cohort _cohort) internal {
        if (_newMember == address(0)) {
            revert ZeroAddress();
        }
        address[] storage cohort = _cohort == Cohort.FIRST ? firstCohort : secondCohort;
        if (cohort.length == cohortSize) {
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
    function setUpgradeExecRouteBuilder(UpgradeExecRouteBuilder _router)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setUpgradeExecRouteBuilder(_router);
    }

    function _setUpgradeExecRouteBuilder(UpgradeExecRouteBuilder _router) internal {
        address routerAddress = address(_router);

        if (!Address.isContract(routerAddress)) {
            revert NotAContract({account: routerAddress});
        }

        router = _router;
        emit UpgradeExecRouteBuilderSet(routerAddress);
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

    /// @inheritdoc ISecurityCouncilManager
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

    /// @inheritdoc ISecurityCouncilManager
    function cohortIncludes(Cohort cohort, address account) public view returns (bool) {
        address[] memory cohortMembers = cohort == Cohort.FIRST ? firstCohort : secondCohort;
        return SecurityCouncilMgmtUtils.isInArray(account, cohortMembers);
    }

    /// @inheritdoc ISecurityCouncilManager
    function generateSalt(address[] memory _members, uint256 nonce)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_members, nonce));
    }

    /// @inheritdoc ISecurityCouncilManager
    function getScheduleUpdateInnerData(uint256 nonce)
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
                SecurityCouncilMemberSyncAction.perform.selector,
                securityCouncilData.securityCouncil,
                newMembers,
                nonce
            );
        }

        // unique salt used for replay protection in the L1 timelock
        bytes32 salt = this.generateSalt(newMembers, nonce);
        (address to, bytes memory data) = router.createActionRouteData(
            chainIds,
            actionAddresses,
            new uint256[](securityCouncils.length), // all values are always 0
            actionDatas,
            0,
            salt
        );

        return (newMembers, to, data);
    }

    /// @dev Create a union of the second and first cohort, then update all Security Councils under management with that unioned array.
    ///      Updates will need to be scheduled through timelocks and target upgrade executors
    function _scheduleUpdate() internal {
        // always update the nonce
        // this is used to ensure that proposals in the timelocks are unique
        // and calls to the upgradeExecutors are in the correct order
        updateNonce++;
        (address[] memory newMembers, address to, bytes memory data) =
            getScheduleUpdateInnerData(updateNonce);

        ArbitrumTimelock(l2CoreGovTimelock).schedule({
            target: to, // ArbSys address - this will trigger a call from L2->L1
            value: 0,
            // call to ArbSys.sendTxToL1; target the L1 timelock with the calldata previously constructed
            data: data,
            predecessor: bytes32(0),
            // must be unique as the proposal hash is used for replay protection in the L2 timelock
            // we cant be sure another proposal wont use this salt, and the same target + data
            // but in that case the proposal will do what we want it to do anyway
            // this can however block the execution of the election - so in this case the
            // Security Council would need to unblock it by setting the election to executed state
            // in the Member Election governor
            salt: this.generateSalt(newMembers, updateNonce),
            delay: ArbitrumTimelock(l2CoreGovTimelock).getMinDelay()
        });
    }
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    uint256[43] private __gap;
}
