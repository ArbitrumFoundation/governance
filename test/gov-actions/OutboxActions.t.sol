// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../util/TestUtil.sol";

import "../../src/gov-action-contracts/set-outbox/BridgeAddOutboxesAction.sol" as add;
import "../../src/gov-action-contracts/set-outbox/BridgeRemoveAllOutboxesAction.sol" as removeall;
import "../../src/gov-action-contracts/set-outbox/BridgeRemoveOutboxesAction.sol" as remove;
import "../util/ActionTestBase.sol";

contract OutboxActionsTest is Test, ActionTestBase {
    function testAddOutbxesAction() public {
        addOutboxes();
        for (uint256 i = 0; i < outboxesToAdd.length; i++) {
            assertTrue(bridge.allowedOutboxes(outboxesToAdd[i]), "Outbox not added");
        }
    }

    function testCantReAddOutbox() public {
        addOutboxes();
        add.BridgeAddOutboxesAction action = new add.BridgeAddOutboxesAction(bridgeGetter);
        bytes memory data =
            abi.encodeWithSelector(add.BridgeAddOutboxesAction.perform.selector, outboxesToAdd);
        vm.prank(executor0);
        vm.expectRevert("BridgeAddOutboxesAction: outbox already allowed");
        ue.execute(address(action), data);
    }

    function testCantAddEOA() public {
        addOutboxes();
        add.BridgeAddOutboxesAction action = new add.BridgeAddOutboxesAction(bridgeGetter);
        bytes memory data = abi.encodeWithSelector(
            add.BridgeAddOutboxesAction.perform.selector, [address(12_345_678)]
        );
        vm.prank(executor0);
        vm.expectRevert("UpgradeExecutor: inner delegate call failed without reason");
        ue.execute(address(action), data);
    }

    function testRemoveOutboxes() public {
        addOutboxes();
        remove.BridgeRemoveOutboxesAction action =
            new remove.BridgeRemoveOutboxesAction(bridgeGetter);
        bytes memory data = abi.encodeWithSelector(
            remove.BridgeRemoveOutboxesAction.perform.selector, outboxesToRemove
        );
        vm.prank(executor0);
        ue.execute(address(action), data);
        for (uint256 i = 0; i < outboxesToRemove.length; i++) {
            assertTrue(!bridge.allowedOutboxes(outboxesToAdd[i]), "Outbox still allowed");
        }
    }

    function testRemoveAllOutboxes() public {
        addOutboxes();
        removeall.BridgeRemoveAllOutboxesAction action =
            new removeall.BridgeRemoveAllOutboxesAction(bridgeGetter);
        bytes memory data =
            abi.encodeWithSelector(removeall.BridgeRemoveAllOutboxesAction.perform.selector);
        vm.prank(executor0);
        ue.execute(address(action), data);

        for (uint256 i = 0; i < outboxesToAdd.length; i++) {
            assertTrue(!bridge.allowedOutboxes(outboxesToAdd[i]), "Outbox still allowed");
        }
    }

    function addOutboxes() public {
        add.BridgeAddOutboxesAction action = new add.BridgeAddOutboxesAction(bridgeGetter);
        bytes memory data =
            abi.encodeWithSelector(add.BridgeAddOutboxesAction.perform.selector, outboxesToAdd);
        vm.prank(executor0);
        ue.execute(address(action), data);
    }
}
