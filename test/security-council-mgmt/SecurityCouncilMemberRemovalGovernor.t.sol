// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilMemberRemovalGovernor.sol";
import "../../src/security-council-mgmt/interfaces/ISecurityCouncilManager.sol";
import "../../src/L2ArbitrumToken.sol";
import "./../util/TestUtil.sol";

import "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

address constant memberToRemove = address(999_999);

contract MockSecurityCouncilManager {
    function firstCohortIncludes(address x) external returns (bool) {
        return x == memberToRemove;
    }

    function secondCohortIncludes(address x) external returns (bool) {
        return false;
    }
}

contract SecurityCouncilMemberRemovalGovernorTest is Test {
    address l1TokenAddress = address(137);
    uint256 initialTokenSupply = 50_000;
    address tokenOwner = address(238);
    uint256 votingPeriod = 180_000;
    uint256 votingDelay = 10;
    address excludeListMember = address(339);
    uint256 quorumNumerator = 500;
    uint256 proposalThreshold = 0;
    uint64 initialVoteExtension = 5;
    uint256 proposalExpirationBlocks = 15;

    address[] stubAddressArray = [address(640)];
    address someRando = address(741);
    address owner = address(842);
    uint256 voteSuccessNumerator = 6000;
    ISecurityCouncilManager securityCouncilManager;
    SecurityCouncilMemberRemovalGovernor scRemovalGov;

    address[] validTargets = new address[](1);
    uint256[] validValues = new uint256[](1);

    bytes[] validCallDatas = new bytes[](1);

    string description = "xyz";

    address rando = address(98_765);

    uint256 newVoteSuccessNumerator = 3;

    address secondTokenHolder = address(23_456_789);
    address thirdTokenHolder = address(3_389_234);

    function setUp() public returns (SecurityCouncilMemberRemovalGovernor) {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);

        vm.startPrank(tokenOwner);
        token.delegate(tokenOwner);
        token.transfer(secondTokenHolder, 19_999);
        token.transfer(thirdTokenHolder, 5001);
        vm.stopPrank();

        vm.prank(secondTokenHolder);
        token.delegate(secondTokenHolder);

        vm.prank(thirdTokenHolder);
        token.delegate(thirdTokenHolder);

        scRemovalGov = SecurityCouncilMemberRemovalGovernor(
            payable(TestUtil.deployProxy(address(new SecurityCouncilMemberRemovalGovernor())))
        );

        securityCouncilManager = ISecurityCouncilManager(address(new MockSecurityCouncilManager()));
        scRemovalGov.initialize(
            voteSuccessNumerator,
            securityCouncilManager,
            token,
            owner,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension,
            proposalExpirationBlocks
        );
        validTargets[0] = address(securityCouncilManager);
        validCallDatas[0] =
            abi.encodeWithSelector(ISecurityCouncilManager.removeMember.selector, memberToRemove);

        return scRemovalGov;
    }

    function testInitFails() public {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);
        SecurityCouncilMemberRemovalGovernor scRemovalGov2 = SecurityCouncilMemberRemovalGovernor(
            payable(TestUtil.deployProxy(address(new SecurityCouncilMemberRemovalGovernor())))
        );
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, address(123_256_123)));
        scRemovalGov2.initialize(
            voteSuccessNumerator,
            ISecurityCouncilManager(address(123_256_123)),
            token,
            owner,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension,
            proposalExpirationBlocks
        );
    }

    function testSuccessfulProposalAndCantAbstain() public {
        uint256 proposalId =
            scRemovalGov.propose(validTargets, validValues, validCallDatas, description);

        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Pending,
            "proposal created"
        );
        vm.roll(block.number + votingDelay + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SecurityCouncilMemberRemovalGovernor.AbstainDisallowed.selector)
        );
        scRemovalGov.castVote(proposalId, 2);
    }

    function testRelay() public {
        // make sure relay can only be called by owner
        vm.expectRevert("Ownable: caller is not the owner");
        scRemovalGov.relay(address(0), 0, new bytes(0));

        // make sure relay can be called by owner, and that we can call an onlyGovernance function
        vm.prank(owner);
        scRemovalGov.relay(
            address(scRemovalGov),
            0,
            abi.encodeWithSelector(scRemovalGov.setVotingPeriod.selector, 121_212)
        );
        assertEq(scRemovalGov.votingPeriod(), 121_212);
    }

    function testProposalCreationTargetRestriction() public {
        validTargets[0] = rando;
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.TargetNotManager.selector, rando
            )
        );
        scRemovalGov.propose(validTargets, validValues, validCallDatas, description);
    }

    function testProposalCreationValuesRestriction() public {
        validValues[0] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(SecurityCouncilMemberRemovalGovernor.ValueNotZero.selector, 1)
        );

        scRemovalGov.propose(validTargets, validValues, validCallDatas, description);
    }

    function testProposalCreationCallRestriction() public {
        validCallDatas[0] =
            abi.encodeWithSelector(ISecurityCouncilManager.addMember.selector, memberToRemove);

        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.CallNotRemoveMember.selector,
                ISecurityCouncilManager.addMember.selector,
                ISecurityCouncilManager.removeMember.selector
            )
        );
        scRemovalGov.propose(validTargets, validValues, validCallDatas, description);
    }

    function testProposalCreationCallParamRestriction() public {
        validCallDatas[0] =
            abi.encodeWithSelector(ISecurityCouncilManager.removeMember.selector, rando);

        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.MemberNotFound.selector, rando
            )
        );
        scRemovalGov.propose(validTargets, validValues, validCallDatas, description);
    }

    function testProposalCreationTargetLen() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.InvalidOperationsLength.selector, 2
            )
        );
        scRemovalGov.propose(new address[](2), validValues, validCallDatas, description);
    }

    function testProposalCreationUnexpectedCallDataLen() public {
        validCallDatas[0] = abi.encodeWithSelector(ISecurityCouncilManager.removeMember.selector);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.UnexpectedCalldataLength.selector, 4
            )
        );
        scRemovalGov.propose(validTargets, validValues, validCallDatas, description);
    }

    function testSetVoteSuccessNumeratorAffordance() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        scRemovalGov.setVoteSuccessNumerator(newVoteSuccessNumerator);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.InvalidVoteSuccessNumerator.selector, 0
            )
        );
        scRemovalGov.setVoteSuccessNumerator(0);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberRemovalGovernor.InvalidVoteSuccessNumerator.selector, 10_001
            )
        );
        scRemovalGov.setVoteSuccessNumerator(10_001);
    }

    function testSetVoteSuccessNumerator() public {
        vm.prank(owner);
        scRemovalGov.setVoteSuccessNumerator(newVoteSuccessNumerator);
        assertEq(
            scRemovalGov.voteSuccessNumerator(),
            newVoteSuccessNumerator,
            "newVoteSuccessNumerator set"
        );
    }

    function testSuccessNumeratorInsufficientVotes() public {
        uint256 proposalId =
            scRemovalGov.propose(validTargets, validValues, validCallDatas, description);

        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Pending,
            "proposal created"
        );
        vm.roll(block.number + votingDelay + 1);
        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Active,
            "proposal active"
        );

        vm.prank(tokenOwner);
        scRemovalGov.castVote(proposalId, 1);

        vm.prank(secondTokenHolder);
        scRemovalGov.castVote(proposalId, 0);

        vm.prank(thirdTokenHolder);
        scRemovalGov.castVote(proposalId, 0);

        vm.roll(block.number + votingPeriod + 1);

        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Defeated,
            "prposal fails if 50% for in favor"
        );
    }

    function testSuccessNumeratorSufficientVotes() public {
        uint256 proposalId =
            scRemovalGov.propose(validTargets, validValues, validCallDatas, description);

        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Pending,
            "proposal created"
        );
        vm.roll(block.number + votingDelay + 1);
        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Active,
            "proposal active"
        );

        vm.prank(tokenOwner);
        scRemovalGov.castVote(proposalId, 1);

        vm.prank(secondTokenHolder);
        scRemovalGov.castVote(proposalId, 0);

        vm.prank(thirdTokenHolder);
        scRemovalGov.castVote(proposalId, 1);

        vm.roll(block.number + votingPeriod + 1);

        assertTrue(
            scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Succeeded,
            "proposal succeeds when over 60% vote in favor"
        );
    }

    function testSeparateSelector() public {
        bytes memory calldataWithSelector = abi.encodeWithSelector(
            MockSecurityCouncilManager.firstCohortIncludes.selector, memberToRemove
        );
        (bytes4 selector, bytes memory data) = scRemovalGov.separateSelector(calldataWithSelector);
        assertEq(
            selector,
            MockSecurityCouncilManager.firstCohortIncludes.selector,
            "separateSelector returns correct selector"
        );
        assertEq(data, abi.encode(memberToRemove), "separateSelector returns correct data");
        assertEq(
            abi.decode(data, (address)), memberToRemove, "separateSelector decodes to correct data"
        );
    }

    function testProposalExpirationDeadline() public {
        uint256 proposalId =
            scRemovalGov.propose(validTargets, validValues, validCallDatas, description);

        assertEq(
            scRemovalGov.proposalExpirationDeadline(proposalId),
            scRemovalGov.proposalDeadline(proposalId) + scRemovalGov.proposalExpirationBlocks()
        );
    }

    function testProposalDoesExpire() public {
        uint256 proposalId =
            scRemovalGov.propose(validTargets, validValues, validCallDatas, description);

        // make the proposal succeed
        vm.roll(scRemovalGov.proposalDeadline(proposalId));
        vm.prank(tokenOwner);
        scRemovalGov.castVote(proposalId, 1);

        // roll to right before expiration
        vm.roll(scRemovalGov.proposalExpirationDeadline(proposalId));

        assertTrue(scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Succeeded);

        // roll to the end of the expiration period
        vm.roll(scRemovalGov.proposalExpirationDeadline(proposalId) + 1);

        assertTrue(scRemovalGov.state(proposalId) == IGovernorUpgradeable.ProposalState.Expired);
    }
}
