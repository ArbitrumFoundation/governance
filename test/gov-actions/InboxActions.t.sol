// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/pause-inbox/PauseInboxAction.sol" as pause;
import "../../src/gov-action-contracts/pause-inbox/UnpauseInboxAction.sol" as unpause;

import "../util/ActionTestBase.sol";

contract InboxActionsTest is Test, ActionTestBase {
    function testPauseAndUpauseInbox() public {
        pause.PauseInboxAction pauseAction = new pause.PauseInboxAction(inboxGetter);
        bytes memory callData = abi.encodeWithSelector(pause.PauseInboxAction.perform.selector);
        vm.prank(executor0);
        ue.execute(address(pauseAction), callData);
        assertTrue(inbox.paused(), "Inbox not paused");

        unpause.UnpauseInboxAction unpauseAction = new unpause.UnpauseInboxAction(inboxGetter);
        callData = abi.encodeWithSelector(unpause.UnpauseInboxAction.perform.selector);
        vm.prank(executor0);
        ue.execute(address(unpauseAction), callData);
        assertFalse(inbox.paused(), "Inbox paused");
    }
}
