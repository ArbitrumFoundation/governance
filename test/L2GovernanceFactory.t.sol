// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/UpgradeExecutor.sol";
import "../src/ArbitrumTimelock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L2GovernanceFactoryTest is Test {
    // token
    address l2TokenOwner = address(123);
    address l1Token = address(139);
    uint256 l2TokenInitialSupply = 1e10;

    // timelock
    uint256 l2MinTimelockDelay = 42;

    // govs
    uint256 votingPeriod = 44;
    uint256 votingDelay = 45;
    uint256 coreQuorumThreshold = 4;
    uint256 treasuryQuorumThreshold = 3;
    uint256 proposalThreshold = 5e6;
    uint64 minPeriodAfterQuorum = 41;

    address[] l2UpgradeExecutors = [address(4), address(5)];

    address[] addressArrayStub = [address(777), address(888)];

    address someRando = address(3);

    DeployCoreParams deployCoreParams = DeployCoreParams({
        _l2MinTimelockDelay: l2MinTimelockDelay,
        _l1Token: l1Token,
        _l2TokenInitialSupply: l2TokenInitialSupply,
        _l2TokenOwner: l2TokenOwner,
        _votingPeriod: votingPeriod,
        _votingDelay: votingDelay,
        _coreQuorumThreshold: coreQuorumThreshold,
        _treasuryQuorumThreshold: treasuryQuorumThreshold,
        _proposalThreshold: proposalThreshold,
        _minPeriodAfterQuorum: minPeriodAfterQuorum
    });

    function deploy()
        public
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        L2GovernanceFactory l2GovernanceFactory = new L2GovernanceFactory();

        (DeployedContracts memory dc, DeployedTreasuryContracts memory dtc) =
            l2GovernanceFactory.deployStep1(deployCoreParams);
        l2GovernanceFactory.deployStep3(l2UpgradeExecutors);

        return (
            dc.token,
            dc.coreGov,
            dc.coreTimelock,
            dtc.treasuryGov,
            dtc.treasuryTimelock,
            dtc.arbTreasury,
            dc.proxyAdmin,
            dc.executor
        );
    }

    function testDeploySteps()
        public
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        address owner = address(232_323);
        vm.prank(owner);
        L2GovernanceFactory l2GovernanceFactory = new L2GovernanceFactory();

        // rando can't start deploy
        vm.prank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        l2GovernanceFactory.deployStep1(deployCoreParams);

        // owner can't skip to step 3
        vm.startPrank(owner);
        vm.expectRevert("L2GovernanceFactory: l2Executor not yet deployed");
        l2GovernanceFactory.deployStep3(l2UpgradeExecutors);

        // owner should successfully carry out step 1
        l2GovernanceFactory.deployStep1(deployCoreParams);

        // owner can't repeat step 1
        vm.expectRevert("L2GovernanceFactory: l2Executor already deployed");
        l2GovernanceFactory.deployStep1(deployCoreParams);
        vm.stopPrank();

        // rando can't trigger step 3
        vm.prank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        l2GovernanceFactory.deployStep3(l2UpgradeExecutors);

        // owner shoud successfully carrout out step 3
        vm.startPrank(owner);
        l2GovernanceFactory.deployStep3(l2UpgradeExecutors);

        // owner can't repeat step 3
        vm.expectRevert("Initializable: contract is already initialized");
        l2GovernanceFactory.deployStep3(l2UpgradeExecutors);
        vm.stopPrank();
    }

    function testContractsDeployed() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        ) = deploy();
        assertGt(address(token).code.length, 0, "no token deployed");
        assertGt(address(coreGov).code.length, 0, "no governer deployed");
        assertGt(address(coreTimelock).code.length, 0, "no timelock deployed");
        assertGt(address(treasuryGov).code.length, 0, "no treasuryGov deployed");
        assertGt(address(treasuryTimelock).code.length, 0, "no treasuryTimelock deployed");
        assertGt(address(arbTreasury).code.length, 0, "no treasuryTimelock deployed");
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
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor
        ) = deploy();
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(l1Token, l2TokenInitialSupply, l1Token);

        vm.expectRevert("Initializable: contract is already initialized");
        gov.initialize(token, timelock, someRando, 1, 1, 1, 1, 1);

        vm.expectRevert("Initializable: contract is already initialized");
        treasuryGov.initialize(token, timelock, someRando, 1, 1, 1, 1, 1);

        vm.expectRevert("Initializable: contract is already initialized");
        timelock.initialize(1, addressArrayStub, addressArrayStub);

        vm.expectRevert("Initializable: contract is already initialized");
        treasuryTimelock.initialize(1, addressArrayStub, addressArrayStub);

        vm.expectRevert("Initializable: contract is already initialized");
        arbTreasury.initialize(payable(address(treasuryGov)));

        vm.expectRevert("Initializable: contract is already initialized");
        address[] memory addresses = new address[](1);
        addresses[0] = someRando;
        upgradeExecutor.initialize(address(upgradeExecutor), addresses);
    }

    function testSanityCheckValues() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor
        ) = deploy();
        assertEq(token.owner(), l2TokenOwner, "token.owner()");
        assertEq(token.l1Address(), l1Token, "token.l1Address()");
        assertEq(token.totalSupply(), l2TokenInitialSupply, "token.totalSupply()");

        assertEq(coreTimelock.getMinDelay(), l2MinTimelockDelay, "coreTimelock.getMinDelay()");
        assertEq(treasuryTimelock.getMinDelay(), 0, "treasuryTimelock.minDelay() zero");

        assertEq(gov.votingPeriod(), votingPeriod, "gov.votingPeriod()");
        assertEq(treasuryGov.votingPeriod(), votingPeriod, "treasuryGov.votingPeriod()");
        assertEq(gov.votingDelay(), votingDelay, "gov.votingDelay()");
        assertEq(treasuryGov.votingDelay(), votingDelay, "treasuryGov.votingDelay()");

        assertEq(gov.quorumNumerator(), coreQuorumThreshold, "gov.quorumNumerator()");
        assertEq(
            treasuryGov.quorumNumerator(), treasuryQuorumThreshold, "reasuryGov.quorumNumerator()"
        );

        assertEq(gov.proposalThreshold(), proposalThreshold, "gov.proposalThreshold()");
        assertEq(
            treasuryGov.proposalThreshold(), proposalThreshold, "treasuryGov.proposalThreshold()"
        );

        assertEq(
            gov.lateQuorumVoteExtension(), minPeriodAfterQuorum, "gov.lateQuorumVoteExtension()"
        );
        assertEq(
            treasuryGov.lateQuorumVoteExtension(),
            minPeriodAfterQuorum,
            "treasuryGov.lateQuorumVoteExtension()"
        );

        bytes32 executorRole = upgradeExecutor.EXECUTOR_ROLE();
        for (uint256 i = 0; i < l2UpgradeExecutors.length; i++) {
            assertTrue(
                upgradeExecutor.hasRole(executorRole, l2UpgradeExecutors[i]),
                "l2UpgradeExecutors are executors"
            );
        }

        assertEq(arbTreasury.treasuryGov(), payable(address(treasuryGov)), "arbTreasury gov set");
        assertEq(arbTreasury.arbToken(), address(token), "arbTreasury token set");
    }

    function testArbTreasury() public {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor
        ) = deploy();
        vm.startPrank(l2TokenOwner);
        vm.warp(block.timestamp + token.MIN_MINT_INTERVAL());

        token.mint(address(arbTreasury), 1000);

        vm.expectRevert("ArbTreasury: not from treasury gov"); //
        arbTreasury.transferArbToken(someRando, 100);
        vm.stopPrank();

        vm.prank(address(treasuryGov));
        arbTreasury.transferArbToken(someRando, 100);

        assertEq(token.balanceOf(address(arbTreasury)), 900, "tokens not transfered");

        vm.deal(address(arbTreasury), 1000);
        vm.prank(someRando);
        vm.expectRevert("ArbTreasury: not from treasury gov");
        arbTreasury.sendETH(payable(someRando), 100);

        assertEq(address(arbTreasury).balance, 1000, "arbtreasury not funded");
        vm.prank(address(treasuryGov));

        arbTreasury.sendETH(payable(someRando), 100);
        assertEq(address(arbTreasury).balance, 900, "eth not sent");
    }

    function testProxyAdminOwnership() public {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            ArbTreasury arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        ) = deploy();
        assertEq(proxyAdmin.owner(), address(executor), "L2 Executor owns l2 proxyAdmin");

        address[7] memory deployments = [
            address(token),
            address(coreGov),
            address(coreTimelock),
            address(treasuryGov),
            address(treasuryTimelock),
            address(arbTreasury),
            address(executor)
        ];
        address proxyAdminAddress = address(proxyAdmin);
        vm.startPrank(proxyAdminAddress);
        for (uint256 i = 0; i < deployments.length; i++) {
            assertEq(
                TransparentUpgradeableProxy(payable(deployments[i])).admin(),
                proxyAdminAddress,
                "proxyAdmin is admin"
            );
        }
        vm.stopPrank();
    }
}
