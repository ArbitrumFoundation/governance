// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";
import "./modules/SecurityCouncilMemberElectionGovernorCountingUpgradeable.sol";
import "./SecurityCouncilNomineeElectionGovernor.sol";

import "../interfaces/ISecurityCouncilManager.sol";

// this contract assumes that any active or successful proposal corresponds to the last NomineeElectionGovernor election
// we may want to override state() such that a successful proposal expires if it isn't executed after some time

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
    OwnableUpgradeable
{
    /// @notice The SecurityCouncilNomineeElectionGovernor that creates proposals for this governor and contains the list of compliant nominees
    SecurityCouncilNomineeElectionGovernor public nomineeElectionGovernor;

    /// @notice The SecurityCouncilManager that will execute the election result
    ISecurityCouncilManager public securityCouncilManager;

    /// @param _nomineeElectionGovernor The SecurityCouncilNomineeElectionGovernor
    /// @param _securityCouncilManager The SecurityCouncilManager
    /// @param _token The token used for voting
    /// @param _owner The owner of the governor
    /// @param _votingPeriod The duration of voting on a proposal
    /// @param _maxNominees The maximum number of nominees that can become members
    /// @param _fullWeightDurationNumerator Numerator for the duration of full weight voting
    /// @param _decreasingWeightDurationNumerator Numerator for the duration of decreasing weight voting
    /// @param _durationDenominator Denominator for the duration of full and decreasing weight voting
    function initialize(
        SecurityCouncilNomineeElectionGovernor _nomineeElectionGovernor,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        address _owner,
        uint256 _votingPeriod,
        uint256 _maxNominees,
        uint256 _fullWeightDurationNumerator,
        uint256 _decreasingWeightDurationNumerator,
        uint256 _durationDenominator
    ) public initializer {
        __Governor_init("SecurityCouncilMemberElectionGovernor");
        __GovernorVotes_init(_token);
        __SecurityCouncilMemberElectionGovernorCounting_init({
            _maxNominees: _maxNominees,
            _fullWeightDurationNumerator: _fullWeightDurationNumerator,
            _decreasingWeightDurationNumerator: _decreasingWeightDurationNumerator,
            _durationDenominator: _durationDenominator
        });
        __GovernorSettings_init(0, _votingPeriod, 0);
        _transferOwnership(_owner);

        nomineeElectionGovernor = _nomineeElectionGovernor;
        securityCouncilManager = _securityCouncilManager;
    }

    modifier onlyNomineeElectionGovernor {
        require(msg.sender == address(nomineeElectionGovernor), "SecurityCouncilMemberElectionGovernor: Only the nominee election governor can call this function");
        _;
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

    /// @notice Always reverts.
    /// @dev    `GovernorUpgradeable` function to create a proposal overridden to just revert. 
    ///         We only want proposals to be created via `proposeFromNomineeElectionGovernor`.
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public virtual override returns (uint256) {
        revert("SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead");
    }

    /// @notice Normally "the number of votes required in order for a voter to become a proposer." But in our case it is 0.
    /// @dev    Since we only want proposals to be created via `proposeFromNomineeElectionGovernor`, we set the proposal threshold to 0.
    ///         `proposeFromNomineeElectionGovernor` determines the rules for creating a proposal.
    function proposalThreshold() public pure override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
    }

    /// @notice Quorum is always 0.
    function quorum(uint256) public pure override returns (uint256) {
        return 0;
    }

    /// @notice Creates a new member election proposal from the most recent nominee election.
    function proposeFromNomineeElectionGovernor() external onlyNomineeElectionGovernor {
        GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            nomineeElectionIndexToDescription(nomineeElectionGovernor.electionCount() - 1)
        );
    }

    /// @notice Calls the securityCouncilManager to execute the election result.
    function executeElectionResult(address[] memory _newCohort, Cohort _cohort) external onlyNomineeElectionGovernor {
        securityCouncilManager.executeElectionResult(_newCohort, _cohort);
    }

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle nominee elections.
    ///         We know that _getTopNominees will return a full list of nominees because we checked it in _voteSucceeded.
    ///         Calls `SecurityCouncilManager.executeElectionResult` with the list of nominees.
    function _execute(
        uint256 proposalId,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory /* calldatas */,
        bytes32 /* descriptionHash */
    ) internal override {
        // we know that the list is full because we checked it in _voteSucceeded
        securityCouncilManager.executeElectionResult({
            _newCohort: _getTopNominees(proposalId),
            _cohort: nomineeElectionGovernor.cohortOfMostRecentElection()
        });
    }

    /// @notice Returns the description of a proposal given the nominee election index.
    function nomineeElectionIndexToDescription(uint256 electionIndex) public pure returns (string memory) {
        return string.concat("Member Election for Nominee Election #", StringsUpgradeable.toString(electionIndex));
    }

    /// @dev returns true if the account is a compliant nominee.
    ///      checks the SecurityCouncilNomineeElectionGovernor to see if the account is a compliant nominee of the most recent nominee election
    function _isCompliantNomineeForMostRecentElection(address possibleNominee) internal view override returns (bool) {
        return nomineeElectionGovernor.isCompliantNomineeForMostRecentElection(possibleNominee);
    }
}