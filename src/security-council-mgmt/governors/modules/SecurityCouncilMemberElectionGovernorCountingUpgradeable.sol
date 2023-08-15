// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

import "solady/utils/LibSort.sol";

/// @title  SecurityCouncilMemberElectionGovernorCountingUpgradeable
/// @notice Counting module for the SecurityCouncilMemberElectionGovernor.
///         Voters can spread their votes across multiple nominees.
///         Implements linearly decreasing voting weights over time.
///         The `_targetMemberCount()` nominees with the most votes are selected as the winners.
abstract contract SecurityCouncilMemberElectionGovernorCountingUpgradeable is
    Initializable,
    GovernorUpgradeable
{
    struct ElectionInfo {
        /// @dev The total votes used by a delegate.
        mapping(address => uint256) votesUsed;
        /// @dev The weight of votes received by a nominee. At the start of the election
        ///      each vote has weight 1, however after a cutoff point the weight of each
        ///      vote decreases linearly until it is 0 by the end of the election.
        ///      Using uint240 because of the sorting implementation, see `selectTopNominees`
        mapping(address => uint240) weightReceived;
    }

    /// @notice Duration of full weight voting (expressed in blocks)
    uint256 public fullWeightDuration;

    /// @dev proposalId => ElectionInfo
    mapping(uint256 => ElectionInfo) private _elections;

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
    /// @notice Emitted when the a new full weight duration is set
    event FullWeightDurationSet(uint256 newFullWeightDuration);

    error FullWeightDurationGreaterThanVotingPeriod(
        uint256 fullWeightDuration, uint256 votingPeriod
    );
    error UnexpectedParamsLength(uint256 paramLength);
    error NotCompliantNominee(address nominee);
    error ZeroWeightVote(uint256 blockNumber, uint256 votes);
    error InsufficientVotes(uint256 prevVotesUsed, uint256 votes, uint256 availableVotes);
    error LengthsDontMatch(uint256 nomineesLength, uint256 weightsLength);
    error NotEnoughNominees(uint256 numNominees, uint256 k);
    error UintTooLarge(uint256 x);
    error InvalidSupport(uint8 support);

    /// @param initialFullWeightDuration Duration of full weight voting (expressed in blocks)
    function __SecurityCouncilMemberElectionGovernorCounting_init(uint256 initialFullWeightDuration)
        internal
        onlyInitializing
    {
        fullWeightDuration = initialFullWeightDuration;
        emit FullWeightDurationSet(initialFullWeightDuration);
    }

    /// @notice Set the full weight duration
    /// @dev    Note that this should not be called during an ongoing election
    ///         as it may lead to inconsistent weights in the ongoing election
    function setFullWeightDuration(uint256 newFullWeightDuration) public onlyGovernance {
        if (newFullWeightDuration > votingPeriod()) {
            revert FullWeightDurationGreaterThanVotingPeriod(newFullWeightDuration, votingPeriod());
        }

        fullWeightDuration = newFullWeightDuration;
        emit FullWeightDurationSet(newFullWeightDuration);
    }

    /// @notice Register a vote by some account for a nominee.
    /// @dev    Reverts if the account does not have enough votes.
    ///         Reverts if the provided nominee is not a compliant nominee of the election.
    ///         Weight of the vote is determined using the votesToWeight function.
    /// @param  proposalId The id of the proposal
    /// @param  account The account that is voting
    /// @param  support The support of the vote (forced to 1)
    /// @param  availableVotes The amount of votes that account had at the time of the proposal snapshot
    /// @param  params Abi encoded (address nominee, uint256 votes)
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 availableVotes,
        bytes memory params
    ) internal virtual override {
        if (support != 1) {
            revert InvalidSupport(support);
        }

        if (params.length != 64) {
            revert UnexpectedParamsLength(params.length);
        }

        (address nominee, uint256 votes) = abi.decode(params, (address, uint256));
        if (!_isCompliantNominee(proposalId, nominee)) {
            revert NotCompliantNominee(nominee);
        }

        uint240 weight = votesToWeight(proposalId, block.number, votes);
        if (weight == 0) {
            revert ZeroWeightVote(block.number, votes);
        }

        ElectionInfo storage election = _elections[proposalId];
        uint256 prevVotesUsed = election.votesUsed[account];
        if (prevVotesUsed + votes > availableVotes) {
            revert InsufficientVotes(prevVotesUsed, votes, availableVotes);
        }

        uint240 prevWeightReceived = election.weightReceived[nominee];
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

    /// @inheritdoc IGovernorUpgradeable
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=for&params=account&counting=n-winners";
    }

    /// @notice Number of votes used by an account for a given proposal
    function votesUsed(uint256 proposalId, address account) public view returns (uint256) {
        return _elections[proposalId].votesUsed[account];
    }

    /// @notice Weight received by a nominee for a given proposal
    function weightReceived(uint256 proposalId, address nominee) public view returns (uint256) {
        return _elections[proposalId].weightReceived[nominee];
    }

    /// @notice Whether the account has voted any amount for any nominee in the proposal
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return votesUsed(proposalId, account) > 0;
    }

    /// @notice The deadline after which voting weight will linearly decrease
    /// @param proposalId The proposal to check the deadline for
    function fullWeightVotingDeadline(uint256 proposalId) public view returns (uint256) {
        uint256 startBlock = proposalSnapshot(proposalId);
        return startBlock + fullWeightDuration;
    }

    /// @notice Gets the top K nominees with greatest weight for a given proposal,
    ///         where K is the manager.cohortSize()
    /// @dev    Care must be taken of gas usage in this function.
    ///         This is an O(n) operation on all compliant nominees in the nominees governor.
    ///         The maximum number of nominees is set by the threshold of votes required to become a nominee.
    ///         Currently this is 0.2% of votable tokens, which corresponds to 500 max nominees.
    ///         Absolute worst case, this function uses 4502345 with 500 nominees, or about 9k gas per nominee (when called externally).
    /// @param proposalId The proposal to find the top nominees for
    function topNominees(uint256 proposalId) public view returns (address[] memory) {
        address[] memory nominees = _compliantNominees(proposalId);
        uint240[] memory weights = new uint240[](nominees.length);
        ElectionInfo storage election = _elections[proposalId];
        for (uint256 i = 0; i < nominees.length; i++) {
            weights[i] = election.weightReceived[nominees[i]];
        }
        return selectTopNominees(nominees, weights, _targetMemberCount());
    }

    /// @notice Gets the top K nominees from a list of nominees and weights.
    /// @param nominees The nominees to select from
    /// @param weights  The weights of the nominees
    /// @param k        The number of nominees to select
    function selectTopNominees(address[] memory nominees, uint240[] memory weights, uint256 k)
        public
        pure
        returns (address[] memory)
    {
        if (nominees.length != weights.length) {
            revert LengthsDontMatch(nominees.length, weights.length);
        }
        if (nominees.length < k) {
            revert NotEnoughNominees(nominees.length, k);
        }

        uint256[] memory topNomineesPacked = new uint256[](k);

        for (uint16 i = 0; i < nominees.length; i++) {
            // The nominee's index in the address array is stored in the 16 rightmost bits; the remaining bits store the nominee's weight
            uint256 packed = (uint256(weights[i]) << 16) | i;
            // Packed weight/index values can be compared when comparing weights, since the values of the weights will outweigh any difference in index;
            // the index value only takes effect here as tie-breaker if the weights are equal.
            // If the current weight is greater than the smallest of the top-6 weights so far, replace the smallest element with it and re-sort.
            if (topNomineesPacked[0] < packed) {
                topNomineesPacked[0] = packed;
                LibSort.insertionSort(topNomineesPacked);
            }
        }

        address[] memory topNomineesAddresses = new address[](k);
        for (uint16 i = 0; i < k; i++) {
            // retrieve the index from the packed value to look up the nominee's address.
            topNomineesAddresses[i] = nominees[uint16(topNomineesPacked[i])];
        }

        return topNomineesAddresses;
    }

    /// @notice Returns the weight of a vote for a given proposal, block number, and number of votes.
    ///         Each vote has weight 1 until the fullWeightVotingDeadline is reached, after which each vote has linearly
    ///         decreasing weight, reaching 0 at the proposalDeadline.
    function votesToWeight(uint256 proposalId, uint256 blockNumber, uint256 votes)
        public
        view
        returns (uint240)
    {
        // Votes have zero weight until after snapshot block
        // Votes are not counted anyway on the actual snapshot block due to a check
        // in token.getPastVotes()
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
            return _downCast(votes);
        }

        // Between the fullWeightVotingDeadline and the proposalDeadline each vote will have weight linearly decreased by time since fullWeightVotingDeadline
        // slope denominator
        uint256 decreasingWeightDuration = endBlock - fullWeightVotingDeadline_;
        // slope numerator is -votes, slope denominator is decreasingWeightDuration, delta x is blockNumber - fullWeightVotingDeadline_
        // y intercept is votes
        uint256 decreaseAmount =
            votes * (blockNumber - fullWeightVotingDeadline_) / decreasingWeightDuration;
        // subtract the decreased amount to get the remaining weight
        return _downCast(votes - decreaseAmount);
    }

    /// @notice Downcasts a uint256 to a uint240, reverting if the input is too large
    function _downCast(uint256 x) internal pure returns (uint240) {
        if (x > type(uint240).max) {
            revert UintTooLarge(x);
        }
        return uint240(x);
    }

    /// @notice True, since there is no minimum quorum
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @notice True, since an election can only be only started if there are enough nominees
    ///         and candidates cannot be excluded after the election has started
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @dev Whether the possibleNominee is a compliant nominee for the given proposal
    function _isCompliantNominee(uint256 proposalId, address possibleNominee)
        internal
        view
        virtual
        returns (bool);

    /// @dev The list of all compliant (non excluded) nominees for the requested proposal
    function _compliantNominees(uint256 proposalId)
        internal
        view
        virtual
        returns (address[] memory);

    /// @dev The target number of members to elect
    function _targetMemberCount() internal view virtual returns (uint256);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
