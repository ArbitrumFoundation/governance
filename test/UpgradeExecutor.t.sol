// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/UpgradeExecutor.sol";
import "./util/TestUtil.sol";

import "forge-std/Test.sol";

// CHRIS: TODO: remove TestUpgrade from the src - it should only be in /test/

// CHRIS: TODO: write a bunch of stuff about how the UpgradeExecutor should be used

contract UpgradeExecutorTest is Test {
    address executor0 = address(138);
    address executor1 = address(139);

    function testDoesDeploy() external  {
        UpgradeExecutor ue = UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](2);
        executors[0] = executor0;
        executors[1] = executor1;

        ue.initialize(address(ue), executors);

        assertEq(ue.hasRole(ue.EXECUTOR_ROLE(), executor0), true, "Executor 1");
    }
}
