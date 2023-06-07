// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

abstract contract SecurityCouncilNomineeElectionGovernorCountingUpgradeable is Initializable, GovernorUpgradeable {
    // todo: better name
    struct NomineeElectionState {
        mapping(address => uint256) tokensUsed;
        mapping(address => uint256) votes;
        address[] nominees;
    }

    // proposalId => NomineeElectionState
    mapping(uint256 => NomineeElectionState) private _elections;

    function __SecurityCouncilNomineeElectionGovernorCounting_init() internal onlyInitializing {}

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    // returns true if the account has voted any amount for any contender
    function hasVoted(
        uint256 proposalId, 
        address account
    ) 
        public 
        view 
        override
        returns (bool) 
    {
        return _elections[proposalId].tokensUsed[account] > 0;
    }

    // there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    // the vote always succeeds, so we just return true
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    // todo: rename candidate to contender everywhere, not just here
    // generally make sure naming is consistent
    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        // let's say params is (address candidate, uint256 tokens)
        (address candidate, uint256 tokens) = abi.decode(params, (address, uint256));

        require(_isContender(proposalId, candidate), "Candidate is not eligible");

        NomineeElectionState storage election = _elections[proposalId];

        // weight is the number of tokens that account has at the time of the vote
        // make sure tokens + previously used tokens is less than or equal to weight
        uint256 previouslyUsedTokens = election.tokensUsed[account];
        require(tokens + previouslyUsedTokens <= weight, "Not enough tokens to cast this vote");

        uint256 oldVotesForCandidate = election.votes[candidate];
        uint256 votesThreshold = quorum(proposalSnapshot(proposalId));

        require(oldVotesForCandidate < votesThreshold, "Candidate already has enough votes");

        if (oldVotesForCandidate + tokens < votesThreshold) {
            // we didn't push the candidate over the line, so just add the tokens
            election.tokensUsed[account] = previouslyUsedTokens + tokens;
            election.votes[candidate] = oldVotesForCandidate + tokens;
        }
        else {
            // we pushed the candidate over the line
            // we should only give the candidate enough tokens to get to the line so that we don't waste tokens
            uint256 tokensNeeded = votesThreshold - oldVotesForCandidate;

            election.tokensUsed[account] = previouslyUsedTokens + tokensNeeded;
            election.votes[candidate] = oldVotesForCandidate + tokensNeeded;

            // push the candidate to the nominees
            election.nominees.push(candidate);

            // emit some event like NewNominee(proposalId, candidate);
        }
    }

    function isNominee(uint256 proposalId, address candidate) public view returns (bool) {
        return _elections[proposalId].votes[candidate] >= quorum(proposalSnapshot(proposalId));
    }

    function nomineeCount(uint256 proposalId) public view returns (uint256) {
        return _elections[proposalId].nominees.length;
    }

    function nominees(uint256 proposalId) public view returns (address[] memory) {
        return _elections[proposalId].nominees;
    }

    function _isContender(uint256 proposalId, address candidate) internal view virtual returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}