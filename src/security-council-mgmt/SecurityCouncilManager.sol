// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "./interfaces/IL1SecurityCouncilUpdateRouter.sol";
import "./SecurityCouncilMgmtUtils.sol";

contract SecurityCouncilManager is Initializable, AccessControlUpgradeable {
    // cohort arrays are source-of-truth for security council; the 12 owners security council owners should always be equal to the
    // sum of these two arrays (or have pending x-chain messages on their way to updating them)
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

    enum Cohort {
        MARCH,
        SEPTEMBER
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
        _grantRole(DEFAULT_ADMIN_ROLE, _roles.admin);
        _grantRole(ELECTION_EXECUTOR_ROLE, _roles.cohortUpdator);
        _grantRole(MEMBER_ADDER_ROLE, _roles.memberAdder);
        _grantRole(MEMBER_REMOVER_ROLE, _roles.memberRemover);
        // TODO require non zero / require code? setter method to update?
        targetContracts = _targetContracts;
    }

    /// @notice callable only by Election Governer. Updates cohort in this contract's state and triggers dispatch
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
    }

    /// @notice callable only by 9 of 12 SC. Adds member in this contract's state and triggers dispatch
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
    }

    /// @notice callable only by SC Removal Governor.
    /// Don't need to specify cohort since duplicate members aren't allowed (so always unambiguous)
    function removeMember(address _member) external onlyRole(MEMBER_REMOVER_ROLE) returns (bool) {
        if (_removeMemberFromCohort(_member, marchCohort)) {
            return true;
        }
        if (_removeMemberFromCohort(_member, septemberCohort)) {
            return true;
        }

        revert("SecurityCouncilManager: member not found");
    }

    /// @notice Removes member in this contract's state and triggers dispatch
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

    /// @notice initates update to all Security Council Multisigs (gov chain, L1, and all others governed L2 chains)
    function _dispatchUpdateMembers(
        address[] memory _membersToAdd,
        address[] memory _membersToRemove
    ) internal {
        // A candidate new be relected, which case they appear in both the arrays; removing and re-added is a no-op. We instead remove them from both arrays; this simplifies the logic of updating them in the gnosis safe.
        (address[] memory newMembers, address[] memory oldMembers) =
            SecurityCouncilMgmtUtils.removeSharedAddresses(_membersToAdd, _membersToRemove);

        // update 9 of 12 gov-chain council directly
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainEmergencySecurityCouncilUpgradeExecutor
        ).updateMembers(newMembers, oldMembers);

        // update 7 of 12 gov-chain council directly
        ISecurityCouncilUpgradeExectutor(
            targetContracts.govChainNonEmergencySecurityCouncilUpgradeExecutor
        ).updateMembers(newMembers, oldMembers);

        // Initiate L2 to L1 message to handle updating remaining secuirity councils
        bytes memory data = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.handleUpdateMembers.selector, newMembers, oldMembers
        );
        ArbSys(0x0000000000000000000000000000000000000064).sendTxToL1(
            targetContracts.l1SecurityCouncilUpdateRouter, data
        );
    }
}
