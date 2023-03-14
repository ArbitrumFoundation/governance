// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/sequencer/AddSequencerAction.sol" as add;
import "../../src/gov-action-contracts/sequencer/RemoveSequencerAction.sol" as remove;

import "../util/ActionTestBase.sol";

contract SequencerActionsTest is Test, ActionTestBase {
    function testAddAndRemoveSequencer() public {
        add.AddSequencerAction addAction = new add.AddSequencerAction(sequencerInboxGetter);
        address newSequencer = address(56_789);
        bytes memory callData =
            abi.encodeWithSelector(add.AddSequencerAction.perform.selector, newSequencer);
        vm.prank(executor0);
        ue.execute(address(addAction), callData);
        assertTrue(si.isBatchPoster(newSequencer), "New sequencer isn't batch poster");

        remove.RemoveSequencerAction removeAction =
            new remove.RemoveSequencerAction(sequencerInboxGetter);
        callData =
            abi.encodeWithSelector(remove.RemoveSequencerAction.perform.selector, newSequencer);
        vm.prank(executor0);
        ue.execute(address(removeAction), callData);

        assertFalse(si.isBatchPoster(newSequencer), "New sequencer is still batch poster");
    }

    function testCantAddZeroAddress() public {
        add.AddSequencerAction addAction = new add.AddSequencerAction(sequencerInboxGetter);
        address newSequencer = address(0);
        bytes memory callData =
            abi.encodeWithSelector(add.AddSequencerAction.perform.selector, newSequencer);
        vm.prank(executor0);
        vm.expectRevert("SequencerActionLib sequencer param cannot be address(0)");
        ue.execute(address(addAction), callData);
    }
}
