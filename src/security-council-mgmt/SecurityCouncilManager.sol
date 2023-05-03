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

    bytes32 public constant ELECTION_EXECUTOR_ROLE = keccak256("ELECTION_EXECUTOR");
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
        _grantRole(ELECTION_EXECUTOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemover);
        // TODO require non zero, require code? setter
        targetContracts = _targetContracts;
    }

    function executeMarchElectionResult(address[] memory _newMarchCohort)
        external
        onlyRole(ELECTION_EXECUTOR_ROLE)
    {
        require(_newMarchCohort.length == 6, "SecurityCouncilManager: invalid march cohort length");
        // TODO: essure no duplicates accross cohorts?
        address[] memory previousMembersCopy =
            SecurityCouncilMgmtUtils.copyAddressArray(_newMarchCohort);
        marchCohort = _newMarchCohort;
        _dispatchUpdateMembers(_newMarchCohort, previousMembersCopy);
    }

    function executeSeptemperElectionResult(address[] memory _newSeptemberCohort)
        external
        onlyRole(ELECTION_EXECUTOR_ROLE)
    {
        require(
            _newSeptemberCohort.length == 6,
            "SecurityCouncilManager: invalid september cohort length"
        );
        // TODO: essure no duplicates accross cohorts?
        address[] memory previousMembersCopy =
            SecurityCouncilMgmtUtils.copyAddressArray(_newSeptemberCohort);
        septemberCohort = _newSeptemberCohort;
        _dispatchUpdateMembers(_newSeptemberCohort, previousMembersCopy);
    }

    function addMemberToMarchCohort(address _newMember) external onlyRole(MEMBER_ADDER_ROLE) {
        _addMemberToCohort(_newMember, marchCohort);
    }

    function addMemberToSeptemberCohort(address _newMember) external onlyRole(MEMBER_ADDER_ROLE) {
        _addMemberToCohort(_newMember, septemberCohort);
    }

    function _addMemberToCohort(address _newMember, address[] storage _cohort) internal {
        require(_cohort.length < 6, "SecurityCouncilManager: cohort is full");
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newMember, marchCohort),
            "SecurityCouncilManager: member already in march cohort"
        );
        require(
            !SecurityCouncilMgmtUtils.isInArray(_newMember, septemberCohort),
            "SecurityCouncilManager: member already in septemberCohort cohort"
        );

        _cohort.push(_newMember);

        address[] memory membersToAdd;
        membersToAdd[0] = (_newMember);

        address[] memory membersToRemove;
        _dispatchUpdateMembers(membersToAdd, membersToRemove);
    }

    function removeMember(address _member) external onlyRole(MEMBER_REMOVER_ROLE) returns (bool) {
        if (_removeMemberFromCohort(_member, marchCohort)) {
            return true;
        }
        if (_removeMemberFromCohort(_member, septemberCohort)) {
            return true;
        }

        revert("SecurityCouncilManager: member not found");
    }

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

    function _dispatchUpdateMembers(
        address[] memory _membersToAdd,
        address[] memory _membersToRemove
    ) internal {
        (address[] memory newMembers, address[] memory oldMembers) =
            SecurityCouncilMgmtUtils.removeSharedAddresses(_membersToAdd, _membersToRemove);

        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainEmergencySecurityCouncilUpgradeExecutor
        ).updateMembers(newMembers, oldMembers);

        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainNonEmergencySecurityCouncilUpgradeExecutor
        ).updateMembers(newMembers, oldMembers);

        bytes memory data = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.handleUpdateMembers.selector, newMembers, oldMembers
        );
        ArbSys(0x0000000000000000000000000000000000000064).sendTxToL1(
            targetContracts.l1SecurityCouncilUpdateRouter, data
        );
    }
}
