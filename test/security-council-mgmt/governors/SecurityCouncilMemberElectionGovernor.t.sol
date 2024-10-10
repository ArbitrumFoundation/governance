// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";
import "../../../src/security-council-mgmt/governors/modules/ElectionGovernor.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";
import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

contract SecurityCouncilMemberElectionGovernorTest is Test {
    struct InitParams {
        ISecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        IVotesUpgradeable token;
        address owner;
        uint256 votingPeriod;
        uint256 maxNominees;
        uint256 fullWeightDuration;
    }

    SecurityCouncilMemberElectionGovernor governor;
    address proxyAdmin = address(0x11);

    InitParams initParams = InitParams({
        nomineeElectionGovernor: ISecurityCouncilNomineeElectionGovernor(payable(address(0x22))),
        securityCouncilManager: ISecurityCouncilManager(address(0x33)),
        token: IVotesUpgradeable(address(0x44)),
        owner: address(0x55),
        votingPeriod: 2 ** 8,
        maxNominees: 6,
        fullWeightDuration: 2 ** 7
    });

    address[] compliantNominees;

    function setUp() public {
        governor = _deployGovernor();

        vm.etch(address(initParams.nomineeElectionGovernor), "0x23");
        vm.etch(address(initParams.securityCouncilManager), "0x34");

        governor.initialize({
            _nomineeElectionGovernor: initParams.nomineeElectionGovernor,
            _securityCouncilManager: initParams.securityCouncilManager,
            _token: initParams.token,
            _owner: initParams.owner,
            _votingPeriod: initParams.votingPeriod,
            _fullWeightDuration: initParams.fullWeightDuration
        });

        _mockCohortSize(initParams.maxNominees);

        compliantNominees = new address[](0);

        vm.roll(10);
    }

    function testInitReverts() public {
        SecurityCouncilMemberElectionGovernor governor2 = _deployGovernor();

        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernor.InvalidDurations.selector,
                initParams.votingPeriod + 1,
                initParams.votingPeriod
            )
        );
        governor2.initialize({
            _nomineeElectionGovernor: initParams.nomineeElectionGovernor,
            _securityCouncilManager: initParams.securityCouncilManager,
            _token: initParams.token,
            _owner: initParams.owner,
            _votingPeriod: initParams.votingPeriod,
            _fullWeightDuration: initParams.votingPeriod + 1
        });
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
        assertEq(governor.fullWeightDuration(), initParams.fullWeightDuration);
        assertEq(governor.proposalThreshold(), 0);
        assertEq(governor.quorum(100), 0);
    }

    // test functions defined in SecurityCouncilMemberElectionGovernor

    function testCastVoteReverts() public {
        vm.expectRevert(SecurityCouncilMemberElectionGovernor.CastVoteDisabled.selector);
        governor.castVote(10, 0);

        vm.expectRevert(SecurityCouncilMemberElectionGovernor.CastVoteDisabled.selector);
        governor.castVoteWithReason(10, 0, "");

        vm.expectRevert(SecurityCouncilMemberElectionGovernor.CastVoteDisabled.selector);
        governor.castVoteBySig(10, 0, 1, bytes32(uint256(0x20)), bytes32(uint256(0x21)));
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

    function testProposeReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(SecurityCouncilMemberElectionGovernor.ProposeDisabled.selector)
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");

        // should also fail if called by the nominee election governor
        vm.prank(address(initParams.nomineeElectionGovernor));
        vm.expectRevert(
            abi.encodeWithSelector(SecurityCouncilMemberElectionGovernor.ProposeDisabled.selector)
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");
    }

    function testOnlyNomineeElectionGovernorCanPropose() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernor.OnlyNomineeElectionGovernor.selector
            )
        );
        governor.proposeFromNomineeElectionGovernor(0);

        _propose(0);
    }

    function testExecute() public {
        // we need to create a proposal, and vote for 6 nominees
        uint256 proposalId = _createProposalAndVoteForSomeNominees(0, initParams.maxNominees);

        // roll to the end of voting
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = governor.getProposeArgs(0);

        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                ElectionGovernor(payable(address(initParams.nomineeElectionGovernor)))
                    .electionIndexToCohort
                    .selector,
                0
            ),
            abi.encode(0)
        );
        vm.mockCall(address(initParams.securityCouncilManager), "", "");
        vm.expectCall(
            address(initParams.securityCouncilManager),
            0,
            abi.encodeWithSelector(
                initParams.securityCouncilManager.replaceCohort.selector,
                governor.topNominees(proposalId),
                Cohort.FIRST
            )
        );
        governor.execute({
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: keccak256(bytes(description))
        });
    }

    function testSetFullWeightDuration() public {
        // ensure onlyGovernance
        vm.expectRevert("Governor: onlyGovernance");
        governor.setFullWeightDuration(0);

        // make sure governor can call
        vm.prank(address(governor));
        governor.setFullWeightDuration(0);
        assertEq(governor.fullWeightDuration(), 0);

        // make sure the duration cannot be longer than votingPeriod
        vm.prank(address(governor));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable
                    .FullWeightDurationGreaterThanVotingPeriod
                    .selector,
                initParams.votingPeriod + 1,
                initParams.votingPeriod
            )
        );
        governor.setFullWeightDuration(initParams.votingPeriod + 1);
    }

    function testNoVoteForNonCompliantNominee() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(proposalId, _nominee(0), false);

        // make sure the voter has enough votes
        address voter = _voter(0);
        _mockGetPastVotes({
            account: voter,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        address nominee = _nominee(0);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voter);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable
                    .NotCompliantNominee
                    .selector,
                nominee
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(nominee, 100)
        });
    }

    function testInvalidParams() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(proposalId, _nominee(0), true);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(_voter(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable
                    .UnexpectedParamsLength
                    .selector,
                32
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(_nominee(0))
        });
    }

    function testNoZeroWeightVotes() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(proposalId, _nominee(0), true);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(_voter(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.ZeroWeightVote.selector,
                block.number,
                0
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(_nominee(0), 0)
        });
    }

    bytes32 private constant _TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256(bytes("SecurityCouncilMemberElectionGovernor"));
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
        uint256 proposalId = _propose(0);
        uint256 voterPrivKey = 0x4173fa62f15e8a9363d4dc11b951722b264fa38fbec64c0f6f14fc1e63f7edd4;
        address voterAddress = vm.addr(voterPrivKey);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(proposalId, _nominee(0), true);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: voterAddress,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        bytes32 dataHash =
            create712Hash(proposalId, 1, "a", abi.encode(_nominee(0), 10), address(governor));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPrivKey, dataHash);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voterAddress);
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "a",
            params: abi.encode(_nominee(0), 10),
            v: v,
            r: r,
            s: s
        });

        bytes32 dataHash2 =
            create712Hash(proposalId, 1, "b", abi.encode(_nominee(0), 10), address(governor));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(voterPrivKey, dataHash2);

        vm.prank(voterAddress);
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "b",
            params: abi.encode(_nominee(0), 10),
            v: v2,
            r: r2,
            s: s2
        });
    }

    function testCastBySigTwice() public {
        uint256 proposalId = _propose(0);
        uint256 voterPrivKey = 0x4173fa62f15e8a9363d4dc11b951722b264fa38fbec64c0f6f14fc1e63f7edd3;
        address voterAddress = vm.addr(voterPrivKey);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(proposalId, _nominee(0), true);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: voterAddress,
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        bytes32 dataHash =
            create712Hash(proposalId, 1, "a", abi.encode(_nominee(0), 10), address(governor));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPrivKey, dataHash);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voterAddress);
        governor.castVoteWithReasonAndParamsBySig({
            proposalId: proposalId,
            support: 1,
            reason: "a",
            params: abi.encode(_nominee(0), 10),
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
            params: abi.encode(_nominee(0), 10),
            v: v,
            r: r,
            s: s
        });
    }

    function testForceSupport() public {
        uint256 proposalId = _propose(0);

        _setCompliantNominee(proposalId, _nominee(0), true);

        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(_voter(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.InvalidSupport.selector, 2
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 2,
            reason: "",
            params: abi.encode(_nominee(0), 100)
        });
    }

    function testCannotUseMoreVotesThanAvailable() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is compliant
        _setCompliantNominee(proposalId, _nominee(0), true);

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
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.InsufficientVotes.selector,
                0,
                101,
                100
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(_nominee(0), 101)
        });

        // use some amount of votes that is less than available
        vm.prank(_voter(0));
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(_nominee(0), 50)
        });

        // now try to use more votes than available
        vm.prank(_voter(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.InsufficientVotes.selector,
                50,
                51,
                100
            )
        );
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(_nominee(0), 51)
        });
    }

    function testSelectTopNomineesFails() public {
        uint16 n = 100;
        uint16 k = 6;

        uint240[] memory weights = TestUtil.randomUint240s(n, 6);
        address[] memory addresses = TestUtil.randomAddresses(n - 1, 7);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.LengthsDontMatch.selector,
                n - 1,
                n
            )
        );
        governor.selectTopNominees(addresses, weights, k);

        weights = TestUtil.randomUint240s(k - 1, 6);
        addresses = TestUtil.randomAddresses(k - 1, 7);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.NotEnoughNominees.selector,
                k - 1,
                k
            )
        );
        governor.selectTopNominees(addresses, weights, k);

        // also test the boundary
        weights = TestUtil.randomUint240s(k, 6);
        addresses = TestUtil.randomAddresses(k, 7);
        governor.selectTopNominees(addresses, weights, k);
    }

    function testSelectTopNominees(uint256 seed) public {
        vm.assume(seed > 0);

        uint16 n = 100;
        uint16 k = 6;

        // make a random list of addresses and weights
        uint240[] memory weights = TestUtil.randomUint240s(n, seed);
        address[] memory addresses = TestUtil.randomAddresses(n, seed - 1);

        // call selectTopNominees
        address[] memory topNominees = governor.selectTopNominees(addresses, weights, k);
        assertEq(topNominees.length, k);

        // pack and sort original, compare to selectTopNominees
        uint256[] memory packed = new uint256[](n);
        for (uint16 i = 0; i < n; i++) {
            packed[i] = (uint256(weights[i]) << 16) | i;
        }

        LibSort.sort(packed);

        for (uint256 i = 0; i < k; i++) {
            assertEq(topNominees[k - i - 1], addresses[packed[n - i - 1] & 0xffff]);
        }
    }

    function testVotesToWeight() public {
        uint256 proposalId = _propose(0);

        uint256 startBlock = governor.proposalSnapshot(proposalId);

        // test weight before voting starts (block <= startBlock)
        assertEq(
            governor.votesToWeight(proposalId, startBlock, 100), 0, "right before voting starts"
        );

        // test weight right after voting starts (block == startBlock + 1)
        assertEq(
            governor.votesToWeight(proposalId, startBlock + 1, 100),
            100,
            "right after voting starts"
        );

        // test weight right before full weight voting ends
        // (block == startBlock + votingPeriod * fullWeightDurationNumerator / durationDenominator)
        assertEq(
            governor.votesToWeight(proposalId, governor.fullWeightVotingDeadline(proposalId), 100),
            100,
            "right before full weight voting ends"
        );

        // test weight right after full weight voting ends
        assertLe(
            governor.votesToWeight(
                proposalId, governor.fullWeightVotingDeadline(proposalId) + 1, 100
            ),
            100,
            "right after full weight voting ends"
        );

        // test weight halfway through decreasing weight voting
        uint256 halfwayPoint = (
            governor.fullWeightVotingDeadline(proposalId) + governor.proposalDeadline(proposalId)
        ) / 2;
        assertEq(
            governor.votesToWeight(proposalId, halfwayPoint, 100),
            50,
            "halfway through decreasing weight voting"
        );

        // test weight at proposal deadline
        assertEq(
            governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100),
            0,
            "at proposal deadline"
        );

        // test governor with no full weight voting
        vm.prank(address(governor));
        governor.setFullWeightDuration(0);
        assertEq(
            governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100),
            0,
            "at proposal deadline, no full weight voting"
        );

        // test governor with no decreasing weight voting
        vm.prank(address(governor));
        governor.setFullWeightDuration(initParams.votingPeriod);
        assertEq(
            governor.votesToWeight(proposalId, governor.proposalDeadline(proposalId), 100),
            100,
            "at proposal deadline, no decreasing weight voting"
        );
    }

    function testMiscVotesViews() public {
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
        assertEq(governor.weightReceived(proposalId, _nominee(0)), 100);
    }

    // helpers

    function _voter(uint8 i) internal pure returns (address) {
        return address(uint160(0x1100 + i));
    }

    function _nominee(uint8 i) internal pure returns (address) {
        return address(uint160(0x2200 + i));
    }

    function _createProposalAndVoteForSomeNominees(
        uint256 nomineeElectionIndex,
        uint256 numNominees
    ) internal returns (uint256) {
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

    function _mockCohortSize(uint256 count) internal {
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(initParams.securityCouncilManager.cohortSize.selector),
            abi.encode(count)
        );

        assertEq(initParams.securityCouncilManager.cohortSize(), count);
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

    function _setCompliantNominee(uint256 proposalId, address account, bool ans) internal {
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                initParams.nomineeElectionGovernor.isCompliantNominee.selector, proposalId, account
            ),
            abi.encode(ans)
        );
        if (ans) {
            // add the nominee to the list in this contract's storage if it isn't already there
            // then mock the call to nomineeElectionGovernor.compliantNominees(uint)
            uint256 index = TestUtil.indexOf(compliantNominees, account);
            if (index == type(uint256).max) {
                compliantNominees.push(account);
            }

            vm.mockCall(
                address(initParams.nomineeElectionGovernor),
                abi.encodeWithSelector(
                    initParams.nomineeElectionGovernor.compliantNominees.selector, proposalId
                ),
                abi.encode(compliantNominees)
            );
        } else {
            // we should remove the nominee from the list in this contract's storage if it is there
            // then mock the call to nomineeElectionGovernor.compliantNominees(uint)
            uint256 index = TestUtil.indexOf(compliantNominees, account);
            if (index != type(uint256).max) {
                compliantNominees[index] = compliantNominees[compliantNominees.length - 1];
                compliantNominees.pop();
            }

            vm.mockCall(
                address(initParams.nomineeElectionGovernor),
                abi.encodeWithSelector(
                    initParams.nomineeElectionGovernor.compliantNominees.selector, proposalId
                ),
                abi.encode(compliantNominees)
            );
        }
    }

    function _castVoteForCompliantNominee(
        uint256 proposalId,
        address voter,
        address nominee,
        uint256 votes
    ) internal {
        // make sure the nomineeElectionGovernor says the nominee is compliant
        _setCompliantNominee(proposalId, nominee, true);

        vm.prank(voter);
        governor.castVoteWithReasonAndParams({
            proposalId: proposalId,
            support: 1,
            reason: "",
            params: abi.encode(nominee, votes)
        });

        // vm.clearMockedCalls();
    }

    function _propose(uint256 nomineeElectionIndex) internal returns (uint256) {
        // we need to mock call to the nominee election governor
        _setUpNomineeGovernorWithIndexInformation(nomineeElectionIndex);

        // we need to mock getPastVotes for the nominee election governor
        _mockGetPastVotes({account: address(initParams.nomineeElectionGovernor), votes: 0});

        vm.prank(address(initParams.nomineeElectionGovernor));
        governor.proposeFromNomineeElectionGovernor(nomineeElectionIndex);

        // vm.clearMockedCalls();
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = governor.getProposeArgs(nomineeElectionIndex);

        return uint256(
            keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description))))
        );
    }

    function _setUpNomineeGovernorWithIndexInformation(uint256 electionIndex) internal {
        // electionCount() returns 1
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernor(
                    payable(address(initParams.nomineeElectionGovernor))
                ).electionCount.selector
            ),
            abi.encode(electionIndex + 1)
        );

        // mock call to electionIndexToDescription
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                ElectionGovernor(payable(address(initParams.nomineeElectionGovernor)))
                    .electionIndexToDescription
                    .selector,
                electionIndex
            ),
            abi.encode(_electionIndexToDescription(electionIndex))
        );

        // mock call to currentCohort
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(SecurityCouncilNomineeElectionGovernor.currentCohort.selector),
            abi.encode(electionIndex % 2)
        );
    }

    function _electionIndexToDescription(uint256 electionIndex)
        internal
        pure
        returns (string memory)
    {
        return
            string.concat("Security Council Election #", StringsUpgradeable.toString(electionIndex));
    }

    function _deployGovernor() internal returns (SecurityCouncilMemberElectionGovernor) {
        return SecurityCouncilMemberElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberElectionGovernor()), proxyAdmin, bytes("")
                )
            )
        );
    }
}
