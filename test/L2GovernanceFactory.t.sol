// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/UpgradeExecutor.sol";
import "../src/ArbitrumTimelock.sol";

import "forge-std/Test.sol";

contract L2GovernanceFactoryTest is Test {
    address l1TokenAddr = address(111);
    address l2UpgradeExecutorInitialOwner = address(666);
    uint256 initialSupply = 522;
    address[] addressArrayStub = [address(777), address(888)];
    address addressStub = address(2323);

    function deploy()
        private
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock timelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        address tokenLogic = address(new L2ArbitrumToken());
        address governerLogic = address(new L2ArbitrumGovernor());
        address upgradeExecutorLogic = address(new UpgradeExecutor());
        address timeLockLogic = address(new ArbitrumTimelock());

        L2GovernanceFactory factory = new L2GovernanceFactory();
        return
            factory.deploy(
                DeployParams({
                    _l2MinTimelockDelay: 0,
                    _l1TokenAddress: l1TokenAddr,
                    _l2TokenLogic: tokenLogic,
                    _l2TokenInitialSupply: initialSupply,
                    _l2TokenOwner: address(this),
                    _l2TimeLockLogic: timeLockLogic,
                    _l2GovernorLogic: governerLogic,
                    _l2UpgradeExecutorLogic: upgradeExecutorLogic,
                    _l2UpgradeExecutorInitialOwner: l2UpgradeExecutorInitialOwner,
                    _votingPeriod: 1,
                    _votingDelay: 1,
                    _proposalThreshold: 1,
                    _quorumThreshold: 1
                })
            );
    }

    function testContractsDeployed() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock timelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor
        ) = deploy();
        assertGt(address(token).code.length, 0, "no token deployed");
        assertGt(address(gov).code.length, 0, "no governer deployed");
        assertGt(address(timelock).code.length, 0, "no timelock deployed");
        assertGt(address(proxyAdmin).code.length, 0, "no proxyAdmin deployed");
        assertGt(
            address(upgradeExecutor).code.length,
            0,
            "no upgradeExecutor deployed"
        );
    }

    function testContractsInitialized() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock timelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor
        ) = deploy();
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(l1TokenAddr, initialSupply, l1TokenAddr);

        vm.expectRevert("Initializable: contract is already initialized");
        gov.initialize(token, timelock, addressStub, 1, 1, 1, 1);

        vm.expectRevert("Initializable: contract is already initialized");
        timelock.initialize(1, addressArrayStub, addressArrayStub);

        vm.expectRevert("Initializable: contract is already initialized");
        upgradeExecutor.initialize(addressStub);
    }
}
