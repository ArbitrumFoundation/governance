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
    address proxyAdmin = address(100);

    InitParams initParams = InitParams({
        nomineeElectionGovernor: SecurityCouncilNomineeElectionGovernor(payable(address(1))),
        securityCouncilManager: ISecurityCouncilManager(address(2)),
        token: IVotesUpgradeable(address(3)),
        owner: address(4),
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

    function _propose(uint256 nomineeElectionIndex) internal {
        // we need to mock call to the nominee election governor
        // electionCount() returns 1
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.electionCount.selector),
            abi.encode(nomineeElectionIndex + 1)
        );

        vm.prank(address(initParams.nomineeElectionGovernor));
        governor.proposeFromNomineeElectionGovernor();

        vm.clearMockedCalls();
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
