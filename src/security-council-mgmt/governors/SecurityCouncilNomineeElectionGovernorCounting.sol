// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

abstract contract SecurityCouncilNomineeElectionGovernorCounting is Initializable, GovernorUpgradeable {
    // todo: better name
    struct NomineeElectionState {
        mapping(address => uint256) tokensUsed;
        mapping(address => uint256) votes;
        address[] nominees;
    }

    // proposalId => NomineeElectionState
    mapping(uint256 => NomineeElectionState) private _elections;

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    function hasVoted(
        uint256 proposalId, 
        address account
    ) 
        public 
        view 
        override
        returns (bool) 
    {
        // should this return true if they've cast any amount of votes? or if they've cast all of their votes?
        revert("TODO");
    }

    // there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    // the vote always succeeds, so we just return true
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

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

        // add to tokensUsed
        election.tokensUsed[account] = previouslyUsedTokens + tokens;

        // add tokens to the candidate
        uint256 oldVotesForCandidate = election.votes[candidate];
        election.votes[candidate] = oldVotesForCandidate + tokens;

        // if this vote put the candidate over the line, push to nominees
        uint256 votesNeeded = quorum(proposalSnapshot(proposalId));
        if (oldVotesForCandidate < votesNeeded && oldVotesForCandidate + tokens >= votesNeeded) {
            election.nominees.push(candidate);
            // emit some event like CandidateSuccessfullyNominated(proposalId, candidate);
        }
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