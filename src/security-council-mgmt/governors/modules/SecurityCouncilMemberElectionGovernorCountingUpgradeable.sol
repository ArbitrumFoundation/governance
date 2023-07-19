// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

import "lib/solady/src/utils/LibSort.sol";

/// @title  SecurityCouncilMemberElectionGovernorCountingUpgradeable
/// @notice Counting module for the SecurityCouncilMemberElectionGovernor.
///         Voters can spread their votes across multiple nominees.
///         Implements linearly decreasing voting weights over time.
///         The top k nominees with the most votes are selected as the winners
abstract contract SecurityCouncilMemberElectionGovernorCountingUpgradeable is
    Initializable,
    GovernorUpgradeable
{
    struct ElectionInfo {
        /// @dev The total votes used by a delegate.
        mapping(address => uint256) votesUsed;
        /// @dev The weight of votes received by a nominee. At the start of the election
        ///      each vote has weight 1, however after a cutoff point the weight of each
        ///      vote decreases linearly until it is 0 by the end of the election
        mapping(address => uint256) weightReceived;
    }

    /// @notice Duration of full weight voting (expressed in blocks)
    uint256 public fullWeightDuration;

    mapping(uint256 => ElectionInfo) private _elections;

    // would this be more useful if reason was included?
    /// @notice Emitted when a vote is cast for a nominee
    /// @param voter The account that is casting the vote
    /// @param proposalId The id of the proposal
    /// @param nominee The nominee that is receiving the vote
    /// @param votes The amount of votes that were just cast for the nominee
    /// @param weight The weight of the vote that was just cast for the nominee
    /// @param totalUsedVotes The total amount of votes the voter has used for this proposal
    /// @param usableVotes The total amount of votes the voter has available for this proposal
    /// @param weightReceived The total amount of voting weight the nominee has received for this proposal
    event VoteCastForNominee(
        address indexed voter,
        uint256 indexed proposalId,
        address indexed nominee,
        uint256 votes,
        uint256 weight,
        uint256 totalUsedVotes,
        uint256 usableVotes,
        uint256 weightReceived
    );

    error FullWeightDurationGreaterThanVotingPeriod(
        uint256 fullWeightDuration, uint256 votingPeriod
    );
    error MustVoteWithParams();
    error NotCompliantNominee();
    error ZeroWeightVote();
    error InsufficientVotes();
    error LengthsDontMatch();

    /// @param initialFullWeightDuration Duration of full weight voting (expressed in blocks)
    function __SecurityCouncilMemberElectionGovernorCounting_init(uint256 initialFullWeightDuration)
        internal
        onlyInitializing
    {
        fullWeightDuration = initialFullWeightDuration;
    }

    /// @notice Set the full weight duration numerator and total duration denominator
    function setFullWeightDuration(uint256 newFullWeightDuration) public onlyGovernance {
        if (newFullWeightDuration > votingPeriod()) {
            revert FullWeightDurationGreaterThanVotingPeriod(newFullWeightDuration, votingPeriod());
        }

        fullWeightDuration = newFullWeightDuration;
    }

    /// @notice Register a vote by some account for a proposal.
    /// @dev    Reverts if the account does not have enough votes.
    ///         Reverts if the possibleNominee is not a compliant nominee of the most recent election.
    ///         Weight of the vote is determined using the votesToWeight function.
    ///         Finally, the weight of the vote is added to the weight of the possibleNominee and the top K nominees are updated if necessary.
    /// @param  proposalId The id of the proposal
    /// @param  account The account that is voting
    /// @param  availableVotes The amount of votes that account had at the time of the proposal snapshot
    /// @param  params Abi encoded (address possibleNominee, uint256 votes)
    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 availableVotes,
        bytes memory params
    ) internal virtual override {
        if (params.length != 64) {
            revert MustVoteWithParams();
        }

        (address nominee, uint256 votes) = abi.decode(params, (address, uint256));

        if (!_isCompliantNominee(proposalId, nominee)) {
            revert NotCompliantNominee();
        }

        uint256 weight = votesToWeight(proposalId, block.number, votes);

        if (weight == 0) {
            revert ZeroWeightVote();
        }

        ElectionInfo storage election = _elections[proposalId];

        uint256 prevVotesUsed = election.votesUsed[account];

        if (prevVotesUsed + votes > availableVotes) {
            revert InsufficientVotes();
        }

        uint256 prevWeightReceived = election.weightReceived[nominee];

        election.votesUsed[account] = prevVotesUsed + votes;
        election.weightReceived[nominee] = prevWeightReceived + weight;

        emit VoteCastForNominee({
            voter: account,
            proposalId: proposalId,
            nominee: nominee,
            votes: votes,
            weight: weight,
            totalUsedVotes: prevVotesUsed + votes,
            usableVotes: availableVotes,
            weightReceived: election.weightReceived[nominee]
        });
    }

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        // TODO:
        return "TODO: ???";
    }

    /// @notice Returns the number of votes used by an account for a given proposal
    function votesUsed(uint256 proposalId, address account) public view returns (uint256) {
        return _elections[proposalId].votesUsed[account];
    }

    /// @notice Returns weight received by a nominee for a given proposal
    function weightReceived(uint256 proposalId, address nominee) public view returns (uint256) {
        return _elections[proposalId].weightReceived[nominee];
    }

    /// @notice Returns true if the account has voted any amount for any nominee in the proposal
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return votesUsed(proposalId, account) > 0;
    }

    function fullWeightVotingDeadline(uint256 proposalId) public view returns (uint256) {
        uint256 startBlock = proposalSnapshot(proposalId);

        return startBlock + fullWeightDuration;
    }

    // gas usage is probably a little bit more than (4200 + 1786)n. With 500 that's 2,993,000
    function topNominees(uint256 proposalId) public view returns (address[] memory) {
        address[] memory nominees = _compliantNominees(proposalId);
        uint256[] memory weights = new uint256[](nominees.length);
        ElectionInfo storage election = _elections[proposalId];
        for (uint256 i = 0; i < nominees.length; i++) {
            weights[i] = election.weightReceived[nominees[i]];
        }
        return selectTopNominees(nominees, weights, _targetMemberCount());
    }

    // todo: set a lower threshold bound in the nominee governor.
    // gas usage with k = 6, n = nominees.length is approx 1786n. with 500 it is 902,346
    // these numbers are for the worst case scenario where the nominees are in ascending order
    // these numbers also include memory expansion cost (i think)
    function selectTopNominees(address[] memory nominees, uint256[] memory weights, uint256 k)
        public
        pure
        returns (address[] memory)
    {
        if (nominees.length != weights.length) {
            revert LengthsDontMatch();
        }

        uint256[] memory topNomineesPacked = new uint256[](k);

        for (uint16 i = 0; i < nominees.length; i++) {
            uint256 weight = weights[i];
            // CHRIS: TODO: we need to put guards in here to make sure we dont overflow bounds
            // CHRIS: TODO: alternative is to roll our own sort here, which sholdnt be too difficult
            uint256 packed = (weight << 16) | i;

            if (topNomineesPacked[0] < packed) {
                topNomineesPacked[0] = packed;
                LibSort.insertionSort(topNomineesPacked);
            }
        }

        address[] memory topNomineesAddresses = new address[](k);
        for (uint256 i = 0; i < k; i++) {
            topNomineesAddresses[i] = nominees[uint16(topNomineesPacked[i])];
        }

        return topNomineesAddresses;
    }

    /// @notice Returns the weight of a vote for a given proposal, block number, and number of votes.
    /// @dev    Uses a piecewise linear function to determine the weight of a vote.
    function votesToWeight(uint256 proposalId, uint256 blockNumber, uint256 votes)
        public
        view
        returns (uint256)
    {
        // Before proposalSnapshot all votes have 0 weight
        uint256 startBlock = proposalSnapshot(proposalId);
        if (blockNumber <= startBlock) {
            return 0;
        }
        // After proposalDeadline all votes have zero weight
        uint256 endBlock = proposalDeadline(proposalId);
        if (blockNumber > endBlock) {
            return 0;
        }

        // Between proposalSnapshot and fullWeightVotingDeadline all votes will have 100% weight - each vote has weight 1
        uint256 fullWeightVotingDeadline_ = fullWeightVotingDeadline(proposalId);
        if (blockNumber <= fullWeightVotingDeadline_) {
            return votes;
        }

        // Between the fullWeightVotingDeadline and the proposalDeadline each vote will have weight linearly decreased by time since fullWeightVotingDeadline
        // slope denominator
        uint256 decreasingWeightDuration = endBlock - fullWeightVotingDeadline_;
        // slope numerator is -votes, slope denominator is decreasingWeightDuration, delta x is blockNumber - fullWeightVotingDeadline_
        // y intercept is votes
        uint256 decreaseAmount =
            votes * (blockNumber - fullWeightVotingDeadline_) / decreasingWeightDuration;
        // subtract the decreased amount to get the remaining weight
        return votes - decreaseAmount;
    }

    /// @notice Returns true, since there is no minimum quorum
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @notice Returns true if votes have been cast for at least K nominees
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @dev Returns true if the possibleNominee is a compliant nominee for the most recent election
    function _isCompliantNominee(uint256 proposalId, address possibleNominee)
        internal
        view
        virtual
        returns (bool);

    /// @dev Returns all the compliant (non excluded) nominees for the requested proposal
    function _compliantNominees(uint256 proposalId)
        internal
        view
        virtual
        returns (address[] memory);

    /// @dev Returns the target number of members to elect
    function _targetMemberCount() internal view virtual returns (uint256);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
