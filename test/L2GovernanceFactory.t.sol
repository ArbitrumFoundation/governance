// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";

import "forge-std/Test.sol";

contract L2GovernanceFactoryTest is Test {
    address l1TokenAddr = address(111);
    address l2TokenAddr = address(222);
    address l2TimeLockLogic = address(333);
    address l2GovernorLogic = address(444);
    address l2UpgradeExecutorLogic = address(555);
    address l2UpgradeExecutorInitialOwner = address(666);

    uint256 initialSupply = 522;

    function testDoesDeployGovernanceFactory() external {
        // CHRIS: TODO: comment back in

        // L2GovernanceFactory factory = new L2GovernanceFactory();
        // (
        //     L2ArbitrumToken token,
        //     L2ArbitrumGovernor gov,
        //     ArbitrumTimelock timelock,
        //     ProxyAdmin proxyAdmin,
        //     UpgradeExecutor upgradeExecutor
        // ) = factory.deploy(
        //     0,
        //     l1TokenAddr,
        //     l2TokenAddr,
        //     initialSupply,
        //     address(this),
        //     l2TimeLockLogic,
        //     l2GovernorLogic,
        //     l2UpgradeExecutorLogic,
        //     l2UpgradeExecutorInitialOwner
        // );

        // assertGt(address(token).code.length, 0, "no token deployed");
    }
}
