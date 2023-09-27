// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../util/TestUtil.sol";
import "../util/DeployGnosisWithModule.sol";

import "../../src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilMemberRemovalGovernor.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

import "../../src/security-council-mgmt/SecurityCouncilManager.sol";

import "../../src/security-council-mgmt/interfaces/IGnosisSafe.sol";

contract L2SecurityCouncilMgmtFactoryTest is Test, DeployGnosisWithModule {
    ChainAndUpExecLocation[] upgradeExecutors;
    address govChainEmergencySecurityCouncil;
    address l1ArbitrumTimelock = address(333);
    address l2CoreGovTimelock;
    address govChainProxyAdmin;
    address[] secondCohort = new address[](1);
    address[] firstCohort = new address[](1);
    address l2UpgradeExecutor;
    address arbToken;
    uint256 l1TimelockMinDelay;

    uint256 removalGovVotingDelay = uint256(2);
    uint256 removalGovVotingPeriod = uint256(3);
    uint256 removalGovQuorumNumerator = uint256(4);
    uint256 removalGovProposalThreshold = uint256(5);
    uint64 removalGovMinPeriodAfterQuorum = uint64(6);
    uint256 removalGovVoteSuccessNumerator = uint256(7);
    uint256 removalProposalExpirationBlocks = uint256(137);
    SecurityCouncilData[] securityCouncils;
    Date firstNominationStartDate =
        Date({year: uint256(2000), month: uint256(1), day: uint256(1), hour: uint256(1)});

    uint256 nomineeVettingDuration = uint256(7);
    address nomineeVetter = address(111_456);
    uint256 nomineeQuorumNumerator = uint256(200);
    uint256 nomineeVotingPeriod = uint256(9);
    uint256 memberVotingPeriod = uint256(112);
    uint256 fullWeightDuration = uint256(111);

    L2SecurityCouncilMgmtFactory fac;
    address owner = address(222);

    address rando = address(11_114);

    address firstCohortMember = address(3456);
    address secondCohortMember = address(7654);

    function getDeployParams() public returns (DeployParams memory deployParams) {
        ChainAndUpExecLocation[] memory upgradeExecutors;

        address[] memory scOwners = new address[](2);
        scOwners[0] = firstCohortMember;
        scOwners[1] = secondCohortMember;

        govChainEmergencySecurityCouncil = deploySafe(scOwners, 1, address(123));
        govChainProxyAdmin = TestUtil.deployStubContract();
        l2UpgradeExecutor = TestUtil.deployStubContract();
        arbToken = TestUtil.deployStubContract();
        l2CoreGovTimelock = TestUtil.deployStubContract();

        firstCohort[0] = firstCohortMember;
        secondCohort[0] = secondCohortMember;

        vm.prank(owner);
        fac = new L2SecurityCouncilMgmtFactory();
        return DeployParams({
            upgradeExecutors: upgradeExecutors,
            govChainEmergencySecurityCouncil: govChainEmergencySecurityCouncil,
            l1ArbitrumTimelock: l1ArbitrumTimelock,
            l2CoreGovTimelock: l2CoreGovTimelock,
            govChainProxyAdmin: govChainProxyAdmin,
            firstCohort: firstCohort,
            secondCohort: secondCohort,
            l2UpgradeExecutor: l2UpgradeExecutor,
            arbToken: arbToken,
            l1TimelockMinDelay: l1TimelockMinDelay,
            removalGovVotingDelay: removalGovVotingDelay,
            removalGovVotingPeriod: removalGovVotingPeriod,
            removalGovProposalThreshold: removalGovProposalThreshold,
            removalGovVoteSuccessNumerator: removalGovVoteSuccessNumerator,
            removalGovQuorumNumerator: removalGovQuorumNumerator,
            removalGovMinPeriodAfterQuorum: removalGovMinPeriodAfterQuorum,
            removalProposalExpirationBlocks: removalProposalExpirationBlocks,
            securityCouncils: securityCouncils,
            firstNominationStartDate: firstNominationStartDate,
            nomineeVettingDuration: nomineeVettingDuration,
            nomineeVetter: nomineeVetter,
            nomineeQuorumNumerator: nomineeQuorumNumerator,
            nomineeVotingPeriod: nomineeVotingPeriod,
            memberVotingPeriod: memberVotingPeriod,
            fullWeightDuration: fullWeightDuration
        });
    }

    function getContractImplementations() public returns (ContractImplementations memory) {
        return ContractImplementations({
            securityCouncilManager: address(new SecurityCouncilManager()),
            securityCouncilMemberRemoverGov: address(new SecurityCouncilMemberRemovalGovernor()),
            nomineeElectionGovernor: address(new SecurityCouncilNomineeElectionGovernor()),
            memberElectionGovernor: address(new SecurityCouncilMemberElectionGovernor())
        });
    }

    function testOnlyOwnerCanDeploy() public {
        DeployParams memory dp = getDeployParams();
        ContractImplementations memory ci = getContractImplementations();

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        fac.deploy(dp, ci);
    }

    function testSecurityCouncilManagerDeployment() public {
        DeployParams memory dp = getDeployParams();
        ContractImplementations memory ci = getContractImplementations();

        vm.prank(owner);
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed = fac.deploy(dp, ci);

        SecurityCouncilManager securityCouncilManager =
            SecurityCouncilManager(address(deployed.securityCouncilManager));

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
            "emergency security council has adder role"
        );
        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.MEMBER_ROTATOR_ROLE(), govChainEmergencySecurityCouncil
            ),
            "emergency security council has rotator role"
        );
        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.MEMBER_REPLACER_ROLE(), govChainEmergencySecurityCouncil
            ),
            "emergency security council has replacer role"
        );
        assertTrue(
            securityCouncilManager.hasRole(
                securityCouncilManager.COHORT_REPLACER_ROLE(),
                address(deployed.memberElectionGovernor)
            ),
            "memberElectionGovernor has replacer role"
        );

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(
                securityCouncilManager.getFirstCohort(), firstCohort
            ),
            "first cohort set"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(
                securityCouncilManager.getSecondCohort(), secondCohort
            ),
            "second cohort set"
        );

        assertEq(
            l2CoreGovTimelock,
            securityCouncilManager.l2CoreGovTimelock(),
            "l2 core gov timelock set"
        );
        assertEq(
            address(deployed.upgradeExecRouteBuilder),
            address(securityCouncilManager.router()),
            "l2 core gov timelock set"
        );
    }

    function testRemovalGovDeployment() public {
        DeployParams memory dp = getDeployParams();
        ContractImplementations memory ci = getContractImplementations();

        vm.prank(owner);
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed = fac.deploy(dp, ci);

        SecurityCouncilMemberRemovalGovernor rg = SecurityCouncilMemberRemovalGovernor(
            payable(address(deployed.securityCouncilMemberRemoverGov))
        );

        assertEq(rg.owner(), l2UpgradeExecutor, "upgrade exec is owner");
        assertEq(
            rg.voteSuccessNumerator(), removalGovVoteSuccessNumerator, "voteSuccessNumerator set"
        );

        assertEq(rg.votingDelay(), removalGovVotingDelay, "removalGovVotingDelay set");
        assertEq(rg.votingPeriod(), removalGovVotingPeriod, "removalGovVotingPeriod set");
        assertEq(rg.quorumNumerator(), removalGovQuorumNumerator, "removalGovQuorumNumerator set");
        assertEq(
            rg.proposalThreshold(), removalGovProposalThreshold, "removalGovProposalThreshold set"
        );
        assertEq(
            rg.lateQuorumVoteExtension(),
            removalGovMinPeriodAfterQuorum,
            "removalGovMinPeriodAfterQuorum set"
        );
    }

    function testNomineeElectionGovDeployment() public {
        DeployParams memory dp = getDeployParams();
        ContractImplementations memory ci = getContractImplementations();

        vm.prank(owner);
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed = fac.deploy(dp, ci);

        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor =
            deployed.nomineeElectionGovernor;

        assertEq(
            nomineeElectionGovernor.nomineeVettingDuration(),
            nomineeVettingDuration,
            "nomineeVettingDuration set"
        );
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
        assertEq(
            nomineeElectionGovernor.quorumNumerator(),
            nomineeQuorumNumerator,
            "quorumNumeratorValue set"
        );
    }

    function testMemberElectionGovDeployment() public {
        DeployParams memory dp = getDeployParams();
        ContractImplementations memory ci = getContractImplementations();

        vm.prank(owner);
        L2SecurityCouncilMgmtFactory.DeployedContracts memory deployed = fac.deploy(dp, ci);

        SecurityCouncilMemberElectionGovernor memberElectionGovernor =
            deployed.memberElectionGovernor;

        //   assertEq(memberElectionGovernor.maxNominees(), firstCohort.length, "maxNominees set");
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
            memberElectionGovernor.fullWeightDuration(),
            fullWeightDuration,
            "fullWeightDuration set"
        );
    }
}
