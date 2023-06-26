// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../util/TestUtil.sol";

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

// todo: these tests aren't very good, but it's something at least
// these can probably be done more systematically
contract AccountRankerUpgradeableTest is Test {
    ConcreteAccountRanker accountRanker;

    function setUp() public {
        accountRanker = new ConcreteAccountRanker();
        accountRanker.initialize();
    }

    function _insertSomeInitialCandidates(uint256 n) internal {
        for (uint160 i = 1; i <= n; i++) {
            accountRanker.increaseNomineeWeight(0, address(i), i * 10);
        }
    }

    function testFirstIncrease() public {
        _insertSomeInitialCandidates(1);
        assertEq(accountRanker.votingWeightReceived(0, address(1)), 10);
        assertEq(accountRanker.topNominees(0)[0], address(1));
    }

    function testListNotFullNewTop() public {
        _insertSomeInitialCandidates(3);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(2));
        assertEq(accountRanker.topNominees(0)[2], address(1));
    }

    function testListNotFullNewBottom() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(4), 1);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(2));
        assertEq(accountRanker.topNominees(0)[2], address(1));
        assertEq(accountRanker.topNominees(0)[3], address(4));
    }

    function testListNotFullNewMiddle() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(4), 15);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(2));
        assertEq(accountRanker.topNominees(0)[2], address(4));
        assertEq(accountRanker.topNominees(0)[3], address(1));
    }

    function testListNotFullMoveBottomToBottom() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(1), 1);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(2));
        assertEq(accountRanker.topNominees(0)[2], address(1));
    }

    function testListNotFullMoveBottomToMiddle() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(1), 15);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(1));
        assertEq(accountRanker.topNominees(0)[2], address(2));
    }

    function testListNotFullMoveBottomToTop() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(1), 100);

        assertEq(accountRanker.topNominees(0)[0], address(1));
        assertEq(accountRanker.topNominees(0)[1], address(3));
        assertEq(accountRanker.topNominees(0)[2], address(2));
    }

    function testListNotFullMoveMiddleToMiddle() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(2), 1);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(2));
        assertEq(accountRanker.topNominees(0)[2], address(1));
    }

    function testListNotFullMoveMiddleToTop() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(2), 100);

        assertEq(accountRanker.topNominees(0)[0], address(2));
        assertEq(accountRanker.topNominees(0)[1], address(3));
        assertEq(accountRanker.topNominees(0)[2], address(1));
    }

    function testListNotFullMoveTopToTop() public {
        _insertSomeInitialCandidates(3);

        accountRanker.increaseNomineeWeight(0, address(3), 1);

        assertEq(accountRanker.topNominees(0)[0], address(3));
        assertEq(accountRanker.topNominees(0)[1], address(2));
        assertEq(accountRanker.topNominees(0)[2], address(1));
    }

    function testFillList() public {
        _insertSomeInitialCandidates(6);

        assertEq(accountRanker.topNominees(0)[0], address(6));
        assertEq(accountRanker.topNominees(0)[1], address(5));
        assertEq(accountRanker.topNominees(0)[2], address(4));
        assertEq(accountRanker.topNominees(0)[3], address(3));
        assertEq(accountRanker.topNominees(0)[4], address(2));
        assertEq(accountRanker.topNominees(0)[5], address(1));
    }

    function testListFullNewNotTopK() public {
        _insertSomeInitialCandidates(6);

        accountRanker.increaseNomineeWeight(0, address(7), 1);

        assertEq(accountRanker.topNominees(0)[0], address(6));
        assertEq(accountRanker.topNominees(0)[1], address(5));
        assertEq(accountRanker.topNominees(0)[2], address(4));
        assertEq(accountRanker.topNominees(0)[3], address(3));
        assertEq(accountRanker.topNominees(0)[4], address(2));
        assertEq(accountRanker.topNominees(0)[5], address(1));
    }

    function testListFullNewBottom() public {
        _insertSomeInitialCandidates(6);

        accountRanker.increaseNomineeWeight(0, address(7), 11);

        assertEq(accountRanker.topNominees(0)[0], address(6));
        assertEq(accountRanker.topNominees(0)[1], address(5));
        assertEq(accountRanker.topNominees(0)[2], address(4));
        assertEq(accountRanker.topNominees(0)[3], address(3));
        assertEq(accountRanker.topNominees(0)[4], address(2));
        assertEq(accountRanker.topNominees(0)[5], address(7));
    }

    function testListFullNewMiddle() public {
        _insertSomeInitialCandidates(6);

        accountRanker.increaseNomineeWeight(0, address(7), 25);

        assertEq(accountRanker.topNominees(0)[0], address(6));
        assertEq(accountRanker.topNominees(0)[1], address(5));
        assertEq(accountRanker.topNominees(0)[2], address(4));
        assertEq(accountRanker.topNominees(0)[3], address(3));
        assertEq(accountRanker.topNominees(0)[4], address(7));
        assertEq(accountRanker.topNominees(0)[5], address(2));
    }

    function testListFullNewTop() public {
        _insertSomeInitialCandidates(6);

        accountRanker.increaseNomineeWeight(0, address(7), 100);

        assertEq(accountRanker.topNominees(0)[0], address(7));
        assertEq(accountRanker.topNominees(0)[1], address(6));
        assertEq(accountRanker.topNominees(0)[2], address(5));
        assertEq(accountRanker.topNominees(0)[3], address(4));
        assertEq(accountRanker.topNominees(0)[4], address(3));
        assertEq(accountRanker.topNominees(0)[5], address(2));
    }
}
