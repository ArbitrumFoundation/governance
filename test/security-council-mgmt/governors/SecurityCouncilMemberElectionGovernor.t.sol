// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";

contract SecurityCouncilMemberElectionGovernorTest is Test {
    struct InitParams {
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        IVotesUpgradeable token;
        address owner;
        uint256 votingPeriod;
        uint256 maxNominees;
        uint256 fullWeightDurationNumerator;
        uint256 durationDenominator;
    }

    SecurityCouncilMemberElectionGovernor governor;
    address proxyAdmin = address(0x11);

    InitParams initParams = InitParams({
        nomineeElectionGovernor: SecurityCouncilNomineeElectionGovernor(payable(address(0x22))),
        securityCouncilManager: ISecurityCouncilManager(address(0x33)),
        token: IVotesUpgradeable(address(0x44)),
        owner: address(0x55),
        votingPeriod: 2 ** 8,
        maxNominees: 6,
        fullWeightDurationNumerator: 3,
        durationDenominator: 4
    });

    function setUp() public {
        governor = _deployGovernor();

        governor.initialize({
            _nomineeElectionGovernor: initParams.nomineeElectionGovernor,
            _securityCouncilManager: initParams.securityCouncilManager,
            _token: initParams.token,
            _owner: initParams.owner,
            _votingPeriod: initParams.votingPeriod,
            _maxNominees: initParams.maxNominees,
            _fullWeightDurationNumerator: initParams.fullWeightDurationNumerator,
            _durationDenominator: initParams.durationDenominator
        });

        vm.roll(10);
    }

    function testProperInitialization() public {
        assertEq(
            address(governor.nomineeElectionGovernor()), address(initParams.nomineeElectionGovernor)
        );
        assertEq(
            address(governor.securityCouncilManager()), address(initParams.securityCouncilManager)
        );
        assertEq(address(governor.token()), address(initParams.token));
        assertEq(governor.owner(), initParams.owner);
        assertEq(governor.votingPeriod(), initParams.votingPeriod);
        assertEq(governor.maxNominees(), initParams.maxNominees);
        assertEq(governor.fullWeightDurationNumerator(), initParams.fullWeightDurationNumerator);
        assertEq(governor.durationDenominator(), initParams.durationDenominator);
    }

    function testRelay() public {
        // make sure relay can only be called by owner
        vm.expectRevert("Ownable: caller is not the owner");
        governor.relay(address(0), 0, new bytes(0));

        // make sure relay can be called by owner, and that we can call an onlyGovernance function
        vm.prank(initParams.owner);
        governor.relay(address(governor), 0, abi.encodeWithSelector(governor.setVotingPeriod.selector, 121212));
        assertEq(governor.votingPeriod(), 121212);
    }

    function testProposeReverts() public {
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead"
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");

        // should also fail if called by the nominee election governor
        vm.prank(address(initParams.nomineeElectionGovernor));
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead"
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");
    }

    function testOnlyNomineeElectionGovernorCanPropose() public {
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Only the nominee election governor can call this function"
        );
        governor.proposeFromNomineeElectionGovernor();

        _propose(0);
    }
    // todo: test executeElectionResult


    // todo: if cleaner, can write a mock contract for the manager
    // that way we don't have to do the mockCallRevert dance
    // i do like that the manager is always 0x33 in the traces though, but that's whatever
    function testExecute() public {
        // we need to create a proposal, and vote for 6 nominees
        uint256 proposalId = _createProposalAndVoteForSomeNominees(0, initParams.maxNominees);

        // roll to the end of voting
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        // make sure the governor calls the manager with the appropriate calldata
        // we can do this by trying to call execute before and after using mockCall on the manager
        // we still need to mock the call to the nominee election governor for cohortOfMostRecentElection

        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                initParams.nomineeElectionGovernor.cohortOfMostRecentElection.selector
            ),
            abi.encode(Cohort.SEPTEMBER)
        );

        // make all calls to the manager revert by default
        vm.mockCallRevert(address(initParams.securityCouncilManager), "", "");

        bytes32 descriptionHash = keccak256(bytes(governor.nomineeElectionIndexToDescription(0)));

        // before mocking manager, should revert
        // (this just makes sure that execute calls the manager at all)
        vm.expectRevert(bytes(""));
        governor.execute({
            targets: new address[](1),
            values: new uint256[](1),
            calldatas: new bytes[](1),
            descriptionHash: descriptionHash
        });

        // mock the call to the manager
        // calls to the manager with any other calldata will revert
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(
                initParams.securityCouncilManager.executeElectionResult.selector,
                governor.topNominees(proposalId),
                Cohort.SEPTEMBER
            ),
            abi.encode()
        );

        // now that we've mocked the call to the manager, should not revert
        governor.execute({
            targets: new address[](1),
            values: new uint256[](1),
            calldatas: new bytes[](1),
            descriptionHash: descriptionHash
        });
    }

    ////////// SecurityCouncilMemberElectionGovernorCountingUpgradeable tests //////////

    function testSetFullWeightDurationNumeratorAndDurationDenominator() public {
        // non governor should not be able to call
        vm.expectRevert("Governor: onlyGovernance");
        governor.setFullWeightDurationNumeratorAndDurationDenominator(1, 1);

        // governor can call
        vm.prank(address(governor));
        governor.setFullWeightDurationNumeratorAndDurationDenominator(100, 200);

        // make sure the values were set
        assertEq(governor.fullWeightDurationNumerator(), 100);
        assertEq(governor.durationDenominator(), 200);

        // make sure it reverts when numerator is 0
        vm.prank(address(governor));
        vm.expectRevert("SecurityCouncilMemberElectionGovernorCountingUpgradeable: Full weight duration numerator must be > 0");
        governor.setFullWeightDurationNumeratorAndDurationDenominator(0, 1);

        // make sure it reverts when numerator is > denominator
        vm.prank(address(governor));
        vm.expectRevert("SecurityCouncilMemberElectionGovernorCountingUpgradeable: Full weight duration numerator must be <= duration denominator");
        governor.setFullWeightDurationNumeratorAndDurationDenominator(2, 1);
    }

    function testVotesToWeight() public {
        _propose(0);

        uint256 proposalId = governor.nomineeElectionIndexToProposalId(0);
        uint256 startBlock = governor.proposalSnapshot(proposalId);

        // test weight before voting starts (block <= startBlock)
        assertEq(governor.votesToWeight(proposalId, startBlock, 100), 0);

        // test weight right after voting starts (block == startBlock + 1)
        assertEq(governor.votesToWeight(proposalId, startBlock + 1, 100), 100);

        // test weight right before full weight voting ends
        // (block == startBlock + votingPeriod * fullWeightDurationNumerator / durationDenominator)
        assertEq(
            governor.votesToWeight(proposalId, governor.fullWeightVotingDeadline(proposalId), 100),
            100
        );

        // test weight right after full weight voting ends
        assertLe(
            governor.votesToWeight(
                proposalId, governor.fullWeightVotingDeadline(proposalId) + 1, 100
            ),
            100
        );

        // test weight halfway through decreasing weight voting
        uint256 halfwayPoint = (
            governor.fullWeightVotingDeadline(proposalId) + governor.proposalDeadline(proposalId)
        ) / 2;
        assertEq(governor.votesToWeight(proposalId, halfwayPoint, 100), 50);

        // test weight at proposal deadline
        assertEq(governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100), 0);

        // test governor with no decreasing weight voting
        vm.prank(address(governor));
        governor.setFullWeightDurationNumeratorAndDurationDenominator(1, 1);
        assertEq(
            governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100), 100
        );
    }

    function testNoVoteForNonCompliantNominee() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(_nominee(0), false);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(_voter(0));
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Nominee is not compliant"
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(_nominee(0), 100)
        });
    }

    function testCannotUseMoreVotesThanAvailable() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is compliant
        _setCompliantNominee(_nominee(0), true);

        // make sure the voter has some votes
        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        // roll to the start of voting
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // try to use more votes than available
        vm.prank(_voter(0));
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Cannot use more votes than available"
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(_nominee(0), 101)
        });

        // use some amount of votes that is less than available
        vm.prank(_voter(0));
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(_nominee(0), 50)
        });

        // now try to use more votes than available
        vm.prank(_voter(0));
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Cannot use more votes than available"
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(_nominee(0), 51)
        });
    }

    function testHasVotedAndVotesUsed() public {
        uint256 proposalId = _propose(0);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });
        _castVoteForCompliantNominee({
            proposalId: proposalId,
            voter: _voter(0),
            nominee: _nominee(0),
            votes: 100
        });

        assertEq(governor.hasVoted(proposalId, _voter(0)), true);
        assertEq(governor.votesUsed(proposalId, _voter(0)), 100);
    }

    function testVoteSucceededFalse() public {
        // test _voteSucceeded by:
        // - proposing
        // - voting for fewer than 6 nominees
        // - making sure the proposal is defeated

        uint256 proposalId = _createProposalAndVoteForSomeNominees(0, initParams.maxNominees - 1);

        // roll to the end of voting
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        // make sure the proposal failed
        assertTrue(governor.state(proposalId) == IGovernorUpgradeable.ProposalState.Defeated);
    }

    function testVoteSucceededTrue() public {
        // test _voteSucceeded by:
        // - proposing
        // - voting for 6 nominees
        // - making sure the proposal succeeds

        uint256 proposalId = _createProposalAndVoteForSomeNominees(0, initParams.maxNominees);

        // roll to the end of voting
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        // make sure the proposal succeeded
        assertTrue(governor.state(proposalId) == IGovernorUpgradeable.ProposalState.Succeeded);
    }

    function _voter(uint8 i) internal pure returns (address) {
        return address(uint160(0x1100 + i));
    }

    function _nominee(uint8 i) internal pure returns (address) {
        return address(uint160(0x2200 + i));
    }

    function _createProposalAndVoteForSomeNominees(uint256 nomineeElectionIndex, uint256 numNominees) internal returns (uint256) {
        uint256 proposalId = _propose(nomineeElectionIndex);        

        // roll to the start of voting
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // vote for 6 compliant nominees
        for (uint8 i = 0; i < numNominees; i++) {
            // mock the number of votes they have
            _mockGetPastVotes({
                account: _voter(0),
                blockNumber: governor.proposalSnapshot(proposalId),
                votes: numNominees
            });

            _castVoteForCompliantNominee({
                proposalId: proposalId,
                voter: _voter(0),
                nominee: _nominee(i),
                votes: 1
            });
        }

        return proposalId;
    }

    function _mockGetPastVotes(address account, uint256 votes, uint256 blockNumber) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastVotes.selector, account, blockNumber),
            abi.encode(votes)
        );
    }

    function _mockGetPastVotes(address account, uint256 votes) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastVotes.selector, account),
            abi.encode(votes)
        );
    }

    function _setCompliantNominee(address account, bool ans) internal {
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                initParams.nomineeElectionGovernor.isCompliantNomineeForMostRecentElection.selector,
                account
            ),
            abi.encode(ans)
        );
    }

    function _castVoteForCompliantNominee(
        uint256 proposalId,
        address voter,
        address nominee,
        uint256 votes
    ) internal {
        // make sure the nomineeElectionGovernor says the nominee is compliant
        _setCompliantNominee(nominee, true);

        vm.prank(voter);
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(nominee, votes)
        });

        vm.clearMockedCalls();
    }

    function _propose(uint256 nomineeElectionIndex) internal returns (uint256) {
        // we need to mock call to the nominee election governor
        // electionCount() returns 1
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.electionCount.selector),
            abi.encode(nomineeElectionIndex + 1)
        );

        // we need to mock getPastVotes for the nominee election governor
        _mockGetPastVotes({
            account: address(initParams.nomineeElectionGovernor),
            votes: 0
        });

        vm.prank(address(initParams.nomineeElectionGovernor));
        governor.proposeFromNomineeElectionGovernor();

        vm.clearMockedCalls();

        return governor.nomineeElectionIndexToProposalId(nomineeElectionIndex);
    }

    function _deployGovernor() internal returns (SecurityCouncilMemberElectionGovernor) {
        return SecurityCouncilMemberElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberElectionGovernor()),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
    }
}
