// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import "./util/TestUtil.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "forge-std/Test.sol";

contract Setter {
    uint256 public val = 0;
    address public lastSender;

    function setVal(uint256 _val) public {
        val = _val;
        lastSender = msg.sender;
    }
}

contract SetterUpgrade {
    function upgrade(address setter, uint256 val) public {
        Setter(setter).setVal(val);
    }
}

contract AccessControlUpgrader {
    function grantRole(address target, bytes32 role, address account) public {
        AccessControlUpgradeable(target).grantRole(role, account);
    }
}

contract UpgradeExecutorTest is Test {
    address executor0 = address(138);
    address executor1 = address(139);
    address nobody = address(140);
    address executor2 = address(141);

    function deployAndInit() internal returns (UpgradeExecutor) {
        UpgradeExecutor ue = UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](2);
        executors[0] = executor0;
        executors[1] = executor1;
        ue.initialize(address(ue), executors);
        return ue;
    }

    function testInit() external {
        UpgradeExecutor ue = deployAndInit();

        assertEq(ue.hasRole(ue.EXECUTOR_ROLE(), executor0), true, "Executor 0");
        assertEq(ue.hasRole(ue.EXECUTOR_ROLE(), executor1), true, "Executor 1");
        assertEq(ue.hasRole(ue.ADMIN_ROLE(), address(ue)), true, "Executor 1");
        assertEq(ue.getRoleAdmin(ue.ADMIN_ROLE()), ue.ADMIN_ROLE(), "admin admin");
        assertEq(ue.getRoleAdmin(ue.EXECUTOR_ROLE()), ue.ADMIN_ROLE(), "executor admin");
    }

    function testInitFailsZeroAdmin() external {
        UpgradeExecutor ue = UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](2);
        executors[0] = executor0;
        executors[1] = executor1;

        vm.expectRevert("UpgradeExecutor: zero admin");
        ue.initialize(address(0), executors);
    }

    function testExecute() external {
        UpgradeExecutor ue = deployAndInit();
        Setter setter = new Setter();
        SetterUpgrade se = new SetterUpgrade();

        uint256 val = 25;
        bytes memory data = abi.encodeWithSelector(se.upgrade.selector, address(setter), val);

        assertEq(setter.val(), 0, "Val before");
        assertEq(setter.lastSender(), address(0), "Sender before");

        vm.prank(executor0);
        ue.execute(address(se), data);

        assertEq(setter.val(), val, "Val after");
        assertEq(setter.lastSender(), address(ue), "Sender after");
    }

    function testCantExecuteEOA() external {
        UpgradeExecutor ue = deployAndInit();
        bytes memory data;

        vm.prank(executor0);
        vm.expectRevert("Address: delegate call to non-contract");
        ue.execute(address(111), data);
    }

    function roleError(address account, bytes32 role) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(account), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(role), 32)
            )
        );
    }

    function testExecuteFailsForAdmin() external {
        UpgradeExecutor ue = deployAndInit();
        Setter setter = new Setter();
        SetterUpgrade se = new SetterUpgrade();

        uint256 val = 25;
        bytes memory data = abi.encodeWithSelector(se.upgrade.selector, address(setter), val);

        vm.expectRevert(bytes(roleError(address(ue), ue.EXECUTOR_ROLE())));
        vm.prank(address(ue));
        ue.execute(address(se), data);
    }

    function testExecuteFailsForNobody() external {
        UpgradeExecutor ue = deployAndInit();
        Setter setter = new Setter();
        SetterUpgrade se = new SetterUpgrade();

        uint256 val = 25;
        bytes memory data = abi.encodeWithSelector(se.upgrade.selector, address(setter), val);

        vm.expectRevert(bytes(roleError(nobody, ue.EXECUTOR_ROLE())));
        vm.prank(nobody);
        ue.execute(address(se), data);
    }

    function testAdminCanChangeExecutor() external {
        UpgradeExecutor ue = deployAndInit();
        AccessControlUpgrader ae = new AccessControlUpgrader();

        bytes memory data = abi.encodeWithSelector(
            ae.grantRole.selector, address(ue), ue.EXECUTOR_ROLE(), executor2
        );

        assertEq(ue.hasRole(ue.EXECUTOR_ROLE(), executor2), false, "executor 2 before");
        vm.prank(executor1);
        ue.execute(address(ae), data);

        assertEq(ue.hasRole(ue.EXECUTOR_ROLE(), executor2), true, "executor 2 before");
    }
}
