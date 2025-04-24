// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./modules/SecurityCouncilMemberElectionGovernorCountingUpgradeable.sol";
import "../interfaces/ISecurityCouncilMemberElectionGovernor.sol";
import "../interfaces/ISecurityCouncilNomineeElectionGovernor.sol";
import "../interfaces/ISecurityCouncilManager.sol";
import "./modules/ElectionGovernor.sol";

/// @title  SecurityCouncilMemberElectionGovernor
/// @notice Narrows a set of nominees down to a set of members.
/// @dev    Proposals are created by the SecurityCouncilNomineeElectionGovernor.
///         This governor is responsible for executing the final election result by calling the SecurityCouncilManager.
contract SecurityCouncilMemberElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilMemberElectionGovernorCountingUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable,
    ElectionGovernor,
    ISecurityCouncilMemberElectionGovernor
{
    /// @notice The SecurityCouncilNomineeElectionGovernor that creates proposals for this governor and contains the list of compliant nominees
    ISecurityCouncilNomineeElectionGovernor public nomineeElectionGovernor;

    /// @notice The SecurityCouncilManager that will execute the election result
    ISecurityCouncilManager public securityCouncilManager;

    error InvalidDurations(uint256 fullWeightDuration, uint256 votingPeriod);
    error OnlyNomineeElectionGovernor();
    error ProposeDisabled();
    error CastVoteDisabled();

    constructor() {
        _disableInitializers();
    }

    /// @param _nomineeElectionGovernor The SecurityCouncilNomineeElectionGovernor
    /// @param _securityCouncilManager The SecurityCouncilManager
    /// @param _token The token used for voting
    /// @param _owner The owner of the governor
    /// @param _votingPeriod The duration of voting on a proposal
    /// @param _fullWeightDuration Duration of full weight voting (blocks)
    function initialize(
        ISecurityCouncilNomineeElectionGovernor _nomineeElectionGovernor,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        address _owner,
        uint256 _votingPeriod,
        uint256 _fullWeightDuration
    ) public initializer {
        if (_fullWeightDuration > _votingPeriod) {
            revert InvalidDurations(_fullWeightDuration, _votingPeriod);
        }

        __Governor_init("SecurityCouncilMemberElectionGovernor");
        __GovernorVotes_init(_token);
        __SecurityCouncilMemberElectionGovernorCounting_init({
            initialFullWeightDuration: _fullWeightDuration
        });
        __GovernorSettings_init(0, _votingPeriod, 0);
        _transferOwnership(_owner);

        if (!Address.isContract(address(_nomineeElectionGovernor))) {
            revert NotAContract(address(_nomineeElectionGovernor));
        }
        nomineeElectionGovernor = _nomineeElectionGovernor;
        if (!Address.isContract(address(_securityCouncilManager))) {
            revert NotAContract(address(_securityCouncilManager));
        }
        securityCouncilManager = _securityCouncilManager;
    }

    modifier onlyNomineeElectionGovernor() {
        if (msg.sender != address(nomineeElectionGovernor)) {
            revert OnlyNomineeElectionGovernor();
        }
        _;
    }

    /// @inheritdoc ISecurityCouncilMemberElectionGovernor
    function proposeFromNomineeElectionGovernor(uint256 electionIndex)
        external
        onlyNomineeElectionGovernor
        returns (uint256)
    {
        // we use the same getProposeArgs to ensure the proposal id is consistent across governors
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory callDatas,
            string memory description
        ) = getProposeArgs(electionIndex);
        return GovernorUpgradeable.propose(targets, values, callDatas, description);
    }

    /// @notice Allows the owner to make calls from the governor
    /// @dev    See {L2ArbitrumGovernor-relay}
    function relay(address target, uint256 value, bytes calldata data)
        external
        virtual
        override
        onlyOwner
    {
        AddressUpgradeable.functionCallWithValue(target, data, value);
    }

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle member elections.
    ///         We know that topNominees() will return a full list.
    ///         Calls `SecurityCouncilManager.replaceCohort` with the list of nominees.
    function _execute(
        uint256 proposalId,
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory callDatas,
        bytes32 /* descriptionHash */
    ) internal override {
        // we know that the election index is part of the calldatas
        uint256 electionIndex = extractElectionIndex(callDatas);

        // it's possible for this call to fail because of checks in the security council manager
        // getting into a state inconsistent with the elections, if it does the Security Council
        // will need to update the Manager so that this replaceCohort can go through
        // Otherwise this and future elections will remain blocked.
        securityCouncilManager.replaceCohort({
            _newCohort: topNominees(proposalId),
            _cohort: electionIndexToCohort(electionIndex)
        });
    }

    /// @notice Normally "the number of votes required in order for a voter to become a proposer." But in our case it is 0.
    /// @dev    Since we only want proposals to be created via `proposeFromNomineeElectionGovernor`, we set the proposal threshold to 0.
    ///         `proposeFromNomineeElectionGovernor` determines the rules for creating a proposal.
    function proposalThreshold()
        public
        pure
        override(GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return 0;
    }

    /// @notice Quorum is always 0.
    function quorum(uint256) public pure override returns (uint256) {
        return 0;
    }

    /// @dev Whether the account is a compliant nominee.
    ///      checks the SecurityCouncilNomineeElectionGovernor to see if the account is a compliant nominee
    function _isCompliantNominee(uint256 proposalId, address possibleNominee)
        internal
        view
        override
        returns (bool)
    {
        return nomineeElectionGovernor.isCompliantNominee(proposalId, possibleNominee);
    }

    /// @dev Returns all the compliant (non excluded) nominees for the requested proposal
    function _compliantNominees(uint256 proposalId)
        internal
        view
        override
        returns (address[] memory)
    {
        return nomineeElectionGovernor.compliantNominees(proposalId);
    }

    /// @inheritdoc SecurityCouncilMemberElectionGovernorCountingUpgradeable
    function _targetMemberCount() internal view override returns (uint256) {
        return securityCouncilManager.cohortSize();
    }

    /// @notice Always reverts.
    /// @dev    `GovernorUpgradeable` function to create a proposal overridden to just revert.
    ///         We only want proposals to be created via `proposeFromNomineeElectionGovernor`.
    function propose(address[] memory, uint256[] memory, bytes[] memory, string memory)
        public
        virtual
        override
        returns (uint256)
    {
        revert ProposeDisabled();
    }

    /// @notice Always reverts. Use castVoteWithReasonAndParams instead
    function castVote(uint256, uint8) public virtual override returns (uint256) {
        revert CastVoteDisabled();
    }

    /// @notice Always reverts. Use castVoteWithReasonAndParams instead
    function castVoteWithReason(uint256, uint8, string calldata)
        public
        virtual
        override
        returns (uint256)
    {
        revert CastVoteDisabled();
    }

    /// @notice Always reverts. Use castVoteWithReasonAndParamsBySig instead
    function castVoteBySig(uint256, uint8, uint8, bytes32, bytes32)
        public
        virtual
        override
        returns (uint256)
    {
        revert CastVoteDisabled();
    }

    /// @inheritdoc ElectionGovernor
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override(GovernorUpgradeable, ElectionGovernor) returns (uint256) {
        return ElectionGovernor.castVoteWithReasonAndParamsBySig(
            proposalId, support, reason, params, v, r, s
        );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
