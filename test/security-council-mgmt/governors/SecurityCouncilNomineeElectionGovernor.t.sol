// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../../../src/security-council-mgmt/Common.sol";

contract SigUtils is Test {
    bytes32 private constant _HASHED_NAME = keccak256("SecurityCouncilNomineeElectionGovernor");
    bytes32 private constant _HASHED_VERSION = keccak256("1");
    bytes32 private constant _TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    address private immutable _VERIFIER;

    constructor(address verifier) {
        _VERIFIER = verifier;
    }

    function signAddContenderMessage(uint256 proposalId, uint256 privKey)
        public
        view
        returns (bytes memory sig)
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(keccak256("AddContenderMessage(uint256 proposalId)"), proposalId))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        sig = abi.encodePacked(r, s, v);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return _buildDomainSeparator(_TYPE_HASH, _EIP712NameHash(), _EIP712VersionHash());
    }

    function _buildDomainSeparator(bytes32 typeHash, bytes32 nameHash, bytes32 versionHash)
        private
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, _VERIFIER));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function _EIP712NameHash() internal view virtual returns (bytes32) {
        return _HASHED_NAME;
    }

    function _EIP712VersionHash() internal view virtual returns (bytes32) {
        return _HASHED_VERSION;
    }
}

contract SecurityCouncilNomineeElectionGovernorTest is Test {
    SecurityCouncilNomineeElectionGovernor governor;

    uint256 cohortSize = 6;

    SecurityCouncilNomineeElectionGovernor.InitParams initParams =
    SecurityCouncilNomineeElectionGovernor.InitParams({
        firstNominationStartDate: Date({year: 2030, month: 1, day: 1, hour: 0}),
        nomineeVettingDuration: 1 days,
        nomineeVetter: address(0x11),
        securityCouncilManager: ISecurityCouncilManager(address(0x22)),
        securityCouncilMemberElectionGovernor: ISecurityCouncilMemberElectionGovernor(
            payable(address(0x33))
        ),
        token: IVotesUpgradeable(address(0x44)),
        owner: address(0x55),
        quorumNumeratorValue: 20,
        votingPeriod: 1 days
    });

    uint256 votingDelay = 2 days;

    address proxyAdmin = address(0x66);
    address proposer = address(0x77);

    SigUtils sigUtils;

    function setUp() public {
        governor = _deployGovernor();
        sigUtils = new SigUtils(address(governor));

        vm.etch(address(initParams.securityCouncilManager), "0x23");
        vm.etch(address(initParams.securityCouncilMemberElectionGovernor), "0x34");

        governor.initialize(initParams);

        vm.warp(1_689_281_541); // july 13, 2023

        _mockGetPastVotes({account: 0x00000000000000000000000000000000000A4B86, votes: 0});
        _mockGetPastTotalSupply(1_000_000_000e18);
        _mockCohortSize(cohortSize);

        // AIP-X: update governor to add voting delay
        vm.prank(initParams.owner);
        governor.relay(
            address(governor),
            0,
            abi.encodeWithSelector(governor.setVotingDelay.selector, votingDelay)
        );
        assertEq(governor.votingDelay(), votingDelay);
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
        assertEq(governor.proposalThreshold(), 0);
        assertEq(uint256(governor.currentCohort()), uint256(Cohort.FIRST));
        assertEq(uint256(governor.otherCohort()), uint256(Cohort.SECOND));
    }

    function testInvalidInit() public {
        SecurityCouncilNomineeElectionGovernor.InitParams memory invalidParams = initParams;
        invalidParams.firstNominationStartDate = Date({year: 2022, month: 1, day: 1, hour: 0});
        SecurityCouncilNomineeElectionGovernor governorInvalid = _deployGovernor();

        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorTiming.StartDateTooEarly.selector,
                1_640_995_200,
                block.timestamp
            )
        );
        governorInvalid.initialize(invalidParams);

        invalidParams.firstNominationStartDate = Date({year: 2000, month: 13, day: 1, hour: 0});
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorTiming.InvalidStartDate.selector,
                invalidParams.firstNominationStartDate.year,
                invalidParams.firstNominationStartDate.month,
                invalidParams.firstNominationStartDate.day,
                invalidParams.firstNominationStartDate.hour
            )
        );
        governorInvalid.initialize(invalidParams);

        SecurityCouncilNomineeElectionGovernor.InitParams memory invalidQuorumParams = initParams;
        invalidQuorumParams.quorumNumeratorValue = 19;
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.QuorumNumeratorTooLow.selector, 19
            )
        );
        governorInvalid.initialize(invalidQuorumParams);
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
        assertEq(governor.electionCount(), 0);
        assertEq(uint256(governor.currentCohort()), uint256(Cohort.FIRST));
        assertEq(uint256(governor.otherCohort()), uint256(Cohort.SECOND));
        vm.warp(expectedStartTimestamp);
        uint256 firstProposalId = governor.createElection();
        assertEq(governor.electionCount(), 1);
        assertEq(uint256(governor.currentCohort()), uint256(Cohort.FIRST));
        assertEq(uint256(governor.otherCohort()), uint256(Cohort.SECOND));

        // if there has been one election created, the nominee gov will (should) call memberGov.state() to check if the previous election has been executed
        // here we mock it to be not Executed and expect that createElection will revert
        _mockMemberGovState(IGovernorUpgradeable.ProposalState.Succeeded);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.LastMemberElectionNotExecuted.selector,
                firstProposalId
            )
        );
        governor.createElection();

        // now mock state to be executed so we can run other tests
        _mockMemberGovState(IGovernorUpgradeable.ProposalState.Executed);

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
        assertEq(governor.electionCount(), 2);
        assertEq(uint256(governor.currentCohort()), uint256(Cohort.SECOND));
        assertEq(uint256(governor.otherCohort()), uint256(Cohort.FIRST));
    }

    function testAddContender() public {
        bytes memory sig = sigUtils.signAddContenderMessage(0, _contenderPrivKey(0));

        // test invalid proposal id
        vm.expectRevert("Governor: unknown proposal id");
        governor.addContender(0, sig);

        // make a valid proposal
        uint256 proposalId = _propose();
        sig = sigUtils.signAddContenderMessage(proposalId, _contenderPrivKey(0));

        // test in other cohort
        _mockCohortIncludes(Cohort.SECOND, _contender(0), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.AccountInOtherCohort.selector,
                Cohort.SECOND,
                _contender(0)
            )
        );
        governor.addContender(proposalId, sig);

        // should fail if the proposal is not pending
        _mockCohortIncludes(Cohort.SECOND, _contender(0), false);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        assertTrue(governor.state(proposalId) == IGovernorUpgradeable.ProposalState.Active);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalNotPending.selector,
                IGovernorUpgradeable.ProposalState.Active
            )
        );
        governor.addContender(proposalId, sig);

        // should succeed if not in other cohort and proposal is pending
        vm.roll(governor.proposalSnapshot(proposalId));
        assertTrue(governor.state(proposalId) == IGovernorUpgradeable.ProposalState.Pending);
        governor.addContender(proposalId, sig);

        // check that it correctly mutated the state
        assertTrue(governor.isContender(proposalId, _contender(0)));

        // adding again should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.AlreadyContender.selector, _contender(0)
            )
        );
        governor.addContender(proposalId, sig);
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
        vm.roll(governor.proposalSnapshot(proposalId));
        _addContender(proposalId, 0);
        vm.roll(governor.proposalDeadline(proposalId));
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
        vm.roll(governor.proposalSnapshot(proposalId));
        _addContender(proposalId, 0);
        vm.roll(governor.proposalDeadline(proposalId));
        _mockGetPastVotes(_voter(0), governor.quorum(proposalId));
        _castVoteForContender(proposalId, _voter(0), _contender(0), governor.quorum(proposalId));

        // should fail if called by non nominee vetter
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.OnlyNomineeVetter.selector
            )
        );
        governor.includeNominee(proposalId, _contender(0));

        // should fail if state is not Succeeded
        vm.roll(governor.proposalDeadline(proposalId));
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalNotSucceededState.selector,
                1 // active
            )
        );
        governor.includeNominee(proposalId, _contender(0));

        // should fail if the account is already a nominee
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .NomineeAlreadyAdded
                    .selector,
                _contender(0)
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
        // should succeed even if past the vetting deadline
        _mockCohortIncludes(Cohort.SECOND, _contender(1), false);
        vm.roll(governor.proposalVettingDeadline(proposalId) + 1);
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
                SecurityCouncilNomineeElectionGovernor.CompliantNomineeTargetHit.selector,
                cohortSize,
                cohortSize
            )
        );
        governor.includeNominee(proposalId, _contender(uint8(cohortSize)));

        vm.prank(initParams.nomineeVetter);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        governor.includeNominee(proposalId, address(0));
    }

    function testExecute() public {
        uint256 proposalId = _propose();

        uint256 electionIndex = governor.electionCount() - 1;

        // should fail if called during vetting period
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        _execute(
            electionIndex,
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalInVettingPeriod.selector,
                block.number,
                governor.proposalVettingDeadline(proposalId)
            )
        );

        // should fail if there aren't enough compliant nominees
        // make some but not enough
        for (uint8 i = 0; i < cohortSize - 1; i++) {
            _mockCohortIncludes(Cohort.SECOND, _contender(i), false);
            vm.prank(initParams.nomineeVetter);
            governor.includeNominee(proposalId, _contender(i));
        }

        vm.roll(governor.proposalVettingDeadline(proposalId) + 1);
        _execute(
            electionIndex,
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.InsufficientCompliantNomineeCount.selector,
                cohortSize - 1,
                cohortSize
            )
        );

        // should call the member election governor if there are enough compliant nominees
        vm.roll(governor.proposalVettingDeadline(proposalId));
        _mockCohortIncludes(Cohort.SECOND, _contender(uint8(cohortSize - 1)), false);
        vm.prank(initParams.nomineeVetter);
        governor.includeNominee(proposalId, _contender(uint8(cohortSize - 1)));

        vm.roll(governor.proposalVettingDeadline(proposalId) + 1);

        // mock the return value as a different proposal id
        vm.mockCall(address(initParams.securityCouncilMemberElectionGovernor), "", abi.encode(100));
        _execute(
            electionIndex,
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor.ProposalIdMismatch.selector, proposalId, 100
            )
        );

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
        _execute(electionIndex, "");

        assertEq(uint256(governor.currentCohort()), uint256(Cohort.FIRST));
        assertEq(uint256(governor.otherCohort()), uint256(Cohort.SECOND));
    }

    function testCountVote() public {
        uint256 proposalId = _propose();

        // mock some votes for the whole test here
        _mockGetPastVotes(_voter(0), governor.quorum(proposalId) * 2);

        // add some contenders
        _addContender(proposalId, 0);
        _addContender(proposalId, 1);
        _addContender(proposalId, 2);

        // roll to active state
        vm.roll(governor.proposalDeadline(proposalId));

        // make sure params is 64 bytes long
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .UnexpectedParamsLength
                    .selector,
                32
            )
        );
        vm.prank(_voter(0));
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(_contender(0))
        });

        // cannot vote for a contender who hasn't added themself
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .NotEligibleContender
                    .selector,
                _contender(3)
            )
        );
        _castVoteForContender(proposalId, _voter(0), _contender(3), 1);

        // can vote for a contender who has added themself
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
                    .selector,
                _contender(0)
            )
        );
        _castVoteForContender(proposalId, _voter(0), _contender(0), 1);

        // make sure we can't use more votes than we have
        _castVoteForContender(proposalId, _voter(0), _contender(1), governor.quorum(proposalId));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable
                    .InsufficientTokens
                    .selector,
                1,
                governor.quorum(proposalId) * 2,
                governor.quorum(proposalId) * 2
            )
        );
        _castVoteForContender(proposalId, _voter(0), _contender(2), 1);
    }

    bytes32 private constant _TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256(bytes("SecurityCouncilNomineeElectionGovernor"));
    bytes32 private constant _VERSION_HASH = keccak256(bytes("1"));
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    function _hashTypedDataV4(bytes32 structHash, address targetAddress)
        internal
        view
        virtual
        returns (bytes32)
    {
        bytes32 domainHash = keccak256(
            abi.encode(_TYPE_HASH, _NAME_HASH, _VERSION_HASH, block.chainid, targetAddress)
        );
        return ECDSAUpgradeable.toTypedDataHash(domainHash, structHash);
    }

    function create712Hash(
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params,
        address targetAddress
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    EXTENDED_BALLOT_TYPEHASH,
                    proposalId,
                    support,
                    keccak256(bytes(reason)),
                    keccak256(params)
                )
            ),
            targetAddress
        );
    }

    function testCastBySig() public {
        uint256 proposalId = _propose();
        uint256 voterPrivKey = 0x4173fa62f15e8a9363d4dc11b951722b264fa38fbec64c0f6f14fc1e63f7edd4;
        address voterAddress = vm.addr(voterPrivKey);

        _addContender(proposalId, 0);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: voterAddress,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        bytes32 dataHash =
            create712Hash(proposalId, 1, "a", abi.encode(_contender(0), 10), address(governor));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPrivKey, dataHash);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voterAddress);
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "a",
            params: abi.encode(_contender(0), 10),
            v: v,
            r: r,
            s: s
        });

        bytes32 dataHash2 =
            create712Hash(proposalId, 1, "b", abi.encode(_contender(0), 10), address(governor));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(voterPrivKey, dataHash2);

        vm.prank(voterAddress);
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "b",
            params: abi.encode(_contender(0), 10),
            v: v2,
            r: r2,
            s: s2
        });
    }

    function testCastBySigTwice() public {
        uint256 proposalId = _propose();
        uint256 voterPrivKey = 0x4173fa62f15e8a9363d4dc11b951722b264fa38fbec64c0f6f14fc1e63f7edd3;
        address voterAddress = vm.addr(voterPrivKey);

        _addContender(proposalId, 0);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: voterAddress,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        bytes32 dataHash =
            create712Hash(proposalId, 1, "a", abi.encode(_contender(0), 10), address(governor));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPrivKey, dataHash);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voterAddress);
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "a",
            params: abi.encode(_contender(0), 10),
            v: v,
            r: r,
            s: s
        });

        vm.prank(voterAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                ElectionGovernor.VoteAlreadyCast.selector,
                voterAddress,
                proposalId,
                keccak256(abi.encodePacked(dataHash, voterAddress))
            )
        );
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "a",
            params: abi.encode(_contender(0), 10),
            v: v,
            r: r,
            s: s
        });
    }

    function testProposeFails() public {
        vm.expectRevert(
            abi.encodeWithSelector(SecurityCouncilNomineeElectionGovernor.ProposeDisabled.selector)
        );
        governor.propose(new address[](1), new uint256[](1), new bytes[](1), "");
    }

    function testCastVoteReverts() public {
        vm.expectRevert(SecurityCouncilNomineeElectionGovernor.CastVoteDisabled.selector);
        governor.castVote(10, 0);

        vm.expectRevert(SecurityCouncilNomineeElectionGovernor.CastVoteDisabled.selector);
        governor.castVoteWithReason(10, 0, "");

        vm.expectRevert(SecurityCouncilNomineeElectionGovernor.CastVoteDisabled.selector);
        governor.castVoteBySig(10, 0, 1, bytes32(uint256(0x20)), bytes32(uint256(0x21)));
    }

    function testForceSupport() public {
        uint256 proposalId = _propose();

        _addContender(proposalId, 0);

        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(_voter(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorCountingUpgradeable.InvalidSupport.selector, 2
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 2,
            reason: "",
            params: abi.encode(_contender(0), 100)
        });
    }

    // helpers

    function _voter(uint8 i) internal pure returns (address) {
        return address(uint160(0x1100 + i));
    }

    function _contender(uint8 i) internal pure returns (address) {
        return vm.addr(_contenderPrivKey(i));
    }

    function _contenderPrivKey(uint8 i) internal pure returns (uint256) {
        return 0x2200 + i;
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

    /// @dev Mocks the state of the governor contract (for all proposal ids)
    function _mockMemberGovState(IGovernorUpgradeable.ProposalState state) internal {
        vm.mockCall(
            address(initParams.securityCouncilMemberElectionGovernor),
            abi.encodeWithSelector(IGovernorUpgradeable.state.selector),
            abi.encode(state)
        );
    }

    function _execute(uint256 electionIndex, bytes memory revertMsg) internal {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = governor.getProposeArgs(electionIndex);
        if (revertMsg.length != 0) {
            vm.expectRevert(revertMsg);
        }
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _addContender(uint256 proposalId, uint8 contender) internal {
        uint256 privKey = _contenderPrivKey(contender);
        address addr = _contender(contender);
        _mockCohortIncludes(Cohort.SECOND, addr, false);
        bytes memory sig = sigUtils.signAddContenderMessage(proposalId, privKey);
        governor.addContender(proposalId, sig);
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
            support: 1,
            reason: "",
            params: abi.encode(contender, votes)
        });
    }

    function _propose() internal returns (uint256) {
        // mock the member gov state to be executed
        _mockMemberGovState(IGovernorUpgradeable.ProposalState.Executed);

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
                    address(new SecurityCouncilNomineeElectionGovernor()), proxyAdmin, bytes("")
                )
            )
        );
    }
}
