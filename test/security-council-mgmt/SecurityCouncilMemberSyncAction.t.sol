// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "../util/TestUtil.sol";
import "../util/DeployGnosisWithModule.sol";
import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";

import "../../src/security-council-mgmt/SecurityCouncilMemberSyncAction.sol";
import "../../src/security-council-mgmt/interfaces/IGnosisSafe.sol";

contract SecurityCouncilMemberSyncActionTest is Test, DeployGnosisWithModule {
    address admin = address(1111);
    address executor = address(2222);

    address[] owners = [
        address(3333),
        address(4444),
        address(5555),
        address(6666),
        address(7777),
        address(8888),
        address(9999),
        address(10_111),
        address(110_111),
        address(121_111),
        address(131_111),
        address(141_111)
    ];

    struct Contracts {
        UpgradeExecutor upgradeExecutor;
        SecurityCouncilMemberSyncAction action;
        KeyValueStore kvStore;
        address safe;
        uint256 threshold;
    }

    function _deploy(address[] memory initialMembers, uint256 threshold)
        internal
        returns (Contracts memory)
    {
        UpgradeExecutor upgradeExecutor =
            UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](1);
        executors[0] = executor;
        upgradeExecutor.initialize(admin, executors);

        address safe = deploySafe(initialMembers, threshold, address(upgradeExecutor));
        KeyValueStore kvStore = new KeyValueStore();
        SecurityCouncilMemberSyncAction action = new SecurityCouncilMemberSyncAction(kvStore);

        return Contracts(upgradeExecutor, action, kvStore, safe, threshold);
    }

    function updateMembersTest(
        Contracts memory contracts,
        address[] memory newMembers,
        uint256 nonce
    ) internal {
        bytes memory upgradeCallData = abi.encodeWithSelector(
            SecurityCouncilMemberSyncAction.perform.selector, contracts.safe, newMembers, nonce
        );
        vm.prank(executor);
        contracts.upgradeExecutor.execute(address(contracts.action), upgradeCallData);
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(
                newMembers, IGnosisSafe(contracts.safe).getOwners()
            ),
            "updated sucessfully"
        );
        assertEq(
            IGnosisSafe(contracts.safe).getThreshold(), contracts.threshold, "threshold preserved"
        );
    }

    function testNoopUpdate() public {
        address[] memory newMembers = owners;
        address[] memory prevMembers = owners;

        updateMembersTest(_deploy(prevMembers, 9), newMembers, 1);
    }

    function testRemoveOne() public {
        address[] memory newMembers = new address[](11);

        for (uint256 i = 0; i < 11; i++) {
            newMembers[i] = owners[i];
        }
        address[] memory prevMembers = owners;
        updateMembersTest(_deploy(prevMembers, 9), newMembers, 1);
    }

    function testAddOne() public {
        address[] memory prevMembers = new address[](11);

        for (uint256 i = 0; i < 11; i++) {
            prevMembers[i] = owners[i];
        }
        address[] memory newMembers = owners;
        updateMembersTest(_deploy(prevMembers, 9), newMembers, 1);
    }

    function testUpdateCohort() public {
        address[] memory prevMembers = owners;
        address[] memory newMembers = new address[](12);

        address[6] memory newCohort = [
            address(16_111),
            address(18_111),
            address(19_111),
            address(200_111),
            address(210_111),
            address(220_111)
        ];

        for (uint256 i = 0; i < 6; i++) {
            newMembers[i] = newCohort[i];
        }
        for (uint256 i = 6; i < owners.length; i++) {
            newMembers[i] = owners[i];
        }
        updateMembersTest(_deploy(prevMembers, 9), newMembers, 1);
    }

    function testCantDropBelowThreshhold() public {
        address[] memory prevMembers = owners;
        address[] memory newMembers = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            newMembers[i] = owners[i];
        }
        UpgradeExecutor upgradeExecutor =
            UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](1);
        executors[0] = executor;
        upgradeExecutor.initialize(admin, executors);

        address safe = deploySafe(prevMembers, 9, address(upgradeExecutor));

        address action = address(new SecurityCouncilMemberSyncAction(new KeyValueStore()));

        bytes memory upgradeCallData = abi.encodeWithSelector(
            SecurityCouncilMemberSyncAction.perform.selector, safe, newMembers
        );

        // [8], [9], [10] sucessfully get removed, leaving [11]'s previous owner to be [7]; removing [11] reverts as it's below the threshold,
        bytes memory revertingRemoveMemberCall = abi.encodeWithSelector(
            IGnosisSafe.removeOwner.selector, prevMembers[7], prevMembers[11], 9
        );
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberSyncAction.ExecFromModuleError.selector,
                revertingRemoveMemberCall,
                safe
            )
        );
        upgradeExecutor.execute(action, upgradeCallData);
    }

    function testGetPrevOwner() public {
        UpgradeExecutor upgradeExecutor =
            UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](1);
        executors[0] = executor;
        upgradeExecutor.initialize(admin, executors);

        IGnosisSafe safe = IGnosisSafe(deploySafe(owners, 9, address(upgradeExecutor)));

        SecurityCouncilMemberSyncAction action =
            new SecurityCouncilMemberSyncAction(new KeyValueStore());

        assertEq(
            action.SENTINEL_OWNERS(),
            action.getPrevOwner(safe, owners[0]),
            "sentinel owners is first owner's prev owner"
        );

        for (uint256 i = 1; i < owners.length; i++) {
            assertEq(owners[i - 1], action.getPrevOwner(safe, owners[i]), "prev owner as exected");
        }
    }

    function testNonces() public {
        Contracts memory contracts = _deploy(owners, 9);

        uint256 nonceKey = contracts.action.computeKey(uint160(contracts.safe));

        assertEq(
            contracts.kvStore.get(address(contracts.upgradeExecutor), nonceKey),
            0,
            "initial nonce is 0"
        );

        // push through an update
        updateMembersTest(contracts, owners, 2);

        // make sure nonce is updated
        assertEq(
            contracts.kvStore.get(address(contracts.upgradeExecutor), nonceKey), 2, "nonce is 2"
        );

        address[] memory newMembers = new address[](11);
        for (uint256 i = 0; i < 11; i++) {
            newMembers[i] = owners[i];
        }

        // updates with nonce == to prev nonce should fail
        bytes memory upgradeCallData = abi.encodeWithSelector(
            SecurityCouncilMemberSyncAction.perform.selector, contracts.safe, newMembers, 2
        );
        vm.prank(executor);
        contracts.upgradeExecutor.execute(address(contracts.action), upgradeCallData);
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(owners, IGnosisSafe(contracts.safe).getOwners()),
            "old members preserved"
        );

        assertEq(
            contracts.kvStore.get(address(contracts.upgradeExecutor), nonceKey),
            2,
            "nonce is still 2"
        );

        // updates with nonce < prev nonce should fail
        upgradeCallData = abi.encodeWithSelector(
            SecurityCouncilMemberSyncAction.perform.selector, contracts.safe, newMembers, 1
        );
        vm.prank(executor);
        contracts.upgradeExecutor.execute(address(contracts.action), upgradeCallData);
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(owners, IGnosisSafe(contracts.safe).getOwners()),
            "old members preserved"
        );
        assertEq(
            contracts.kvStore.get(address(contracts.upgradeExecutor), nonceKey),
            2,
            "nonce is still 2"
        );

        updateMembersTest(contracts, owners, 1);

        // updates with nonce > prev nonce should succeed
        updateMembersTest(contracts, owners, 3);

        assertEq(
            contracts.kvStore.get(address(contracts.upgradeExecutor), nonceKey), 3, "nonce is now 3"
        );
    }
}
