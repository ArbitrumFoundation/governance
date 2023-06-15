// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

/// @title AccountRankerUpgradeable
/// @notice Keeps track of the top K nominees for a given round (proposalId) and their weights
abstract contract AccountRankerUpgradeable is Initializable {
    /// @dev max number of nominees to track (6)
    uint256 private maxNominees;

    /// @dev round => list of top nominees in descending order by weight
    mapping(uint256 => address[]) private _nominees;

    /// @dev round => account => weight.
    ///      weight is the voting weight cast for the account
    mapping(uint256 => mapping(address => uint256)) private _weights;

    function __AccountRanker_init(uint256 _maxNominees) internal onlyInitializing {
        maxNominees = _maxNominees;
    }

    /// @dev returns the list of top nominees for a given round
    function _getTopNominees(uint256 round) internal view returns (address[] memory) {
        return _nominees[round];
    }

    /// @dev returns true if the list of top nominees is full for a given round
    function _isNomineesListFull(uint256 round) internal view returns (bool) {
        return _nominees[round].length == maxNominees;
    }

    /// @dev returns the weight of an account in a given round
    function _getWeight(uint256 round, address account) internal view returns (uint256) {
        return _weights[round][account];
    }

    /// @dev increases the weight of an account in a given round. 
    ///      updates the list of top nominees for that round if necessary.
    function _increaseNomineeWeight(uint256 round, address account, uint256 weightToAdd) internal {
        address[] storage nomineesPtr = _nominees[round];
        mapping(address => uint256) storage weightsPtr = _weights[round];

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
        if (previousIndexOfAccount == type(uint256).max && nomineesPtr.length < maxNominees) {
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
        while(true) {
            address nominee = nomineesPtr[j];
            if (newWeight > weightsPtr[nominee]) {
                // the account's weight is greater than the nominee we are looking at
                // we should move nominee down the list by one (unless they are already at the bottom)
                if (j != nomineesPtr.length - 1) {
                    nomineesPtr[j + 1] = nominee;
                }
            }
            else {
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
abstract contract SecurityCouncilMemberElectionGovernorCountingUpgradeable is Initializable, GovernorUpgradeable, AccountRankerUpgradeable {
    uint256 private constant WAD = 1e18;

    /// @notice Numerator for the duration of full weight voting
    uint256 public fullWeightDurationNumerator; // = 1 (7 days)
    /// @notice Numerator for the duration of decreasing weight voting
    uint256 public decreasingWeightDurationNumerator; // = 2 (14 days)
    /// @notice Denominator for the total duration of voting
    uint256 public durationDenominator; // = 3 (21 days)

    /// @notice Keeps track of the number of votes used by each account for each proposal
    mapping(uint256 => mapping(address => uint256)) public votesUsed;

    /// @param _maxNominees The maximum number of nominees to track
    /// @param _fullWeightDurationNumerator Numerator for the duration of full weight voting
    /// @param _decreasingWeightDurationNumerator Numerator for the duration of decreasing weight voting
    /// @param _durationDenominator Denominator for the total duration of voting
    function __SecurityCouncilMemberElectionGovernorCounting_init(
        uint256 _maxNominees,
        uint256 _fullWeightDurationNumerator,
        uint256 _decreasingWeightDurationNumerator,
        uint256 _durationDenominator
    ) internal onlyInitializing {
        __AccountRanker_init(_maxNominees);

        fullWeightDurationNumerator = _fullWeightDurationNumerator;
        decreasingWeightDurationNumerator = _decreasingWeightDurationNumerator;
        durationDenominator = _durationDenominator;
    }

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    /// @notice Returns true if the account has voted any amount for any nominee in the proposal
    function hasVoted(
        uint256 proposalId, 
        address account
    ) 
        public 
        view 
        override
        returns (bool) 
    {
        return votesUsed[proposalId][account] > 0;
    }

    /// @notice Returns true, since there is no minimum quorum
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @notice Returns true if votes have been cast for at least K nominees
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        return _isNomineesListFull(proposalId);
    }
    
    /// @notice Register a vote by some account for a proposal. 
    /// @dev    Reverts if the account does not have enough votes.
    ///         Reverts if the possibleNominee is not a compliant nominee of the most recent election.
    ///         Weight of the vote is determined using the votesToWeight function.
    ///         Finally, the weight of the vote is added to the weight of the possibleNominee and the top K nominees are updated if necessary.
    /// @param  proposalId The id of the proposal
    /// @param  account The account that is voting
    /// @param  weight The amount of votes that account had at the time of the proposal snapshot
    /// @param  params Abi encoded (address possibleNominee, uint256 votes) 
    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        (address possibleNominee, uint256 votes) = abi.decode(params, (address, uint256));

        require(_isCompliantNomineeForMostRecentElection(possibleNominee), "Nominee is not compliant");

        uint256 prevVotesUsed = votesUsed[proposalId][account];

        require(prevVotesUsed + votes <= weight, "Cannot use more votes than available");

        votesUsed[proposalId][account] = prevVotesUsed + votes;

        _increaseNomineeWeight(proposalId, possibleNominee, votesToWeight(proposalId, block.number, votes));
    }

    /// @notice Returns the weight of a vote for a given proposal, block number, and number of votes.
    /// @dev    Uses a piecewise linear function to determine the weight of a vote.
    function votesToWeight(uint256 proposalId, uint256 blockNumber, uint256 votes) public view returns (uint256) {
        // Votes cast before T+14 days will have 100% weight. 
        // Votes cast between T+14 days and T+28 days will have weight based on the time of casting, 
        // decreasing linearly with time, with 100% weight at T+14 days, decreasing linearly to 0% weight at T+28 days.

        // 7 days full weight, 14 days decreasing weight

        // do i have an off-by-one in here?

        uint256 startBlock = proposalSnapshot(proposalId);
        uint256 endBlock = proposalDeadline(proposalId);

        uint256 duration = endBlock - startBlock;

        if (blockNumber <= startBlock || blockNumber > endBlock) {
            return 0;
        }

        uint256 fullWeightDuration = WAD * fullWeightDurationNumerator / durationDenominator * duration / WAD;

        uint256 decreasingWeightStartBlock = startBlock + fullWeightDuration;

        if (blockNumber <= decreasingWeightStartBlock) {
            return votes;
        }


        // slope denominator
        uint256 decreasingWeightDuration = WAD * decreasingWeightDurationNumerator / durationDenominator * duration / WAD;

        // slope numerator is -votes

        uint256 decreaseAmount = WAD * votes / decreasingWeightDuration * (blockNumber - decreasingWeightStartBlock) / WAD;

        if (decreaseAmount >= votes) {
            return 0;
        }

        return votes - decreaseAmount;
    }

    /// @dev Returns true if the possibleNominee is a compliant nominee for the most recent election
    function _isCompliantNomineeForMostRecentElection(address possibleNominee) internal view virtual returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}