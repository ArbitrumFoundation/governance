// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

/// @title AccountRankerUpgradeable
/// @notice Keeps track of the top K nominees for a given proposalId and their weights
abstract contract AccountRankerUpgradeable is Initializable {
    /// @dev max number of nominees to track (6)
    uint256 private _maxNominees;

    /// @dev proposalId => list of top nominees in descending order by weight
    mapping(uint256 => address[]) private _nominees;

    /// @dev proposalId => account => weight.
    ///      weight is the voting weight cast for the account
    mapping(uint256 => mapping(address => uint256)) private _weights;

    function __AccountRanker_init(uint256 maxNominees_) internal onlyInitializing {
        _maxNominees = maxNominees_;
    }

    /// @notice returns the max number of nominees this contract will track
    function maxNominees() public view returns (uint256) {
        return _maxNominees;
    }

    /// @dev returns the list of top nominees for a given proposalId
    function topNominees(uint256 proposalId) public view returns (address[] memory) {
        return _nominees[proposalId];
    }

    /// @dev returns true if the list of top nominees is full for a given proposalId
    function isNomineesListFull(uint256 proposalId) public view returns (bool) {
        return _nominees[proposalId].length == _maxNominees;
    }

    /// @dev returns the received voting weight of a contender in a given proposalId
    function votingWeightReceived(uint256 proposalId, address contender)
        public
        view
        returns (uint256)
    {
        return _weights[proposalId][contender];
    }

    /// @dev increases the weight of an account in a given proposalId.
    ///      updates the list of top nominees for that proposalId if necessary.
    function _increaseNomineeWeight(uint256 proposalId, address account, uint256 weightToAdd)
        internal
    {
        address[] storage nomineesPtr = _nominees[proposalId];
        mapping(address => uint256) storage weightsPtr = _weights[proposalId];

        uint256 oldWeight = weightsPtr[account];
        uint256 newWeight = oldWeight + weightToAdd;

        // update the weight of account
        weightsPtr[account] = newWeight;

        // check to see if the account is already in the top K
        uint256 previousIndexOfAccount = type(uint256).max;
        // todo: can probably just skip this loop if the oldWeight is less than the weight of the last nominee
        for (uint256 i = 0; i < nomineesPtr.length; i++) {
            if (nomineesPtr[i] == account) {
                previousIndexOfAccount = i;
                break;
            }
        }

        // if the array is not max length yet, and account is not already in the list, just add the account to the end
        if (previousIndexOfAccount == type(uint256).max && nomineesPtr.length < _maxNominees) {
            nomineesPtr.push(account);
            previousIndexOfAccount = nomineesPtr.length - 1;
        }
        // if the array is max length already, and account is not already in the list, set the previousIndexOfAccount to the length of the array
        else if (previousIndexOfAccount == type(uint256).max) {
            previousIndexOfAccount = nomineesPtr.length;
        }

        if (previousIndexOfAccount == 0) {
            // account is already at the top of the list
            return;
        }

        // start with the account's index - 1 and move to the left, shifting things down to the right until we find the appropriate spot
        uint256 j = previousIndexOfAccount - 1;
        while (true) {
            address nominee = nomineesPtr[j];
            if (newWeight > weightsPtr[nominee]) {
                // the account's weight is greater than the nominee we are looking at
                // we should move nominee down the list by one (unless they are already at the bottom)
                if (j != nomineesPtr.length - 1) {
                    nomineesPtr[j + 1] = nominee;
                }
            } else {
                // the account's weight is less than or equal to the nominee we are looking at
                // if we are at the bottom of the list, then return
                // if we are not, then we should place the account just to the right of the nominee we are looking at and return
                if (j != nomineesPtr.length - 1) {
                    nomineesPtr[j + 1] = account;
                }
                return;
            }

            if (j == 0) break;
            j--;
        }

        // if we get here, we have passed the end of the list, so we should place the account at the beginning
        nomineesPtr[0] = account;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}

/// @title  SecurityCouncilMemberElectionGovernorCountingUpgradeable
/// @notice Counting module for the SecurityCouncilMemberElectionGovernor.
///         Voters can spread their votes across multiple nominees.
///         Implements linearly decreasing voting weights over time.
///         Uses AccountRankerUpgradeable to keep track of the top K nominees and their weights (where K is the number of nominees we want to select to become members).
abstract contract SecurityCouncilMemberElectionGovernorCountingUpgradeable is
    Initializable,
    GovernorUpgradeable,
    AccountRankerUpgradeable
{
    uint256 private constant WAD = 1e18;

    // /// @notice Numerator for the duration of full weight voting
    // uint256 private _fullWeightDurationNumerator; // = 1 (7 days)
    // /// @notice Denominator for the total duration of voting
    // uint256 private _durationDenominator; // = 3 (21 days)

    /// @notice Duration of full weight voting (expressed in blocks)
    uint256 private _fullWeightDuration;

    /// @notice Keeps track of the number of votes used by each account for each proposal
    mapping(uint256 => mapping(address => uint256)) private _votesUsed;

    // would this be more useful if reason was included?
    event VoteCastForNominee(
        address indexed voter,
        uint256 indexed proposalId,
        address indexed nominee,
        uint256 votes,
        uint256 weight
    );

    /// @param maxNominees The maximum number of nominees to track
    /// @param initialFullWeightDuration Duration of full weight voting (expressed in blocks)
    function __SecurityCouncilMemberElectionGovernorCounting_init(
        uint256 maxNominees,
        uint256 initialFullWeightDuration
    ) internal onlyInitializing {
        __AccountRanker_init(maxNominees);

        _fullWeightDuration = initialFullWeightDuration;
    }

    /// @notice Returns the duration of full weight voting (expressed in blocks)
    function fullWeightDuration() public view returns (uint256) {
        return _fullWeightDuration;
    }

    /// @notice Set the full weight duration numerator and total duration denominator
    function setFullWeightDuration(
        uint256 newFullWeightDuration
    ) public onlyGovernance {
        require(
            newFullWeightDuration <= votingPeriod(),
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Full weight duration must be <= votingPeriod"
        );
    }

    /// @notice Returns the number of votes used by an account for a given proposal
    function votesUsed(uint256 proposalId, address account) public view returns (uint256) {
        return _votesUsed[proposalId][account];
    }

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    /// @notice Returns true if the account has voted any amount for any nominee in the proposal
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _votesUsed[proposalId][account] > 0;
    }

    /// @notice Returns true, since there is no minimum quorum
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @notice Returns true if votes have been cast for at least K nominees
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        return isNomineesListFull(proposalId);
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
        (address possibleNominee, uint256 votes) = abi.decode(params, (address, uint256));

        require(
            _isCompliantNomineeForMostRecentElection(possibleNominee),
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Nominee is not compliant"
        );

        uint256 prevVotesUsed = _votesUsed[proposalId][account];

        require(
            prevVotesUsed + votes <= availableVotes,
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Cannot use more votes than available"
        );

        _votesUsed[proposalId][account] = prevVotesUsed + votes;

        uint256 weight = votesToWeight(proposalId, block.number, votes);
        _increaseNomineeWeight(proposalId, possibleNominee, weight);

        emit VoteCastForNominee(account, proposalId, possibleNominee, votes, weight);
    }

    function fullWeightVotingDeadline(uint256 proposalId) public view returns (uint256) {
        uint256 startBlock = proposalSnapshot(proposalId);

        return startBlock + _fullWeightDuration;
    }

    /// @notice Returns the weight of a vote for a given proposal, block number, and number of votes.
    /// @dev    Uses a piecewise linear function to determine the weight of a vote.
    function votesToWeight(uint256 proposalId, uint256 blockNumber, uint256 votes)
        public
        view
        returns (uint256)
    {
        // Votes cast before T+14 days will have 100% weight.
        // Votes cast between T+14 days and T+28 days will have weight based on the time of casting,
        // decreasing linearly with time, with 100% weight at T+14 days, decreasing linearly to 0% weight at T+28 days.

        // 7 days full weight, 14 days decreasing weight

        // do i have an off-by-one in here?

        uint256 endBlock = proposalDeadline(proposalId);
        uint256 startBlock = proposalSnapshot(proposalId);

        if (blockNumber <= startBlock || blockNumber > endBlock) {
            return 0;
        }

        uint256 fullWeightVotingDeadline_ = fullWeightVotingDeadline(proposalId);

        if (blockNumber <= fullWeightVotingDeadline_) {
            return votes;
        }

        // slope denominator
        uint256 decreasingWeightDuration = endBlock - fullWeightVotingDeadline_;

        // slope numerator is -votes, slope denominator is decreasingWeightDuration, delta x is blockNumber - fullWeightVotingDeadline_
        // y intercept is votes
        uint256 decreaseAmount =
            WAD * votes / decreasingWeightDuration * (blockNumber - fullWeightVotingDeadline_) / WAD;

        return decreaseAmount >= votes ? 0 : votes - decreaseAmount;
    }

    /// @dev Returns true if the possibleNominee is a compliant nominee for the most recent election
    function _isCompliantNomineeForMostRecentElection(address possibleNominee)
        internal
        view
        virtual
        returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}
