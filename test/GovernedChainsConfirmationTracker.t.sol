// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./util/RollupMock.sol";
import "forge-std/Test.sol";

contract GovernedChainsConfirmationTrackerTest is Test {
    address owner = address(1111);
    address rando = address(1112);
    uint256 initialBlock = 10;
    GovernedChainsConfirmationTracker governedChainsConfirmationTracker;
    bytes32[2] rollup0assertionHashes;
    bytes32[2] rollup1assertionHashes;

    function setUp() external {
        rollup0assertionHashes[0] = keccak256("100");
        rollup0assertionHashes[1] = keccak256("200");
        rollup1assertionHashes[0] = keccak256("300");
        rollup1assertionHashes[1] = keccak256("400");

        GovernedChainsConfirmationTracker.ChainInfo[] memory chains =
            new GovernedChainsConfirmationTracker.ChainInfo[](2);
        chains[0] = GovernedChainsConfirmationTracker.ChainInfo({
            chainId: 123,
            rollupAddress: address(new RollupMock()),
            messagesConfirmedParentBlock: initialBlock
        });

        chains[1] = GovernedChainsConfirmationTracker.ChainInfo({
            chainId: 456,
            rollupAddress: address(new RollupMock()),
            messagesConfirmedParentBlock: initialBlock
        });
        governedChainsConfirmationTracker = new GovernedChainsConfirmationTracker(chains, owner);
    }

    function testCantUseSameAssertionHash() external {
        bytes32[2] memory assertionHashes;
        assertionHashes[0] = keccak256("100");
        assertionHashes[1] = keccak256("100");
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernedChainsConfirmationTracker.DuplicateAssertion.selector, assertionHashes[0]
            )
        );
        governedChainsConfirmationTracker.getMessagesConfirmedParentChainBlock(0, assertionHashes);
    }

    function testUnconfirmedAssertionReverts() external {
        bytes32[2] memory assertionHashes;
        assertionHashes[0] = keccak256("UNCONFIRMED");
        assertionHashes[1] = keccak256("100");
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernedChainsConfirmationTracker.AssertionNotConfirmed.selector,
                assertionHashes[0],
                AssertionStatus.NoAssertion
            )
        );
        governedChainsConfirmationTracker.getMessagesConfirmedParentChainBlock(0, assertionHashes);
    }

    function testReturnsFalseAtSetup() external {
        assertFalse(
            governedChainsConfirmationTracker.allChildChainMessagesConfirmed(initialBlock + 1),
            "all child confirmed returns false"
        );
    }

    function testSingleSuccessfulUpdateWorks() external {
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            0, rollup0assertionHashes
        );
        GovernedChainsConfirmationTracker.ChainInfo memory chainInfo =
            governedChainsConfirmationTracker.getChainInfo(0);
        assertEq(chainInfo.messagesConfirmedParentBlock, 99, "chain 0 updated");
        assertFalse(
            governedChainsConfirmationTracker.allChildChainMessagesConfirmed(99),
            "not all confirmed"
        );
    }

    function testDoubleSuccessfulUpdatesSameChainWorks() external {
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            0, rollup0assertionHashes
        );
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            0, rollup1assertionHashes
        );

        GovernedChainsConfirmationTracker.ChainInfo memory chainInfo =
            governedChainsConfirmationTracker.getChainInfo(0);
        assertEq(chainInfo.messagesConfirmedParentBlock, 299, "chain 0 updated");
    }

    function testTwoSuccessfulUpdatesReturnTrue() external {
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            0, rollup0assertionHashes
        );
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            1, rollup1assertionHashes
        );
        assertTrue(
            governedChainsConfirmationTracker.allChildChainMessagesConfirmed(99),
            "confimred at block after initiated block"
        );
        assertFalse(
            governedChainsConfirmationTracker.allChildChainMessagesConfirmed(100),
            "not confirmed at initiated at block"
        );
    }

    function testCantUpdateBackwards() external {
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            0, rollup1assertionHashes
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernedChainsConfirmationTracker.NotAdvanced.selector, 299, 99, 123
            )
        );
        governedChainsConfirmationTracker.updateMessagesConfirmedParentChainBlock(
            0, rollup0assertionHashes
        );
    }

    function testOwnerCanForceUpdate() external {
        vm.prank(owner);
        governedChainsConfirmationTracker.forceUpdateMessagesConfirmedParentBlock(0, 1000);
        GovernedChainsConfirmationTracker.ChainInfo memory chainInfo =
            governedChainsConfirmationTracker.getChainInfo(0);
        assertEq(chainInfo.messagesConfirmedParentBlock, 1000, "force update works");
    }

    function testRandoCantForceUpdate() external {
        vm.prank(rando);
        vm.expectRevert();
        governedChainsConfirmationTracker.forceUpdateMessagesConfirmedParentBlock(0, 1000);
    }
}
