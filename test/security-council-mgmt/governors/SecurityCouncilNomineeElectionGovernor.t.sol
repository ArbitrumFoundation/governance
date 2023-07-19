// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../../../src/security-council-mgmt/Common.sol";

contract SecurityCouncilNomineeElectionGovernorTest is Test {
    SecurityCouncilNomineeElectionGovernor governor;

    uint256 cohortSize = 6;

    SecurityCouncilNomineeElectionGovernor.InitParams initParams =
    SecurityCouncilNomineeElectionGovernor.InitParams({
        firstNominationStartDate: Date({year: 2030, month: 1, day: 1, hour: 0}),
        nomineeVettingDuration: 1 days,
        nomineeVetter: address(0x11),
        securityCouncilManager: ISecurityCouncilManager(address(0x22)),
        securityCouncilMemberElectionGovernor: SecurityCouncilMemberElectionGovernor(
            payable(address(0x33))
            ),
        token: IVotesUpgradeable(address(0x44)),
        owner: address(0x55),
        quorumNumeratorValue: 200,
        votingPeriod: 1 days
    });

    address proxyAdmin = address(0x66);
    address proposer = address(0x77);

    function setUp() public {
        governor = _deployGovernor();

        governor.initialize(initParams);

        vm.warp(1_689_281_541); // july 13, 2023

        _mockGetPastVotes({account: 0x00000000000000000000000000000000000A4B86, votes: 0});
        _mockGetPastTotalSupply(1_000_000_000e18);
        _mockCohortSize(cohortSize);
    }

    function testProperInitialization() public {
        assertEq(governor.nomineeVettingDuration(), initParams.nomineeVettingDuration);
        assertEq(governor.nomineeVetter(), initParams.nomineeVetter);
        assertEq(
            address(governor.securityCouncilManager()), address(initParams.securityCouncilManager)
        );
        assertEq(
            address(governor.securityCouncilMemberElectionGovernor()),
            address(initParams.securityCouncilMemberElectionGovernor)
        );
        assertEq(address(governor.token()), address(initParams.token));
        assertEq(governor.owner(), initParams.owner);
        // assertEq(governor.quorumNumeratorValue(), initParams.quorumNumeratorValue);
        assertEq(governor.votingPeriod(), initParams.votingPeriod);
        // assertEq(governor.firstNominationStartDate(), initParams.firstNominationStartDate);
        (uint256 year, uint256 month, uint256 day, uint256 hour) =
            governor.firstNominationStartDate();
        assertEq(year, initParams.firstNominationStartDate.year);
        assertEq(month, initParams.firstNominationStartDate.month);
        assertEq(day, initParams.firstNominationStartDate.day);
        assertEq(hour, initParams.firstNominationStartDate.hour);
    }

    function testInvalidStartDate() public {
        SecurityCouncilNomineeElectionGovernor.InitParams memory invalidParams = initParams;
        invalidParams.firstNominationStartDate = Date({year: 2022, month: 1, day: 1, hour: 0});

        governor = _deployGovernor();

        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorTiming.StartDateTooEarly.selector
            )
        );
        governor.initialize(invalidParams);

        invalidParams.firstNominationStartDate = Date({year: 2000, month: 13, day: 1, hour: 0});
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorTiming.InvalidStartDate.selector
            )
        );
        governor.initialize(invalidParams);
    }

    function testCreateElection() public {
        // we need to mock getPastVotes for the proposer
        _mockGetPastVotes({account: address(this), votes: 0});

        // we should not be able to create election before first nomination start date
        uint256 expectedStartTimestamp =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0);
        vm.warp(expectedStartTimestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.CreateTooEarly.selector,
                block.timestamp,
                expectedStartTimestamp
            )
        );
        governor.createElection();

        // we should be able to create an election at the timestamp
        vm.warp(expectedStartTimestamp);
        governor.createElection();

        assertEq(governor.electionCount(), 1);

        // we should not be able to create another election before 6 months have passed
        expectedStartTimestamp = _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 6);
        vm.warp(expectedStartTimestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.CreateTooEarly.selector,
                block.timestamp,
                expectedStartTimestamp
            )
        );
        governor.createElection();

        // we should be able to create an election at the timestamp
        vm.warp(expectedStartTimestamp);
        governor.createElection();
    }

    function testAddContender() public {
        // test invalid proposal id
        vm.prank(_contender(0));
        vm.expectRevert("Governor: unknown proposal id");
        governor.addContender(0);

        // make a valid proposal
        uint256 proposalId = _propose();

        // test in other cohort
        _mockCohortIncludes(Cohort.SECOND, _contender(0), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.AccountInOtherCohort.selector,
                Cohort.SECOND,
                _contender(0)
            )
        );
        vm.prank(_contender(0));
        governor.addContender(proposalId);

        // should fail if the proposal is not active
        _mockCohortIncludes(Cohort.SECOND, _contender(0), false);
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalNotActive.selector,
                IGovernorUpgradeable.ProposalState.Succeeded
            )
        );
        vm.prank(_contender(0));
        governor.addContender(proposalId);

        // should succeed if not in other cohort and proposal is active
        vm.roll(governor.proposalDeadline(proposalId));
        assertTrue(governor.state(proposalId) == IGovernorUpgradeable.ProposalState.Active);
        vm.prank(_contender(0));
        governor.addContender(proposalId);

        // check that it correctly mutated the state
        assertTrue(governor.isContender(proposalId, _contender(0)));
    }

    function testSetNomineeVetter() public {
        // should only be callable by owner
        vm.expectRevert("Governor: onlyGovernance");
        governor.setNomineeVetter(address(137));

        // should succeed if called by owner
        vm.prank(initParams.owner);
        governor.relay(
            address(governor),
            0,
            abi.encodeWithSelector(governor.setNomineeVetter.selector, address(137))
        );
        assertEq(governor.nomineeVetter(), address(137));
    }

    function testRelay() public {
        // make sure relay can only be called by owner
        vm.expectRevert("Ownable: caller is not the owner");
        governor.relay(address(0), 0, new bytes(0));

        // make sure relay can be called by owner, and that we can call an onlyGovernance function
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setVotingPeriod.selector, 121_212)
        );
        assertEq(governor.votingPeriod(), 121_212);
    }

    function testExcludeNominee() public {
        uint256 proposalId = _propose();

        // should fail if called by non-nominee vetter
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.OnlyNomineeVetter.selector
            )
        );
        governor.excludeNominee(proposalId, address(0));

        // should fail if called with invalid proposal id
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert("Governor: unknown proposal id");
        governor.excludeNominee(0, _contender(0));

        // should fail if called while proposal is active
        uint256 vettingDeadline = governor.proposalVettingDeadline(proposalId);
        vm.roll(governor.proposalDeadline(proposalId) - 1); // state is active
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalNotSucceededState.selector,
                1 // active
            )
        );
        governor.excludeNominee(proposalId, _contender(0));

        // should fail if called after the vetting period has elapsed
        vm.roll(governor.proposalDeadline(proposalId) + governor.nomineeVettingDuration() + 1);
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalNotInVettingPeriod.selector,
                block.number,
                vettingDeadline
            )
        );
        governor.excludeNominee(proposalId, _contender(0));

        // should fail if the account is not a nominee
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.NotNominee.selector, _contender(0)
            )
        );
        governor.excludeNominee(proposalId, _contender(0));

        // should succeed if called by nominee vetter, proposal is in vetting period, and account is a nominee
        // make sure the account is a nominee
        vm.roll(governor.proposalDeadline(proposalId));
        _addContender(proposalId, _contender(0));
        _mockGetPastVotes(_voter(0), governor.quorum(proposalId));
        _castVoteForContender(proposalId, _voter(0), _contender(0), governor.quorum(proposalId));

        // roll to the end of voting (into the vetting period) and exclude the nominee
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.prank(initParams.nomineeVetter);
        governor.excludeNominee(proposalId, _contender(0));

        // make sure state is correct
        assertTrue(governor.isExcluded(proposalId, _contender(0)));
        assertEq(governor.excludedNomineeCount(proposalId), 1);

        // should fail if contender is excluded twice
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.NomineeAlreadyExcluded.selector,
                _contender(0)
            )
        );
        governor.excludeNominee(proposalId, _contender(0));
    }

    function testIncludeNominee() public {
        // going to skip cases checking the onlyNomineeVetterInVettingPeriod modifier

        uint256 proposalId = _propose();

        // create a nominee
        vm.roll(governor.proposalDeadline(proposalId));
        _addContender(proposalId, _contender(0));
        _mockGetPastVotes(_voter(0), governor.quorum(proposalId));
        _castVoteForContender(proposalId, _voter(0), _contender(0), governor.quorum(proposalId));

        // should fail if the account is already a nominee
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .NomineeAlreadyAdded
                    .selector
            )
        );
        governor.includeNominee(proposalId, _contender(0));

        // should fail if the account is part of the other cohort
        _mockCohortIncludes(Cohort.SECOND, _contender(1), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.AccountInOtherCohort.selector,
                Cohort.SECOND,
                _contender(1)
            )
        );
        vm.prank(initParams.nomineeVetter);
        governor.includeNominee(proposalId, _contender(1));

        // should succeed if the account is not a nominee, we havent reached the target nominee count, and the account is not a member of the opposite cohort
        _mockCohortIncludes(Cohort.SECOND, _contender(1), false);
        vm.prank(initParams.nomineeVetter);
        governor.includeNominee(proposalId, _contender(1));

        // make sure state is correct
        assertTrue(governor.isNominee(proposalId, _contender(1)));
        assertEq(governor.nomineeCount(proposalId), 2);

        // make sure that we can't add more nominees than the target count
        for (uint8 i = 0; i < cohortSize - 2; i++) {
            _mockCohortIncludes(Cohort.SECOND, _contender(i + 2), false);
            vm.prank(initParams.nomineeVetter);
            governor.includeNominee(proposalId, _contender(i + 2));
        }
        _mockCohortIncludes(Cohort.SECOND, _contender(uint8(cohortSize)), false);
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.CompliantNomineeTargetHit.selector
            )
        );
        governor.includeNominee(proposalId, _contender(uint8(cohortSize)));
    }

    function testExecute() public {
        uint256 proposalId = _propose();

        uint256 electionIndex = governor.electionCount() - 1;

        // should fail if called during vetting period
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalInVettingPeriod.selector
            )
        );
        _execute(electionIndex);

        // should fail if there aren't enough compliant nominees
        // make some but not enough
        for (uint8 i = 0; i < cohortSize - 1; i++) {
            _mockCohortIncludes(Cohort.SECOND, _contender(i), false);
            vm.prank(initParams.nomineeVetter);
            governor.includeNominee(proposalId, _contender(i));
        }

        vm.roll(governor.proposalVettingDeadline(proposalId) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.InsufficientCompliantNomineeCount.selector,
                cohortSize - 1
            )
        );
        _execute(electionIndex);

        // should call the member election governor if there are enough compliant nominees
        vm.roll(governor.proposalVettingDeadline(proposalId));
        _mockCohortIncludes(Cohort.SECOND, _contender(uint8(cohortSize - 1)), false);
        vm.prank(initParams.nomineeVetter);
        governor.includeNominee(proposalId, _contender(uint8(cohortSize - 1)));

        vm.roll(governor.proposalVettingDeadline(proposalId) + 1);
        vm.mockCall(
            address(initParams.securityCouncilMemberElectionGovernor), "", abi.encode(proposalId)
        );
        vm.expectCall(
            address(initParams.securityCouncilMemberElectionGovernor),
            abi.encodeWithSelector(
                initParams
                    .securityCouncilMemberElectionGovernor
                    .proposeFromNomineeElectionGovernor
                    .selector,
                electionIndex
            )
        );
        _execute(electionIndex);
    }

    function testCountVote() public {
        uint256 proposalId = _propose();

        // mock some votes for the whole test here
        _mockGetPastVotes(_voter(0), governor.quorum(proposalId) * 2);

        // make sure params is 64 bytes long
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .MustVoteWithParams
                    .selector
            )
        );
        vm.prank(_voter(0));
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(_contender(0))
        });

        // cannot vote for a contender who hasn't added themself
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .NotEligibleContender
                    .selector
            )
        );
        _castVoteForContender(proposalId, _voter(0), _contender(0), 1);

        // can vote for a contender who has added themself
        _addContender(proposalId, _contender(0));
        _castVoteForContender(proposalId, _voter(0), _contender(0), 1);

        // check state
        assertEq(governor.votesUsed(proposalId, _voter(0)), 1);
        assertEq(governor.votesReceived(proposalId, _contender(0)), 1);
        assertTrue(governor.hasVoted(proposalId, _voter(0)));
        assertFalse(governor.isNominee(proposalId, _contender(0)));

        // push the candidate over the line, make sure that any excess votes aren't used
        _castVoteForContender(
            proposalId, _voter(0), _contender(0), governor.quorum(proposalId) + 100
        );
        assertEq(governor.votesUsed(proposalId, _voter(0)), governor.quorum(proposalId));
        assertEq(governor.votesReceived(proposalId, _contender(0)), governor.quorum(proposalId));
        assertTrue(governor.isNominee(proposalId, _contender(0)));
        assertEq(governor.nomineeCount(proposalId), 1);

        // make sure that we can't vote for a nominee
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .NomineeAlreadyAdded
                    .selector
            )
        );
        _castVoteForContender(proposalId, _voter(0), _contender(0), 1);

        // make sure we can't use more votes than we have
        _addContender(proposalId, _contender(1));
        _addContender(proposalId, _contender(2));
        _castVoteForContender(proposalId, _voter(0), _contender(1), governor.quorum(proposalId));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .InsufficientTokens
                    .selector
            )
        );
        _castVoteForContender(proposalId, _voter(0), _contender(2), 1);
    }

    // helpers

    function _voter(uint8 i) internal pure returns (address) {
        return address(uint160(0x1100 + i));
    }

    function _contender(uint8 i) internal pure returns (address) {
        return address(uint160(0x2200 + i));
    }

    function _datePlusMonthsToTimestamp(Date memory date, uint256 months)
        internal
        pure
        returns (uint256)
    {
        return DateTimeLib.dateTimeToTimestamp({
            year: date.year,
            month: date.month + months,
            day: date.day,
            hour: date.hour,
            minute: 0,
            second: 0
        });
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

    function _mockGetPastTotalSupply(uint256 amount) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastTotalSupply.selector),
            abi.encode(amount)
        );
    }

    function _mockCohortIncludes(Cohort cohort, address member, bool ans) internal {
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(
                initParams.securityCouncilManager.cohortIncludes.selector, cohort, member
            ),
            abi.encode(ans)
        );
    }

    function _mockCohortSize(uint256 count) internal {
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(initParams.securityCouncilManager.cohortSize.selector),
            abi.encode(count)
        );

        assertEq(initParams.securityCouncilManager.cohortSize(), count);
    }

    function _execute() internal {
        uint256 electionIndex = governor.electionCount() - 1;
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = ElectionGovernorLib.getProposeArgs(electionIndex);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _execute(uint256 electionIndex) internal {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = ElectionGovernorLib.getProposeArgs(electionIndex);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _addContender(uint256 proposalId, address contender) internal {
        _mockCohortIncludes(Cohort.SECOND, contender, false);

        vm.prank(contender);
        governor.addContender(proposalId);
    }

    function _castVoteForContender(
        uint256 proposalId,
        address voter,
        address contender,
        uint256 votes
    ) internal {
        vm.prank(voter);
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 0,
            reason: "",
            params: abi.encode(contender, votes)
        });
    }

    function _propose() internal returns (uint256) {
        // we need to mock getPastVotes for the proposer
        _mockGetPastVotes({account: address(proposer), votes: 0});

        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0));

        vm.prank(proposer);
        uint256 proposalId = governor.createElection();

        vm.roll(block.number + 1);

        return proposalId;
    }

    function _deployGovernor() internal returns (SecurityCouncilNomineeElectionGovernor) {
        return SecurityCouncilNomineeElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilNomineeElectionGovernor()),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
    }
}
