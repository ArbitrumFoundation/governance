// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../util/ActionTestBase.sol";
// import this way to avoid naming collision
import "../../src/gov-action-contracts/sequencer/SetSequencerInboxMaxTimeVariationAction.sol" as
    action;

contract SetSequencerInboxMaxTimeVariationActionTest is Test, ActionTestBase {
    uint256 public newDelayBlocks = 123;
    uint256 public newFutureBlocks = 456;
    uint256 public newDelaySeconds = 789;
    uint256 public newFutureSeconds = 10_112;

    function testSetMaxTimeVariation() public {
        action.SetSequencerInboxMaxTimeVariationAction setSequencerInboxMaxTimeVariationAction =
        new action.SetSequencerInboxMaxTimeVariationAction(
            addressRegistry, newDelayBlocks, newFutureBlocks, newDelaySeconds, newFutureSeconds
        );
        bytes memory callData =
            abi.encodeWithSelector(action.SetSequencerInboxMaxTimeVariationAction.perform.selector);
        vm.prank(executor0);
        ue.execute(address(setSequencerInboxMaxTimeVariationAction), callData);
        (uint256 delayBlocks, uint256 futureBlocks, uint256 delaySeconds, uint256 futureSeconds) =
            si.maxTimeVariation();
        assertEq(delayBlocks, newDelayBlocks, "delay blocks set");
        assertEq(futureBlocks, newFutureBlocks, "future blocks set");
        assertEq(delaySeconds, newDelaySeconds, "delay seconds set");
        assertEq(futureSeconds, newFutureSeconds, "future seconds set");
    }
}
