// // SPDX-License-Identifier: Apache-2.0
// pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/UpgradeExecutor.sol";
import "../src/ArbitrumTimelock.sol";
import "../src/ArbitrumDAOConstitution.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L2GovernanceFactoryTest is Test {
    // token
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

    // councils
    address l2EmergencyCouncil = address(504);
    address aliasedL1Timelock = address(404);

    address[] addressArrayStub = [address(777), address(888)];

    address someRando = address(390);
    address l2NonEmergencySecurityCouncil = address(1234);

    address l2InitialSupplyRecipient = address(456);

    bytes32 constitutionHash = bytes32("0x0123");

    DeployCoreParams deployCoreParams = DeployCoreParams({
        _l2MinTimelockDelay: l2MinTimelockDelay,
        _l1Token: l1Token,
        _l2TokenInitialSupply: l2TokenInitialSupply,
        _votingPeriod: votingPeriod,
        _votingDelay: votingDelay,
        _coreQuorumThreshold: coreQuorumThreshold,
        _treasuryQuorumThreshold: treasuryQuorumThreshold,
        _proposalThreshold: proposalThreshold,
        _minPeriodAfterQuorum: minPeriodAfterQuorum,
        _l2NonEmergencySecurityCouncil: l2NonEmergencySecurityCouncil,
        _l2InitialSupplyRecipient: l2InitialSupplyRecipient,
        _l2EmergencySecurityCouncil: l2EmergencyCouncil,
        _constitutionHash: constitutionHash
    });

    function deploy()
        public
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            FixedDelegateErc20Wallet arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor,
            L2GovernanceFactory l2GovernanceFactory,
            ArbitrumDAOConstitution arbitrumDAOConstitution
        )
    {
        L2GovernanceFactory l2GovernanceFactory;
        {
            address _coreTimelockLogic = address(new ArbitrumTimelock());
            address _coreGovernorLogic = address(new L2ArbitrumGovernor());
            address _treasuryTimelockLogic = address(new ArbitrumTimelock());
            address _treasuryLogic = address(new FixedDelegateErc20Wallet());
            address _treasuryGovernorLogic = address(new L2ArbitrumGovernor());
            address _l2TokenLogic = address(new L2ArbitrumToken());
            address _upgradeExecutorLogic = address(new UpgradeExecutor());

            l2GovernanceFactory = new L2GovernanceFactory(
            _coreTimelockLogic,
            _coreGovernorLogic,
            _treasuryTimelockLogic,
            _treasuryLogic,
            _treasuryGovernorLogic,
            _l2TokenLogic,
            _upgradeExecutorLogic
        );
        }

        (DeployedContracts memory dc, DeployedTreasuryContracts memory dtc) =
            l2GovernanceFactory.deployStep1(deployCoreParams);
        l2GovernanceFactory.deployStep3(aliasedL1Timelock);

        vm.prank(l2InitialSupplyRecipient);
        dc.token.transferOwnership(address(dc.executor));

        return (
            dc.token,
            dc.coreGov,
            dc.coreTimelock,
            dtc.treasuryGov,
            dtc.treasuryTimelock,
            dtc.arbTreasury,
            dc.proxyAdmin,
            dc.executor,
            l2GovernanceFactory,
            dc.arbitrumDAOConstitution
        );
    }

    function testDeploySteps() public {
        address owner = address(232_323);
        address _coreTimelockLogic = address(new ArbitrumTimelock());
        address _coreGovernorLogic = address(new L2ArbitrumGovernor());
        address _treasuryTimelockLogic = address(new ArbitrumTimelock());
        address _treasuryLogic = address(new FixedDelegateErc20Wallet());
        address _treasuryGovernorLogic = address(new L2ArbitrumGovernor());
        address _l2TokenLogic = address(new L2ArbitrumToken());
        address _upgradeExecutorLogic = address(new UpgradeExecutor());

        vm.prank(owner);
        L2GovernanceFactory l2GovernanceFactory = new L2GovernanceFactory(
            _coreTimelockLogic,
            _coreGovernorLogic,
            _treasuryTimelockLogic,
            _treasuryLogic,
            _treasuryGovernorLogic,
            _l2TokenLogic,
            _upgradeExecutorLogic
        );

        // rando can't start deploy
        vm.prank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        l2GovernanceFactory.deployStep1(deployCoreParams);

        // owner can't skip to step 3
        vm.startPrank(owner);
        vm.expectRevert("L2GovernanceFactory: not step three");
        l2GovernanceFactory.deployStep3(aliasedL1Timelock);

        // owner should successfully carry out step 1
        l2GovernanceFactory.deployStep1(deployCoreParams);

        // owner can't repeat step 1
        vm.expectRevert("L2GovernanceFactory: not step one");
        l2GovernanceFactory.deployStep1(deployCoreParams);
        vm.stopPrank();

        // rando can't trigger step 3
        vm.prank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        l2GovernanceFactory.deployStep3(aliasedL1Timelock);

        // owner shoud successfully carrout out step 3
        vm.startPrank(owner);
        l2GovernanceFactory.deployStep3(aliasedL1Timelock);

        // owner can't repeat step 3
        vm.expectRevert("L2GovernanceFactory: not step three");
        l2GovernanceFactory.deployStep3(aliasedL1Timelock);
        vm.stopPrank();
    }

    function testContractsDeployed() external {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            FixedDelegateErc20Wallet arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor,
            L2GovernanceFactory l2GovernanceFactory,
            ArbitrumDAOConstitution arbitrumDAOConstitution
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
            FixedDelegateErc20Wallet arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor,
            L2GovernanceFactory l2GovernanceFactory,
            ArbitrumDAOConstitution arbitrumDAOConstitution
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

        address excludeAddress = treasuryGov.EXCLUDE_ADDRESS();
        vm.expectRevert("Initializable: contract is already initialized");
        arbTreasury.initialize(address(token), excludeAddress, address(treasuryGov));

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
            FixedDelegateErc20Wallet arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor upgradeExecutor,
            L2GovernanceFactory l2GovernanceFactory,
            ArbitrumDAOConstitution arbitrumDAOConstitution
        ) = deploy();
        assertEq(token.owner(), address(upgradeExecutor), "token.owner()");
        assertEq(
            arbitrumDAOConstitution.owner(),
            address(upgradeExecutor),
            "arbitrumDAOConstitution.owner()"
        );

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
        assertTrue(
            upgradeExecutor.hasRole(executorRole, l2EmergencyCouncil),
            "l2EmergencyCouncil is executor"
        );
        assertTrue(
            upgradeExecutor.hasRole(executorRole, aliasedL1Timelock),
            "aliasedL1Timelock is executor"
        );

        assertEq(
            token.delegates(address(arbTreasury)),
            treasuryGov.EXCLUDE_ADDRESS(),
            "Exclude address delegation"
        );
        assertEq(token.balanceOf(l2InitialSupplyRecipient), l2TokenInitialSupply, "Initial supply");
    }

    function testProxyAdminOwnership() public {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            FixedDelegateErc20Wallet arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor,
            L2GovernanceFactory l2GovernanceFactory,
            ArbitrumDAOConstitution arbitrumDAOConstitution
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

    function testRoles() public {
        (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            ArbitrumTimelock coreTimelock,
            L2ArbitrumGovernor treasuryGov,
            ArbitrumTimelock treasuryTimelock,
            FixedDelegateErc20Wallet arbTreasury,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor,
            L2GovernanceFactory l2GovernanceFactory,
            ArbitrumDAOConstitution arbitrumDAOConstitution
        ) = deploy();
        assertTrue(
            coreTimelock.hasRole(coreTimelock.PROPOSER_ROLE(), address(coreGov)),
            "core gov can propose"
        );
        assertTrue(
            coreTimelock.hasRole(
                coreTimelock.PROPOSER_ROLE(), address(l2NonEmergencySecurityCouncil)
            ),
            "l2NonEmergencySecurityCouncil can propose"
        );
        assertTrue(
            coreTimelock.hasRole(coreTimelock.CANCELLER_ROLE(), address(coreGov)),
            "core gov can cancel"
        );

        assertTrue(
            coreTimelock.hasRole(coreTimelock.EXECUTOR_ROLE(), address(0)), "anyone can execute"
        );
        assertTrue(
            coreTimelock.hasRole(coreTimelock.CANCELLER_ROLE(), l2EmergencyCouncil),
            "9/12 council can cancel"
        );

        assertTrue(
            treasuryTimelock.hasRole(treasuryTimelock.PROPOSER_ROLE(), address(treasuryGov)),
            "treasuryGov can propose"
        );
        assertTrue(
            treasuryTimelock.hasRole(treasuryTimelock.EXECUTOR_ROLE(), address(0)),
            "anyone can execute"
        );

        assertTrue(
            executor.hasRole(executor.ADMIN_ROLE(), address(executor)), "exec is admin of itself"
        );
        assertFalse(
            executor.hasRole(executor.ADMIN_ROLE(), address(l2GovernanceFactory)),
            "l2GovernanceFactory admin role is revoked"
        );
    }
}
