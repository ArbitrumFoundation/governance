// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L1GovernanceFactory.sol";
import "./util/InboxMock.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L1GovernanceFactoryTest is Test {
    address l2Timelock = address(10_001);
    address bridge = address(10_002);
    address factoryOwner = address(10_003);
    address l1SecurityCouncil = address(10_004);
    address someRando = address(10_005);
    uint256 minDelay = 42;
    UpgradeExecutor upgradeExecutorLogic = new UpgradeExecutor();

    function testL1GovernanceFactory() external {
        vm.prank(factoryOwner);
        L1GovernanceFactory l1GovernanceFactory = new L1GovernanceFactory();
        InboxMock inbox = new InboxMock(bridge);

        vm.prank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        l1GovernanceFactory.deployStep2(
            address(upgradeExecutorLogic), minDelay, address(inbox), l2Timelock, l1SecurityCouncil
        );

        vm.startPrank(factoryOwner);
        (L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin, UpgradeExecutor executor) =
        l1GovernanceFactory.deployStep2(
            address(upgradeExecutorLogic), minDelay, address(inbox), l2Timelock, l1SecurityCouncil
        );
        vm.expectRevert("L1GovernanceFactory: already executed");
        l1GovernanceFactory.deployStep2(
            address(upgradeExecutorLogic), minDelay, address(inbox), l2Timelock, l1SecurityCouncil
        );

        assertGt(address(timelock).code.length, 0, "timelock deployed");
        assertEq(timelock.governanceChainInbox(), address(inbox), "timelock inbox set");
        assertEq(timelock.l2Timelock(), l2Timelock, "timelock l2Timelock set");
        assertEq(timelock.getMinDelay(), minDelay, "timelock minDelay set");
        // address[] memory proposers;
        address[] memory executors;
        vm.expectRevert("Initializable: contract is already initialized");
        timelock.initialize(minDelay, executors, address(inbox), l2Timelock);

        assertGt(address(proxyAdmin).code.length, 0, "proxyAdmin deployed");

        assertGt(address(executor).code.length, 0, "executor deployed");
        bytes32 executorRole = executor.EXECUTOR_ROLE();
        assertTrue(
            executor.hasRole(executorRole, l1SecurityCouncil), "l1SecurityCouncil is executor"
        );
        assertTrue(executor.hasRole(executorRole, address(timelock)), "timelock is executor");
        bytes32 adminRole = executor.ADMIN_ROLE();
        assertTrue(executor.hasRole(adminRole, address(executor)), "executor is admin to itself");

        assertTrue(
            timelock.hasRole(timelock.CANCELLER_ROLE(), l1SecurityCouncil),
            "l1SecurityCouncil is canceler"
        );
        vm.stopPrank();

        assertEq(proxyAdmin.owner(), address(executor), "L1 Executor owns L1 proxyAdmin");
        vm.startPrank(address(proxyAdmin));
        assertEq(
            TransparentUpgradeableProxy(payable(address(executor))).admin(),
            address(proxyAdmin),
            "L1 proxyAdmin is admin of executor"
        );
        assertEq(
            TransparentUpgradeableProxy(payable(address(timelock))).admin(),
            address(proxyAdmin),
            "L1 proxyAdmin is admin of timelock"
        );

        vm.stopPrank();
    }

    function deployAndInit()
        internal
        returns (L1GovernanceFactory, L1ArbitrumTimelock, UpgradeExecutor)
    {
        vm.prank(factoryOwner);
        L1GovernanceFactory l1GovernanceFactory = new L1GovernanceFactory();
        InboxMock inbox = new InboxMock(bridge);

        vm.startPrank(factoryOwner);
        (L1ArbitrumTimelock timelock,, UpgradeExecutor executor) = l1GovernanceFactory.deployStep2(
            address(upgradeExecutorLogic), minDelay, address(inbox), l2Timelock, l1SecurityCouncil
        );
        vm.stopPrank();

        return (l1GovernanceFactory, timelock, executor);
    }

    function testSetMinDelayRevertsForCoreAddress() external {
        (, L1ArbitrumTimelock coreTimelock,) = deployAndInit();

        uint256 oldMinDelay = coreTimelock.getMinDelay();

        bytes32 adminRole = coreTimelock.TIMELOCK_ADMIN_ROLE();
        vm.prank(address(coreTimelock));
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(address(coreTimelock)), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(adminRole), 32)
            )
        );
        coreTimelock.updateDelay(oldMinDelay + 1);
    }

    function testSetMinDelay() external {
        (, L1ArbitrumTimelock coreTimelock, UpgradeExecutor executor) = deployAndInit();

        uint256 oldMinDelay = coreTimelock.getMinDelay();

        vm.prank(address(executor));
        coreTimelock.updateDelay(oldMinDelay + 1);
        assertEq(coreTimelock.getMinDelay(), oldMinDelay + 1, "Min delay not updated");
    }
}
