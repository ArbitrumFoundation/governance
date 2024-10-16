// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";

import {
    ProxyAdmin,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "src/gov-action-contracts/AIPs/upgrade-executor-upgrade/UpgradeExecutorUpgradeAction.sol";

contract UpgradeExecutorUpgradeActionTest is Test {
    function testArbOne() external {
        vm.createSelectFork(vm.envString("ARB_URL"));
        _testUpgrade(
            0xdb216562328215E010F819B5aBe947bad4ca961e,
            0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827,
            0xf7951D92B0C345144506576eC13Ecf5103aC905a
        );
    }

    function testNova() external {
        vm.createSelectFork(vm.envString("NOVA_URL"));
        _testUpgrade(
            0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9,
            0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482,
            0xf7951D92B0C345144506576eC13Ecf5103aC905a
        );
    }

    function testL1() external {
        vm.createSelectFork(vm.envString("ETH_URL"));
        _testUpgrade(
            0x5613AF0474EB9c528A34701A5b1662E3C8FA0678,
            0x3ffFbAdAF827559da092217e474760E2b2c3CeDd,
            0xE6841D92B0C345144506576eC13ECf5103aC7f49
        );
    }

    function _testUpgrade(
        address admin,
        address ue,
        address executor
    ) internal {
        UpgradeExecutorUpgradeAction action = new UpgradeExecutorUpgradeAction();
        vm.prank(executor);
        UpgradeExecutor(ue).execute(address(action), abi.encodeWithSignature("perform()"));

        assertTrue(
            ProxyAdmin(admin).getProxyImplementation(
                TransparentUpgradeableProxy(payable(address(ue)))
            ) == action.newUpgradeExecutorImplementation()
        );
    }
}
