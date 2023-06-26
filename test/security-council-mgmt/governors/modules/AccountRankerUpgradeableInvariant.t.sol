// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import
    "../../../../src/security-council-mgmt/governors/modules/SecurityCouncilMemberElectionGovernorCountingUpgradeable.sol";

contract ConcreteAccountRanker is AccountRankerUpgradeable {
    function initialize() public initializer {
        __AccountRanker_init(6);
    }

    function increaseNomineeWeight(uint256 proposalId, address account, uint256 weightToAdd)
        public
    {
        _increaseNomineeWeight(proposalId, account, weightToAdd);
    }
}

contract AccountRankerInvariantHandler {
    ConcreteAccountRanker public accountRanker;

    address[] public accounts;
    uint256 public accountsLength;
    mapping(address => bool) public accountUsed;

    constructor() {
        accountRanker = new ConcreteAccountRanker();
        accountRanker.initialize();
    }

    function increaseNomineeWeight(address account, uint64 weightToAdd) public {
        if (!accountUsed[account]) {
            accounts.push(account);
            accountsLength++;
            accountUsed[account] = true;
        }
        accountRanker.increaseNomineeWeight(0, account, weightToAdd);
    }
}

contract AccountRankerInvariantTest is DSTest, StdInvariant {
    AccountRankerInvariantHandler handler;

    function setUp() public {
        handler = new AccountRankerInvariantHandler();
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 50
    function invariant_deep() public view {
        _testInvariantsHold();
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 5
    function invariant_shallow() public view {
        _testInvariantsHold();
    }

    function _testInvariantsHold() internal view {
        ConcreteAccountRanker accountRanker = handler.accountRanker();
        address[] memory topNominees = accountRanker.topNominees(0);

        // assert accountRanker.topNominees.length == min(6, handler.accounts.length)
        // (basically saying that if there were less than or equal to 6 accounts added, they should all be in the top k)
        uint256 min = handler.accountsLength() < 6 ? handler.accountsLength() : 6;
        require(topNominees.length == min);

        if (min == 0) {
            return;
        }

        // make sure the top k nominees are sorted
        for (uint256 i = 1; i < topNominees.length; i++) {
            require(
                accountRanker.votingWeightReceived(0, topNominees[i - 1]) >=
                    accountRanker.votingWeightReceived(0, topNominees[i])
            );
        }
        
        // make sure the top k nominees are all in accounts
        // (probably not necessary)
        for (uint256 i = 0; i < topNominees.length; i++) {
            require(handler.accountUsed(topNominees[i]));
        }

        // make sure that all accounts that aren't in the top k have weight less than the kth account
        uint256 leastWeight = accountRanker.votingWeightReceived(0, topNominees[min - 1]);
        for (uint256 i = 0; i < handler.accountsLength(); i++) {
            address account = handler.accounts(i);
            bool isTopNominee = false;
            for (uint256 j = 0; j < topNominees.length; j++) {
                if (topNominees[j] == account) {
                    isTopNominee = true;
                    break;
                }
            }
            if (!isTopNominee) {
                require(accountRanker.votingWeightReceived(0, account) <= leastWeight);
            }
        }
    }
}