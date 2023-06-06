// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

// provides a way to keep track of the top K candidates for a given round
abstract contract AccountRankerUpgradeable is Initializable {
    // max number of candidates to track
    uint256 private maxCandidates;

    // maps round to list of top candidates
    mapping(uint256 => address[]) private _candidates;

    // maps round to map of account to weight
    mapping(uint256 => mapping(address => uint256)) private _weights;

    function __AccountRanker_init(uint256 _maxCandidates) internal onlyInitializing {
        maxCandidates = _maxCandidates;
    }

    function _getTopCandidates(uint256 round) internal view returns (address[] memory) {
        return _candidates[round];
    }

    function _isCandidatesListFull(uint256 round) internal view returns (bool) {
        return _candidates[round].length == maxCandidates;
    }

    function _getWeight(uint256 round, address account) internal view returns (uint256) {
        return _weights[round][account];
    }

    // increase the weight of an account in a given round
    // update the list of top candidates for that round if necessary
    function _increaseCandidateWeight(uint256 round, address account, uint256 weightToAdd) internal {
        address[] storage candidatesPtr = _candidates[round];
        mapping(address => uint256) storage weightsPtr = _weights[round];

        uint256 oldWeight = weightsPtr[account];
        uint256 newWeight = oldWeight + weightToAdd;

        // update the weight of account
        weightsPtr[account] = newWeight;

        // check to see if the account is already in the top K
        uint256 previousIndexOfAccount = type(uint256).max;
        // todo: can probably just skip this loop if the oldWeight is less than the weight of the last candidate
        for (uint256 i = 0; i < candidatesPtr.length; i++) {
            if (candidatesPtr[i] == account) {
                previousIndexOfAccount = i;
                break;
            }
        }

        // if the array is not max length yet, and account is not already in the list, just add the account to the end
        if (previousIndexOfAccount == type(uint256).max && candidatesPtr.length < maxCandidates) {
            candidatesPtr.push(account);
            previousIndexOfAccount = candidatesPtr.length - 1;
        }
        // if the array is max length already, and account is not already in the list, set the previousIndexOfAccount to the length of the array
        else if (previousIndexOfAccount == type(uint256).max) {
            previousIndexOfAccount = candidatesPtr.length;
        }

        if (previousIndexOfAccount == 0) {
            // account is already at the top of the list
            return;
        }

        // start with the account's index - 1 and move to the left, shifting things down to the right until we find the appropriate spot
        uint256 j = previousIndexOfAccount - 1;
        while(true) {
            address candidate = candidatesPtr[j];
            if (newWeight > weightsPtr[candidate]) {
                // the account's weight is greater than the candidate we are looking at
                // we should move candidate down the list by one (unless they are already at the bottom)
                if (j != candidatesPtr.length - 1) {
                    candidatesPtr[j + 1] = candidate;
                }
            }
            else {
                // the account's weight is less than or equal to the candidate we are looking at
                // if we are at the bottom of the list, then return
                // if we are not, then we should place the account just to the right of the candidate we are looking at and return
                if (j != candidatesPtr.length - 1) {
                    candidatesPtr[j + 1] = account;
                }
                return;
            }

            if (j == 0) break;
            j--;
        }

        // if we get here, we have passed the end of the list, so we should place the account at the beginning
        candidatesPtr[0] = account;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}

abstract contract SecurityCouncilMemberElectionGovernorCountingUpgradeable is Initializable, GovernorUpgradeable, AccountRankerUpgradeable {
    uint256 private constant WAD = 1e18;

    uint256 public fullWeightDurationNumerator; // = 1 (7 days)
    uint256 public decreasingWeightDurationNumerator; // = 2 (14 days)
    uint256 public durationDenominator; // = 3 (21 days)

    // proposalId => voter => tokens used
    mapping(uint256 => mapping(address => uint256)) public tokensUsed;

    function __SecurityCouncilMemberElectionGovernorCounting_init(
        uint256 _maxCandidates,
        uint256 _fullWeightDurationNumerator,
        uint256 _decreasingWeightDurationNumerator,
        uint256 _durationDenominator
    ) internal onlyInitializing {
        __AccountRanker_init(_maxCandidates);

        fullWeightDurationNumerator = _fullWeightDurationNumerator;
        decreasingWeightDurationNumerator = _decreasingWeightDurationNumerator;
        durationDenominator = _durationDenominator;
    }

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    // returns true if the account has voted any amount for any nominee
    function hasVoted(
        uint256 proposalId, 
        address account
    ) 
        public 
        view 
        override
        returns (bool) 
    {
        return tokensUsed[proposalId][account] > 0;
    }

    // there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    // the vote succeeds if the top K candidates have been selected
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        return _isCandidatesListFull(proposalId);
    }
    
    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        (address nominee, uint256 tokens) = abi.decode(params, (address, uint256));

        require(_isCompliantNominee(proposalId, nominee), "Nominee is not compliant");

        uint256 prevTokensUsed = tokensUsed[proposalId][account];

        require(prevTokensUsed + tokens <= weight, "Cannot use more tokens than available");

        tokensUsed[proposalId][account] = prevTokensUsed + tokens;
        _increaseCandidateWeight(proposalId, nominee, tokensToWeight(proposalId, block.number, tokens));
    }

    function tokensToWeight(uint256 proposalId, uint256 blockNumber, uint256 tokens) public view returns (uint256) {
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
            return tokens;
        }


        // slope denominator
        uint256 decreasingWeightDuration = WAD * decreasingWeightDurationNumerator / durationDenominator * duration / WAD;

        // slope numerator is -tokens

        uint256 decreaseAmount = WAD * tokens / decreasingWeightDuration * (blockNumber - decreasingWeightStartBlock) / WAD;

        if (decreaseAmount >= tokens) {
            return 0;
        }

        return tokens - decreaseAmount;
    }

    function _isCompliantNominee(uint256 proposalId, address nominee) internal view virtual returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}