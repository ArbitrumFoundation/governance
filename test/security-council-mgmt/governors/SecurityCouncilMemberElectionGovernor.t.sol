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
        uint256 fullWeightDuration;
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
        fullWeightDuration: 2 ** 7
    });

    address[] compliantNominees;

    function setUp() public {
        governor = _deployGovernor();

        governor.initialize({
            _nomineeElectionGovernor: initParams.nomineeElectionGovernor,
            _securityCouncilManager: initParams.securityCouncilManager,
            _token: initParams.token,
            _owner: initParams.owner,
            _votingPeriod: initParams.votingPeriod,
            _fullWeightDuration: initParams.fullWeightDuration
        });

        _mockTargetNomineeCount(initParams.maxNominees);

        compliantNominees = new address[](0);

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
        assertEq(governor.fullWeightDuration(), initParams.fullWeightDuration);
    }

    // test functions defined in SecurityCouncilMemberElectionGovernor

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
        governor.proposeFromNomineeElectionGovernor();

        _propose(0);
    }


    function testSelectTopNominees() public {
        // make a random list of addresses and weights
        uint256[] memory weights = TestUtil.randomArray(100, 0);
        address[] memory addresses = TestUtil.randomAddresses(100, 1);

        // call selectTopNominees
        address[] memory topNominees = governor.selectTopNominees(addresses, weights, 6);

        // pack and sort original, compare to selectTopNominees
        uint256[] memory packed = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            packed[i] = (weights[i] << 16) | i;
        }

        LibSort.sort(packed);

        for (uint256 i = 0; i < 6; i++) {
            assertEq(topNominees[5 - i], addresses[packed[99 - i] & 0xffff]);
        }
    }

    function testExecute() public {
        // we need to create a proposal, and vote for 6 nominees
        uint256 proposalId = _createProposalAndVoteForSomeNominees(0, initParams.maxNominees);

        // roll to the end of voting
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        bytes32 descriptionHash =
            keccak256(bytes(initParams.nomineeElectionGovernor.electionIndexToDescription(0)));

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
            targets: new address[](1),
            values: new uint256[](1),
            calldatas: new bytes[](1),
            descriptionHash: descriptionHash
        });
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

    function testNoVoteForNonCompliantNominee() public {
        uint256 proposalId = _propose(0);

        // make sure the nomineeElectionGovernor says the nominee is not compliant
        _setCompliantNominee(proposalId, _nominee(0), false);

        // make sure the voter has enough votes
        _mockGetPastVotes({
            account: _voter(0),
            blockNumber: governor.proposalSnapshot(proposalId),
            votes: 100
        });

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(_voter(0));
        // vm.expectRevert(
        //     "SecurityCouncilMemberElectionGovernorCountingUpgradeable: Nominee is not compliant"
        // );
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable
                    .NotCompliantNominee
                    .selector
            )
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
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.InsufficientVotes.selector
            )
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
            abi.encodeWithSelector(
                SecurityCouncilMemberElectionGovernorCountingUpgradeable.InsufficientVotes.selector
            )
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

    function _mockTargetNomineeCount(uint256 count) internal {
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.targetNomineeCount.selector),
            abi.encode(count)
        );

        assertEq(initParams.nomineeElectionGovernor.targetNomineeCount(), count);
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
            support: 0,
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
        governor.proposeFromNomineeElectionGovernor();

        // vm.clearMockedCalls();

        return uint256(
            keccak256(
                abi.encode(
                    new address[](1),
                    new uint256[](1),
                    new bytes[](1),
                    keccak256(bytes(_electionIndexToDescription(nomineeElectionIndex)))
                )
            )
        );
    }

    function _setUpNomineeGovernorWithIndexInformation(uint256 electionIndex) internal {
        // electionCount() returns 1
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.electionCount.selector),
            abi.encode(electionIndex + 1)
        );

        // mock call to electionIndexToDescription
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(
                initParams.nomineeElectionGovernor.electionIndexToDescription.selector,
                electionIndex
            ),
            abi.encode(_electionIndexToDescription(electionIndex))
        );

        // mock call to currentCohort
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.currentCohort.selector),
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
                    address(new SecurityCouncilMemberElectionGovernor()),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
    }
}
