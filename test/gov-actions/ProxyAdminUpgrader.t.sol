// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../util/TestUtil.sol";

import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import
    "../../src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/ProxyUpgradeAndCallAction.sol";
import "../../src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/ProxyUpgradeAction.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract Dummy {
    event SomeEvent();

    function someFunction() public {
        emit SomeEvent();
    }
}

contract ProxyUpgradeAndCallActionTest is Test {
    address executor0 = address(138);
    address executor1 = address(139);
    UpgradeExecutor ue;

    address upgraderAndCaller;
    address upgrader;
    ProxyAdmin admin;
    address proxy;

    bytes32 constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event SomeEvent();

    function setUp() public {
        // Setup UpgradeExecutor
        ue = UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](2);
        executors[0] = executor0;
        executors[1] = executor1;
        ue.initialize(address(ue), executors);
        vm.deal(executor0, 1_000_000_000_000_000_000);
        vm.deal(executor1, 1_000_000_000_000_000_000);

        // Setup
        admin = new ProxyAdmin();
        admin.transferOwnership(address(ue));
        proxy = address(new TransparentUpgradeableProxy(address(new Dummy()), address(admin), ""));

        upgraderAndCaller = address(new ProxyUpgradeAndCallAction());
        upgrader = address(new ProxyUpgradeAction());
    }

    function testUpgradeAndCall() public {
        Dummy newLogicImpl = new Dummy();
        bytes memory data = abi.encodeWithSelector(
            ProxyUpgradeAndCallAction.perform.selector,
            address(admin),
            address(proxy),
            address(newLogicImpl),
            abi.encodeWithSelector(newLogicImpl.someFunction.selector)
        );
        vm.expectEmit(true, true, true, true);
        emit SomeEvent();
        vm.prank(executor0);
        ue.execute(upgraderAndCaller, data);
        address newImpl = address(uint160(uint256(vm.load(address(proxy), _IMPLEMENTATION_SLOT))));
        assertEq(newImpl, address(newLogicImpl));
    }

    function testUpgrade() public {
        Dummy newLogicImpl = new Dummy();
        bytes memory data = abi.encodeWithSelector(
            ProxyUpgradeAction.perform.selector,
            address(admin),
            address(proxy),
            address(newLogicImpl)
        );
        vm.prank(executor0);
        ue.execute(upgrader, data);
        address newImpl = address(uint160(uint256(vm.load(address(proxy), _IMPLEMENTATION_SLOT))));
        assertEq(newImpl, address(newLogicImpl));
    }
}
