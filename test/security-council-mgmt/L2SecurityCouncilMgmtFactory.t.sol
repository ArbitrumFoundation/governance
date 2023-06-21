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

    // todo: set these to something meaningful for testing. for now just to compile
    Cohort firstCohort = Cohort.SEPTEMBER;
    uint256 firstNominationStartTime = 7;
    uint256 nominationFrequency = 8;
    uint256 nomineeVettingDuration = 9;
    address nomineeVetter = address(11_114);
    uint256 nomineeQuorumNumerator = 10;
    uint256 nomineeVotingPeriod = 11;
    uint256 memberVotingPeriod = 12;
    uint256 memberFullWeightDurationNumerator = 13;
    uint256 memberDecreasingWeightDurationNumerator = 14;
    uint256 memberDurationDenominator = memberFullWeightDurationNumerator + memberDecreasingWeightDurationNumerator;

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
            _removalGovMinPeriodAfterQuorum: removalGovMinPeriodAfterQuorum,
            firstCohort: firstCohort,
            firstNominationStartTime: firstNominationStartTime,
            nominationFrequency: nominationFrequency,
            nomineeVettingDuration: nomineeVettingDuration,
            nomineeVetter: nomineeVetter,
            nomineeQuorumNumerator: nomineeQuorumNumerator,
            nomineeVotingPeriod: nomineeVotingPeriod,
            memberVotingPeriod: memberVotingPeriod,
            memberFullWeightDurationNumerator: memberFullWeightDurationNumerator,
            memberDecreasingWeightDurationNumerator: memberDecreasingWeightDurationNumerator,
            memberDurationDenominator: memberDurationDenominator
        });
    }

    function testOnlyOwnerCanDeploy() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);
    }

    function testEmergencySCExecDeployment() public {
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);

        // emergency SC upgrade exec initialization
        SecurityCouncilUpgradeExecutor l2EmergencySecurityCouncilUpgradeExecutor =
            SecurityCouncilUpgradeExecutor(deployed.l2EmergencySecurityCouncilUpgradeExecutor);
        vm.expectRevert("Initializable: contract is already initialized");
        l2EmergencySecurityCouncilUpgradeExecutor.initialize(IGnosisSafe(rando), rando, rando);

        address emSC = address(l2EmergencySecurityCouncilUpgradeExecutor.securityCouncil());
        assertEq(emSC, govChainEmergencySecurityCouncil, "Emergency SC set in SC upgrade exec");

        assertTrue(
            l2EmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2EmergencySecurityCouncilUpgradeExecutor.UPDATOR_ROLE(), address(deployed.securityCouncilManager)
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
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);

        SecurityCouncilUpgradeExecutor l2NonEmergencySecurityCouncilUpgradeExecutor =
            SecurityCouncilUpgradeExecutor(deployed.l2NonEmergencySecurityCouncilUpgradeExecutor);
        vm.expectRevert("Initializable: contract is already initialized");
        l2NonEmergencySecurityCouncilUpgradeExecutor.initialize(IGnosisSafe(rando), rando, rando);

        address noneMSC = address(l2NonEmergencySecurityCouncilUpgradeExecutor.securityCouncil());
        assertEq(
            noneMSC, govChainNonEmergencySecurityCouncil, "non emergency SC set in SC upgrade exec"
        );
        assertTrue(
            l2NonEmergencySecurityCouncilUpgradeExecutor.hasRole(
                l2NonEmergencySecurityCouncilUpgradeExecutor.UPDATOR_ROLE(),
                address(deployed.securityCouncilManager)
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
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);
        SecurityCouncilManager securityCouncilManager = SecurityCouncilManager(address(deployed.securityCouncilManager));

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
                securityCouncilManager.MEMBER_REMOVER_ROLE(), address(deployed.securityCouncilMemberRemoverGov)
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
            address(deployed.l2EmergencySecurityCouncilUpgradeExecutor),
            "emergency SC set"
        );
        assertEq(
            tc.govChainNonEmergencySecurityCouncilUpgradeExecutor,
            address(deployed.l2NonEmergencySecurityCouncilUpgradeExecutor),
            "non emergency SC set"
        );
        assertEq(
            tc.l1SecurityCouncilUpdateRouter, l1SecurityCouncilUpdateRouter, "l1update router set"
        );
    }

    function testRemovalGovDeployment() public {
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);
        SecurityCouncilMemberRemoverGov rg =
            SecurityCouncilMemberRemoverGov(payable(address(deployed.securityCouncilMemberRemoverGov)));

        assertTrue(
            rg.hasRole(rg.PROPSER_ROLE(), govChainEmergencySecurityCouncil),
            "emergency SC has removal role"
        );
        assertTrue(
            rg.hasRole(rg.DEFAULT_ADMIN_ROLE(), l2UpgradeExecutor), "emergency SC has removal role"
        );
    }

    function testNomineeElectionGovDeployment() public {
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);
        
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor = deployed.nomineeElectionGovernor;

        assertEq(nomineeElectionGovernor.targetNomineeCount(), marchCohort.length, "targetNomineeCount set");
        assertTrue(nomineeElectionGovernor.firstCohort() == firstCohort, "firstCohort set");
        assertEq(nomineeElectionGovernor.firstNominationStartTime(), firstNominationStartTime, "firstNominationStartTime set");
        assertEq(nomineeElectionGovernor.nominationFrequency(), nominationFrequency, "nominationFrequency set");
        assertEq(nomineeElectionGovernor.nomineeVettingDuration(), nomineeVettingDuration, "nomineeVettingDuration set");
        assertEq(nomineeElectionGovernor.nomineeVetter(), nomineeVetter, "nomineeVetter set");
        assertEq(
            address(nomineeElectionGovernor.securityCouncilManager()), 
            address(deployed.securityCouncilManager), 
            "securityCouncilManager set"
        );
        assertEq(address(nomineeElectionGovernor.token()), arbToken, "token set");
        assertEq(nomineeElectionGovernor.owner(), l2UpgradeExecutor, "owner set");
        assertEq(nomineeElectionGovernor.votingPeriod(), nomineeVotingPeriod, "votingPeriod set");
        assertEq(
            address(nomineeElectionGovernor.securityCouncilMemberElectionGovernor()), 
            address(deployed.memberElectionGovernor), 
            "securityCouncilMemberElectionGovernor set"
        );
        assertEq(nomineeElectionGovernor.quorumNumerator(), nomineeQuorumNumerator, "quorumNumeratorValue set");
    }

    function testMemberElectionGovDeployment() public {
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed =
            fac.deployStep2(deployParams);
        
        SecurityCouncilMemberElectionGovernor memberElectionGovernor = deployed.memberElectionGovernor;

        // assertEq(memberElectionGovernor.maxNominees(), marchCohort.length, "maxNominees set");
        assertEq(
            address(memberElectionGovernor.nomineeElectionGovernor()), 
            address(deployed.nomineeElectionGovernor), 
            "nomineeElectionGovernor set"
        );
        assertEq(
            address(memberElectionGovernor.securityCouncilManager()), 
            address(deployed.securityCouncilManager), 
            "securityCouncilManager set"
        );
        assertEq(address(memberElectionGovernor.token()), arbToken, "token set");
        assertEq(memberElectionGovernor.owner(), l2UpgradeExecutor, "owner set");
        assertEq(memberElectionGovernor.votingPeriod(), memberVotingPeriod, "votingPeriod set");
        assertEq(
            memberElectionGovernor.fullWeightDurationNumerator(), 
            memberFullWeightDurationNumerator, 
            "fullWeightDurationNumerator set"
        );
        assertEq(
            memberElectionGovernor.decreasingWeightDurationNumerator(), 
            memberDecreasingWeightDurationNumerator, 
            "decreasingWeightDurationNumerator set"
        );
        assertEq(
            memberElectionGovernor.durationDenominator(), 
            memberDurationDenominator, 
            "durationDenominator set"
        );
    }
}
