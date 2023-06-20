// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../util/TestUtil.sol";

import "../../src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory.sol";
import "../../src/security-council-mgmt/SecurityCouncilUpgradeExecutor.sol";
import "../../src/security-council-mgmt/SecurityCouncilMemberRemoverGov.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";

import "../../src/security-council-mgmt/interfaces/IGnosisSafe.sol";

contract L2SecurityCouncilMgmtFactoryTest is Test {
    address govChainEmergencySecurityCouncil;
    address govChainNonEmergencySecurityCouncil;
    address l1SecurityCouncilUpdateRouter = address(11_111);
    address proxyAdmin;
    address[] marchCohort = [address(11_112)];
    address[] septemberCohort = [address(11_113)];
    address l2UpgradeExecutor;
    address arbToken;

    uint256 removalGovMinTimelockDelay = uint256(1);
    uint256 removalGovVotingDelay = uint256(2);
    uint256 removalGovVotingPeriod = uint256(3);
    uint256 removalGovQuorumNumerator = uint256(4);
    uint256 removalGovProposalThreshold = uint256(5);
    uint64 removalGovMinPeriodAfterQuorum = uint64(6);
    L2SecurityCouncilMgmtFactory fac;
    DeployParams deployParams;

    address rando = address(11_114);

    function setUp() public {
        govChainEmergencySecurityCouncil = TestUtil.deployStub();
        govChainNonEmergencySecurityCouncil = TestUtil.deployStub();
        proxyAdmin = TestUtil.deployStub();
        l2UpgradeExecutor = TestUtil.deployStub();
        arbToken = TestUtil.deployStub();
        fac = new L2SecurityCouncilMgmtFactory();
        deployParams = DeployParams({
            _govChainEmergencySecurityCouncil: govChainEmergencySecurityCouncil,
            _govChainNonEmergencySecurityCouncil: govChainNonEmergencySecurityCouncil,
            _l1SecurityCouncilUpdateRouter: l1SecurityCouncilUpdateRouter,
            _proxyAdmin: proxyAdmin,
            _marchCohort: marchCohort,
            _septemberCohort: septemberCohort,
            l2UpgradeExecutor: l2UpgradeExecutor,
            arbToken: arbToken,
            _removalGovMinTimelockDelay: removalGovMinTimelockDelay,
            _removalGovVotingDelay: removalGovVotingDelay,
            _removalGovVotingPeriod: removalGovVotingPeriod,
            _removalGovQuorumNumerator: removalGovQuorumNumerator,
            _removalGovProposalThreshold: removalGovProposalThreshold,
            _removalGovMinPeriodAfterQuorum: removalGovMinPeriodAfterQuorum
        });
    }

    function testOnlyOwnerCanDeploy() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        (
            address l2EmergencySecurityCouncilUpgradeExecutor,
            address l2NonEmergencySecurityCouncilUpgradeExecutor,
            address securityCouncilMemberRemoverGov,
            address securityCouncilManager
        ) = fac.deployStep2(deployParams);
    }

    function testEmergencySCExecDeployment() public {
        (
            address l2EmergencySecurityCouncilUpgradeExecutorAddr,
            address l2NonEmergencySecurityCouncilUpgradeExecutorAddr,
            address securityCouncilMemberRemoverGovAddr,
            address securityCouncilManagerAddr
        ) = fac.deployStep2(deployParams);

        // emergency SC upgrade exec initialization
        SecurityCouncilUpgradeExecutor l2EmergencySecurityCouncilUpgradeExecutor =
            SecurityCouncilUpgradeExecutor(l2EmergencySecurityCouncilUpgradeExecutorAddr);
        vm.expectRevert("Initializable: contract is already initialized");
        l2EmergencySecurityCouncilUpgradeExecutor.initialize(IGnosisSafe(rando), rando, rando);

        address emSC = address(l2EmergencySecurityCouncilUpgradeExecutor.securityCouncil());
        assertEq(emSC, govChainEmergencySecurityCouncil, "Emergency SC set in SC upgrade exec");

        assertTrue(
            l2EmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2EmergencySecurityCouncilUpgradeExecutor.UPDATOR_ROLE(), securityCouncilManagerAddr
            ),
            "SecurityCouncilManagerAddr is updater for l2EmergencySecurityCouncilUpgradeExecutor"
        );
        assertTrue(
            l2EmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2EmergencySecurityCouncilUpgradeExecutor.UPDATOR_ROLE(),
                govChainEmergencySecurityCouncil
            ),
            "govChainEmergencySecurityCouncil is updater for l2EmergencySecurityCouncilUpgradeExecutor"
        );
        assertTrue(
            l2EmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2EmergencySecurityCouncilUpgradeExecutor.DEFAULT_ADMIN_ROLE(), l2UpgradeExecutor
            ),
            "l2UpgradeExecutor is role admin for l2EmergencySecurityCouncilUpgradeExecutor"
        );
    }

    function testNonEmergencySCExecDeployment() public {
        (
            address l2EmergencySecurityCouncilUpgradeExecutorAddr,
            address l2NonEmergencySecurityCouncilUpgradeExecutorAddr,
            address securityCouncilMemberRemoverGovAddr,
            address securityCouncilManagerAddr
        ) = fac.deployStep2(deployParams);

        SecurityCouncilUpgradeExecutor l2NonEmergencySecurityCouncilUpgradeExecutor =
            SecurityCouncilUpgradeExecutor(l2NonEmergencySecurityCouncilUpgradeExecutorAddr);
        vm.expectRevert("Initializable: contract is already initialized");
        l2NonEmergencySecurityCouncilUpgradeExecutor.initialize(IGnosisSafe(rando), rando, rando);

        address noneMSC = address(l2NonEmergencySecurityCouncilUpgradeExecutor.securityCouncil());
        assertEq(
            noneMSC, govChainNonEmergencySecurityCouncil, "non emergency SC set in SC upgrade exec"
        );
        assertTrue(
            l2NonEmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2NonEmergencySecurityCouncilUpgradeExecutor.UPDATOR_ROLE(),
                securityCouncilManagerAddr
            ),
            "SecurityCouncilManagerAddr is updater for l2NonEmergencySecurityCouncilUpgradeExecutor"
        );
        assertTrue(
            l2NonEmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2NonEmergencySecurityCouncilUpgradeExecutor.UPDATOR_ROLE(),
                govChainNonEmergencySecurityCouncil
            ),
            "govChainNonEmergencySecurityCouncil is updater for l2NonEmergencySecurityCouncilUpgradeExecutor"
        );
        assertTrue(
            l2NonEmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2NonEmergencySecurityCouncilUpgradeExecutor.DEFAULT_ADMIN_ROLE(), l2UpgradeExecutor
            ),
            "l2UpgradeExecutor is role admin for l2NonEmergencySecurityCouncilUpgradeExecuto"
        );
    }

    function testSecurityCouncilManagerDeployment() public {
        (
            address l2EmergencySecurityCouncilUpgradeExecutorAddr,
            address l2NonEmergencySecurityCouncilUpgradeExecutorAddr,
            address securityCouncilMemberRemoverGovAddr,
            address securityCouncilManagerAddr
        ) = fac.deployStep2(deployParams);
        SecurityCouncilManager securityCouncilManager =
            SecurityCouncilManager(securityCouncilManagerAddr);

        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.DEFAULT_ADMIN_ROLE(), l2UpgradeExecutor
            ),
            "DAO has admin role"
        );
        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.MEMBER_ADDER_ROLE(), govChainEmergencySecurityCouncil
            ),
            "SecurityCouncilManager: emergency security council has adder role"
        );
        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.MEMBER_ROTATOR_ROLE(), govChainEmergencySecurityCouncil
            ),
            "emergency security council has rotator role"
        );
        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.MEMBER_REMOVER_ROLE(), securityCouncilMemberRemoverGovAddr
            ),
            "emergency security council has removal role"
        );
        // TODO test that election contract has cohort updator role

        assertTrue(
            TestUtil.areAddressArraysEqual(securityCouncilManager.getMarchCohort(), marchCohort),
            "march cohort set"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(
                securityCouncilManager.getSeptemberCohort(), septemberCohort
            ),
            "september cohort set"
        );
        TargetContracts memory tc = securityCouncilManager.getTargetContracts();
        assertEq(
            tc.govChainEmergencySecurityCouncilUpgradeExecutor,
            l2EmergencySecurityCouncilUpgradeExecutorAddr,
            "emergency SC set"
        );
        assertEq(
            tc.govChainNonEmergencySecurityCouncilUpgradeExecutor,
            l2NonEmergencySecurityCouncilUpgradeExecutorAddr,
            "non emergency SC set"
        );
        assertEq(
            tc.l1SecurityCouncilUpdateRouter, l1SecurityCouncilUpdateRouter, "l1update router set"
        );
    }

    function testRemovalGovDeployment() public {
        (
            address l2EmergencySecurityCouncilUpgradeExecutorAddr,
            address l2NonEmergencySecurityCouncilUpgradeExecutorAddr,
            address securityCouncilMemberRemoverGovAddr,
            address securityCouncilManagerAddr
        ) = fac.deployStep2(deployParams);
        SecurityCouncilMemberRemoverGov rg =
            SecurityCouncilMemberRemoverGov(payable(securityCouncilMemberRemoverGovAddr));

        assertTrue(
            rg.hasRole(rg.PROPSER_ROLE(), govChainEmergencySecurityCouncil),
            "emergency SC has removal role"
        );
        assertTrue(
            rg.hasRole(rg.DEFAULT_ADMIN_ROLE(), l2UpgradeExecutor), "emergency SC has removal role"
        );
    }
}
