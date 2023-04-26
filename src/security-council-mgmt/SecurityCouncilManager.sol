// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "./interfaces/IL1SecurityCouncilUpdateRouter.sol";
import "./SecurityCouncilMgmtUtils.sol";

contract SecurityCouncilManager is Initializable, AccessControlUpgradeable {
    address[] public marchCohort;
    address[] public septemberCohort;

    bytes32 public constant COHORT_UPDATOR_ROLE = keccak256("COHORT_UPDATOR");
    bytes32 public constant MEMBER_ADDER_ROLE = keccak256("MEMBER_ADDER");
    bytes32 public constant MEMBER_REMOVER_ROLE = keccak256("MEMBER_REMOVER");

    struct Roles {
        address admin;
        address cohortUpdator;
        address memberAdder;
        address memberRemover;
    }

    struct TargetContracts {
        address govChainEmergencySecurityCouncilUpgradeExecutor;
        address govChainNonEmergencySecurityCouncilUpgradeExecutor;
        address l1SecurityCouncilUpdateRouter;
    }

    TargetContracts targetContracts;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _marchCohort,
        address[] memory _septemberCohort,
        Roles memory _roles,
        TargetContracts memory _targetContracts
    ) external initializer {
        marchCohort = _marchCohort;
        septemberCohort = _septemberCohort;
        // TODO verify that marchcohort.concat(septemberCohort) == current SecurityCouncil
        _setupRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(COHORT_UPDATOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemover);
        // TODO require non zero, require code? setter
        targetContracts = _targetContracts;
    }

    function upgdateMarchCohort(address[] memory _newMarchCohort)
        external
        onlyRole(COHORT_UPDATOR_ROLE)
    {
        require(_newMarchCohort.length == 6, "SecurityCouncilManager: invalid march cohort length");
        address[] memory previousMembersCopy =
            SecurityCouncilMgmtUtils.copyAddressArray(_newMarchCohort);
        marchCohort = _newMarchCohort;
        _dispatchUpdateCohort(_newMarchCohort, previousMembersCopy);
    }

    function upgdateSeptemberCohort(address[] memory _newSeptemberCohort)
        external
        onlyRole(COHORT_UPDATOR_ROLE)
    {
        require(
            _newSeptemberCohort.length == 6,
            "SecurityCouncilManager: invalid september cohort length"
        );
        address[] memory previousMembersCopy =
            SecurityCouncilMgmtUtils.copyAddressArray(_newSeptemberCohort);
        septemberCohort = _newSeptemberCohort;
        _dispatchUpdateCohort(_newSeptemberCohort, previousMembersCopy);
    }

    function _dispatchUpdateCohort(address[] memory _newMembers, address[] memory _oldMembers)
        internal
    {
        (address[] memory newMembers, address[] memory oldMembers) =
            SecurityCouncilMgmtUtils.removeSharedAddresses(_newMembers, _oldMembers);
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainEmergencySecurityCouncilUpgradeExecutor
        ).updateMembers(newMembers, oldMembers);
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainNonEmergencySecurityCouncilUpgradeExecutor
        ).updateMembers(newMembers, oldMembers);

        bytes memory data = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.handleUpdateCohort.selector, newMembers, oldMembers
        );
        _sendToL1Router(data);
    }

    function addMemberToMarchCohort(address _newMember) external onlyRole(MEMBER_ADDER_ROLE) {
        _addMemberToCohort(_newMember, marchCohort);
    }

    function addMemberToSeptemberCohort(address _newMember) external onlyRole(MEMBER_ADDER_ROLE) {
        _addMemberToCohort(_newMember, septemberCohort);
    }

    function _addMemberToCohort(address _newMember, address[] storage _cohort) internal {
        require(_cohort.length < 6, "SecurityCouncilManager: cohort is full");
        _cohort.push(_newMember);
        _dispatchAddMember(_newMember);
    }

    function _dispatchAddMember(address _newMember) internal {
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainEmergencySecurityCouncilUpgradeExecutor
        ).addMember(_newMember);
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainNonEmergencySecurityCouncilUpgradeExecutor
        ).addMember(_newMember);

        bytes memory data = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.handleAddMember.selector, _newMember
        );
        _sendToL1Router(data);
    }

    function removeMember(address _prevMemberInLinkedList, address _member)
        external
        onlyRole(MEMBER_REMOVER_ROLE)
        returns (bool)
    {
        if (_removeMemberFromCohort(_prevMemberInLinkedList, _member, marchCohort)) {
            return true;
        }
        if (_removeMemberFromCohort(_prevMemberInLinkedList, _member, septemberCohort)) {
            return true;
        }

        revert("SecurityCouncilManager: member not found");
    }

    function _removeMemberFromCohort(
        address _prevMemberInLinkedList,
        address _member,
        address[] storage _cohort
    ) internal returns (bool) {
        for (uint256 i = 0; i < _cohort.length; i++) {
            if (_member == _cohort[i]) {
                delete _cohort[i];
                _dispatchRemoveMember(_prevMemberInLinkedList, _member);
                return true;
            }
        }
        return false;
    }

    function _dispatchRemoveMember(address _prevMemberInLinkedList, address _member) internal {
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainEmergencySecurityCouncilUpgradeExecutor
        ).removeMember(_prevMemberInLinkedList, _member);
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainNonEmergencySecurityCouncilUpgradeExecutor
        ).removeMember(_prevMemberInLinkedList, _member);
        bytes memory data = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.handleRemoveMember.selector,
            _prevMemberInLinkedList,
            _member
        );
        _sendToL1Router(data);
    }

    function _sendToL1Router(bytes memory callData) internal {
        ArbSys(0x0000000000000000000000000000000000000064).sendTxToL1(
            targetContracts.l1SecurityCouncilUpdateRouter, callData
        );
    }
}
