// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../L2ArbitrumGovernor.sol";
import "./SecurityCouncilNominationsManager.sol";
import "./interfaces/ISecurityCouncilManager.sol";


// narrows a set of candidates down to a set of nominees
// todo: setter for the nominations manager
// todo: ERC165
contract SecurityCouncilNominationsGovernor is L2ArbitrumGovernor {
    // override all GovernorCountingSimpleUpgradeable functions

    // override all GovernorTimelockControlUpgradeable functions 
    // (and L2ArbitrumGovernor functions that override GovernorTimelockControlUpgradeable)
    // because we don't need a timelock

    // we also don't need GovernorPreventLateQuorumUpgradeable
    // so we set the minPeriodAfterQuorum to 0?

    // also override propose to make sure only the manager can call it

    struct NominationElection {
        uint256 electionId; // NominationsManager's electionId
        mapping(address => uint256) nominationsTokensUsed;
        mapping(address => uint256) nominationsVotes;
        address[] successfullyNominatedCandidates;
    }

    SecurityCouncilNominationsManager public nominationsManager;

    // proposalId => GovernorNominationElection
    mapping(uint256 => NominationElection) nominationElections;

    /// @param _token The token to read vote delegation from
    /// @param _owner The executor through which all upgrades should be finalised
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    function initialize(
        IVotesUpgradeable _token,
        address _owner,
        SecurityCouncilNominationsManager _nominationsManager,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator // 0.2%, required for any candidate to become a nominee for next phases
    ) external initializer {
        __Governor_init("TODO: some name here like NominationsGovernor or something");
        __GovernorSettings_init(_votingDelay, _votingPeriod, 0);
        // __GovernorCountingSimple_init(); // we are overriding this
        __GovernorVotes_init(_token);
        // __GovernorTimelockControl_init(_timelock); // we are overriding this too
        __GovernorVotesQuorumFraction_init(_quorumNumerator);
        __GovernorPreventLateQuorum_init(0); // set this to 0 to disable prevent late quorum?
        _transferOwnership(_owner);

        nominationsManager = _nominationsManager;
    }

    modifier onlyManager {
        require(msg.sender == address(nominationsManager), "Only the manager can call this");
        _;
    }

    ////////////// GovernorCountingSimple Overrides //////////////

    function COUNTING_MODE() public pure virtual override(GovernorCountingSimpleUpgradeable, IGovernorUpgradeable) returns (string memory) {
        return "TODO: ???";
    }

    function hasVoted(
        uint256 proposalId, 
        address account
    ) 
        public 
        view 
        override(GovernorCountingSimpleUpgradeable, IGovernorUpgradeable) 
        returns (bool) 
    {
        // should this return true if they've cast any amount of votes? or if they've cast all of their votes?
        revert("TODO");
    }

    // unsupported because it is supposed to return for, against, abstain. but that doesn't make sense for nominations
    function proposalVotes(
        uint256
    ) public pure override(GovernorCountingSimpleUpgradeable) returns (uint256, uint256, uint256) {
        revert("Unsupported");
    }

    // there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable) returns (bool) {
        return true;
    }

    // the vote always succeeds, so we just return true
    function _voteSucceeded(uint256) internal pure override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable) returns (bool) {
        return true;
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable) {
        // let's say params is (address candidate, uint256 tokens)
        (address candidate, uint256 tokens) = abi.decode(params, (address, uint256));

        require(_isCandidateEligible(proposalId, candidate), "Candidate is not eligible");

        NominationElection storage election = nominationElections[proposalId];

        // weight is the number of tokens that account has at the time of the vote
        // make sure tokens + previously used tokens is less than or equal to weight
        uint256 previouslyUsedTokens = election.nominationsTokensUsed[account];
        require(tokens + previouslyUsedTokens <= weight, "Not enough tokens to cast this vote");

        // add to nominationsTokensUsed
        election.nominationsTokensUsed[account] = previouslyUsedTokens + tokens;

        // add tokens to the candidate
        uint256 oldVotesForCandidate = election.nominationsVotes[candidate];
        election.nominationsVotes[candidate] = oldVotesForCandidate + tokens;

        // if this vote put the candidate over the line, push to successfullyNominatedCandidates
        uint256 votesNeeded = quorum(proposalSnapshot(proposalId));
        if (oldVotesForCandidate < votesNeeded && oldVotesForCandidate + tokens >= votesNeeded) {
            election.successfullyNominatedCandidates.push(candidate);
            // emit some event like CandidateSuccessfullyNominated(proposalId, candidate);
        }
    }

    ////////////// End GovernorCountingSimple Overrides //////////////

    ////////////// GovernorTimelockControl Overrides //////////////

    // should these view functions just revert?

    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        return GovernorUpgradeable.state(proposalId);
    }

    function timelock() public view virtual override returns (address) {
        return address(0);
    }

    function proposalEta(uint256) public view virtual override returns (uint256) {
        return 0;
    }

    function queue(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        bytes32
    ) public virtual override returns (uint256) {
        revert("Unsupported");
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override {
        GovernorUpgradeable._execute(
            proposalId, targets, values, calldatas, descriptionHash
        );
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint256) {
        return GovernorUpgradeable._cancel(targets, values, calldatas, descriptionHash);
    }

    function updateTimelock(TimelockControllerUpgradeable newTimelock) external virtual override {
        revert("Unsupported");
    }

    ////////////// End GovernorTimelockControl Overrides //////////////

    // override propose such that only the manager contract can call it
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(GovernorUpgradeable, IGovernorUpgradeable) onlyManager returns (uint256) {
        uint256 proposalId = super.propose(targets, values, calldatas, description);

        // set the electionId for this proposal
        uint256 electionId = nominationsManager.nominationsCount();
        nominationElections[proposalId].electionId = electionId;

        return proposalId;
    }

    // returns true if the candidate has enough votes to be nominated
    function isCandidateSuccessfullyNominated(uint256 proposalId, address candidate) public view returns (bool) {
        return nominationElections[proposalId].nominationsVotes[candidate] >= quorum(proposalSnapshot(proposalId));
    }

    function successfullyNominatedCandidatesCount(uint256 proposalId) public view returns (uint256) {
        return nominationElections[proposalId].successfullyNominatedCandidates.length;
    }

    function successfullyNominatedCandidates(uint256 proposalId) public view returns (address[] memory) {
        return nominationElections[proposalId].successfullyNominatedCandidates;
    }

    // check the manager contract to see if the candidate is eligible
    function _isCandidateEligible(uint256 proposalId, address candidate) internal view returns (bool) {
        uint256 electionId = nominationElections[proposalId].electionId;
        return nominationsManager.isCandidateUpForNomination(electionId, candidate);
    }
}
