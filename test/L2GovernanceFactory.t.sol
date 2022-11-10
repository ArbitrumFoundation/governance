// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/UpgradeExecutor.sol";
import "../src/ArbitrumTimelock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract L2GovernanceFactoryTest is Test {
    address[] addressArrayStub = [address(777), address(888)];
    address owner = address(2323);
    uint256 l2MinTimelockDelay = 42;
    address l1Token = address(1);
    uint256 l2TokenInitialSupply = 43;
    address l2TokenOwner = address(2);
    address[] l2UpgradeExecutors;
    uint256 votingPeriod = 44;
    uint256 votingDelay = 45;
    uint256 coreQuorumThreshold = 4;
    uint256 treasuryQuorumThreshold = 3;
    uint256 proposalThreshold = 5e6;
    uint64 minPeriodAfterQuorum = 42;

    function deploy()
        public
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        address[] memory l2UpgradeExecutors; // DG: TODO should be security council and l1 timelock alias?
        L2GovernanceFactory l2GovernanceFactory = new L2GovernanceFactory();

        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            L2ArbitrumGovernor treasuryGov,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        ) = l2GovernanceFactory.deploy(
            DeployCoreParams({
                _l2MinTimelockDelay: l2MinTimelockDelay,
                _l1Token: l1Token,
                _l2TokenInitialSupply: l2TokenInitialSupply,
                _l2TokenOwner: l2TokenOwner,
                _l2UpgradeExecutors: l2UpgradeExecutors,
                _votingPeriod: votingPeriod,
                _votingDelay: votingDelay,
                _coreQuorumThreshold: coreQuorumThreshold,
                _treasuryQuorumThreshold: treasuryQuorumThreshold,
                _proposalThreshold: proposalThreshold,
                _minPeriodAfterQuorum: minPeriodAfterQuorum
            })
        );
        ArbitrumTimelock coreTimelock = ArbitrumTimelock(payable(coreGov.timelock()));

        ArbitrumTimelock treasuryTimelock = ArbitrumTimelock(payable(treasuryGov.timelock()));

        return (token, coreGov, coreTimelock, treasuryGov, treasuryTimelock, proxyAdmin, executor);
    }

    function testContractsDeployed() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        ) = deploy();
        assertGt(address(token).code.length, 0, "no token deployed");
        assertGt(address(coreGov).code.length, 0, "no governer deployed");
        assertGt(address(coreTimelock).code.length, 0, "no timelock deployed");
        assertGt(address(treasuryGov).code.length, 0, "no treasuryGov deployed");
        assertGt(address(treasuryTimelock).code.length, 0, "no treasuryTimelock deployed");
        assertGt(address(proxyAdmin).code.length, 0, "no proxyAdmin deployed");
        assertGt(address(executor).code.length, 0, "no upgradeExecutor deployed");
    }

    function testContractsInitialized() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock timelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor
        ) = deploy();
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(l1Token, l2TokenInitialSupply, l1Token);

        vm.expectRevert("Initializable: contract is already initialized");
        gov.initialize(token, timelock, owner, 1, 1, 1, 1, 1);

        vm.expectRevert("Initializable: contract is already initialized");
        timelock.initialize(1, addressArrayStub, addressArrayStub);

        vm.expectRevert("Initializable: contract is already initialized");
        address[] memory addresses = new address[](1);
        addresses[0] = owner;
        upgradeExecutor.initialize(address(upgradeExecutor), addresses);
    }
}

/**
 * Test TODOs:
 * - testContractsInitialized: check treasury contracts
 * - Sanity checks - contracts init with expected values
 * - Only contract deployer can call deploy
 * - MainnetL2GovernanceFactory: can't call deploy, mainnetDeploy works
 */
