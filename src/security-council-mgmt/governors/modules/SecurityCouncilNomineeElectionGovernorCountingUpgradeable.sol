// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

/// @title  SecurityCouncilNomineeElectionGovernorCountingUpgradeable
/// @notice Counting module for the SecurityCouncilNomineeElectionGovernor
///         Keeps track of all contenders that receive enough votes to be a nominee
///         Voters can spread votes across multiple contenders
abstract contract SecurityCouncilNomineeElectionGovernorCountingUpgradeable is Initializable, GovernorUpgradeable {
    // todo: better name
    struct NomineeElectionState {
        mapping(address => uint256) votesUsed;
        mapping(address => uint256) votesReceived;
        address[] nominees;
    }

    // proposalId => NomineeElectionState
    mapping(uint256 => NomineeElectionState) private _elections;

    function __SecurityCouncilNomineeElectionGovernorCounting_init() internal onlyInitializing {}

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    /// @notice returns true if the account has voted any amount for any contender in the proposal
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _elections[proposalId].votesUsed[account] > 0;
    }

    /// @dev there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @dev the vote always succeeds, so we just return true
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @dev This function is responsible for counting votes when they are cast.
    ///      If this vote pushes the candidate over the line, then the candidate is added to the nominees
    ///      and only the necessary amount of votes will be deducted from the voter. 
    /// @param proposalId the id of the proposal
    /// @param account the account that is casting the vote
    /// @param weight the amount of vote that account held at time of snapshot
    /// @param params abi encoded (candidate, votes) where votes is the amount of votes the account is using for this candidate
    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        // let's say params is (address candidate, uint256 votes)
        (address candidate, uint256 votes) = abi.decode(params, (address, uint256));

        require(_isContender(proposalId, candidate), "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Candidate is not eligible");

        require(
            !isNominee(proposalId, candidate), 
            "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Candidate already has enough votes"
        );

        NomineeElectionState storage election = _elections[proposalId];
        uint256 prevVotesUsed = election.votesUsed[account];

        require(
            votes + prevVotesUsed <= weight, 
            "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Not enough tokens to cast this vote"
        );

        uint256 prevVotesReceived = election.votesReceived[candidate];
        uint256 votesThreshold = quorum(proposalSnapshot(proposalId));

        if (prevVotesReceived + votes < votesThreshold) {
            // we didn't push the candidate over the line, so just add the votes
            election.votesUsed[account] = prevVotesUsed + votes;
            election.votesReceived[candidate] = prevVotesReceived + votes;
        }
        else {
            // we pushed the candidate over the line
            // we should only give the candidate enough votes to get to the line so that we don't waste votes
            uint256 votesNeeded = votesThreshold - prevVotesReceived;

            election.votesUsed[account] = prevVotesUsed + votesNeeded;
            election.votesReceived[candidate] = prevVotesReceived + votesNeeded;

            // push the candidate to the nominees
            election.nominees.push(candidate);

            // emit some event like NewNominee(proposalId, candidate);
        }
    }

    /// @notice Returns true if the candidate has enough votes to be a nominee
    function isNominee(uint256 proposalId, address candidate) public view returns (bool) {
        return _elections[proposalId].votesReceived[candidate] >= quorum(proposalSnapshot(proposalId));
    }

    /// @notice Returns the number of nominees for a given proposal
    function nomineeCount(uint256 proposalId) public view returns (uint256) {
        return _elections[proposalId].nominees.length;
    }

    /// @notice Returns the list of nominees for a given proposal
    function nominees(uint256 proposalId) public view returns (address[] memory) {
        return _elections[proposalId].nominees;
    }

    /// @dev Returns true if the account is a contender for the proposal
    function _isContender(uint256 proposalId, address possibleContender) internal view virtual returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}