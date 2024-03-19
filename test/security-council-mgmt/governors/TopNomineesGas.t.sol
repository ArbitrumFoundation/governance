// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";
import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";
import "./SecurityCouncilNomineeElectionGovernor.t.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @notice This contract tests gas usage of SecurityCouncilMemberElectionGovernor.topNominees()
contract TopNomineesGasTest is Test {
    SecurityCouncilMemberElectionGovernor memberGov;
    SecurityCouncilNomineeElectionGovernor nomineeGov;
    SigUtils sigUtils;

    SecurityCouncilNomineeElectionGovernor.InitParams nomineeInitParams =
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
        quorumNumeratorValue: 10_000 / N,
        votingPeriod: 1 days
    });

    struct MemberInitParams {
        ISecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        IVotesUpgradeable token;
        address owner;
        uint256 votingPeriod;
        uint256 maxNominees;
        uint256 fullWeightDuration;
    }

    SecurityCouncilMemberElectionGovernor governor;

    uint256 fullWeightDuration = 0.5 days;

    address proxyAdmin = address(0x1111);
    address voter = address(0x2222);

    uint256 proposalId;

    uint16 constant N = 500;

    function setUp() public {
        memberGov = SecurityCouncilMemberElectionGovernor(
            payable(_deployProxy(address(new SecurityCouncilMemberElectionGovernor())))
        );
        nomineeGov = SecurityCouncilNomineeElectionGovernor(
            payable(_deployProxy(address(new SecurityCouncilNomineeElectionGovernor())))
        );

        // we need to etch code onto each contract parameter
        _dummyEtch(address(nomineeInitParams.securityCouncilManager));
        _dummyEtch(address(nomineeInitParams.token));

        memberGov.initialize({
            _nomineeElectionGovernor: nomineeGov,
            _securityCouncilManager: nomineeInitParams.securityCouncilManager,
            _token: nomineeInitParams.token,
            _owner: nomineeInitParams.owner,
            _votingPeriod: nomineeInitParams.votingPeriod,
            _fullWeightDuration: fullWeightDuration
        });

        nomineeInitParams.securityCouncilMemberElectionGovernor = memberGov;
        nomineeGov.initialize(nomineeInitParams);

        sigUtils = new SigUtils(address(nomineeGov));

        // mock stuff
        _mockGetPastVotes(voter, 1_000_000_000e18);
        _mockGetPastVotes({account: 0x00000000000000000000000000000000000A4B86, votes: 0});
        _mockGetPastVotes(address(nomineeGov), 0);
        _mockGetPastTotalSupply(1_000_000_000e18);
        _mockCohortSize(6);

        // start a nominee election
        vm.warp(_datePlusMonthsToTimestamp(nomineeInitParams.firstNominationStartDate, 0));
        vm.prank(voter);
        proposalId = nomineeGov.createElection();

        // vote for N nominees
        uint256 quorum = nomineeGov.quorum(proposalId);
        for (uint16 i = 0; i < N; i++) {
            _mockCohortIncludes(Cohort.SECOND, _nominee(i), false);

            vm.roll(nomineeGov.proposalSnapshot(proposalId));
            _addContender(i);

            vm.roll(nomineeGov.proposalDeadline(proposalId));
            vm.prank(voter);
            nomineeGov.castVoteWithReasonAndParams(
                proposalId, 1, "test", abi.encode(_nominee(i), quorum)
            );
        }

        assertEq(nomineeGov.compliantNominees(proposalId).length, N);
        assertEq(nomineeGov.compliantNominees(proposalId)[N - 1], _nominee(N - 1));

        // start the member election
        vm.roll(nomineeGov.proposalVettingDeadline(proposalId) + 1);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = nomineeGov.getProposeArgs(0);
        nomineeGov.execute(targets, values, calldatas, keccak256(bytes(description)));

        // vote for the N nominees to create worst case ordering (ascending order of weight)
        vm.roll(memberGov.proposalSnapshot(proposalId) + 1);
        for (uint16 i = 0; i < N; i++) {
            vm.prank(voter);
            memberGov.castVoteWithReasonAndParams(
                proposalId, 1, "test", abi.encode(_nominee(i), i + 1)
            );
        }

        // call topNominees() in a test case to accurately measure gas
    }

    function testTopNomineesGas() public {
        uint256 g = gasleft();
        memberGov.topNominees(proposalId);
        g -= gasleft();

        assertLt(g, uint256(N) * 10_000);
    }

    function _nomineePrivKey(uint16 i) internal pure returns (uint256) {
        return uint256(0x3300) + i;
    }

    function _nominee(uint16 i) internal pure returns (address) {
        return vm.addr(_nomineePrivKey(i));
    }

    function _dummyEtch(address x) internal {
        vm.etch(x, hex"1234");
    }

    function _addContender(uint16 i) internal {
        bytes memory sig = sigUtils.signAddContenderMessage(proposalId, _nomineePrivKey(i));
        nomineeGov.addContender(proposalId, sig);
    }

    function _deployProxy(address impl) internal returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                impl,
                proxyAdmin,
                bytes("")
            )
        );
    }

    function _mockGetPastVotes(address account, uint256 votes) internal {
        vm.mockCall(
            address(nomineeInitParams.token),
            abi.encodeWithSelector(nomineeInitParams.token.getPastVotes.selector, account),
            abi.encode(votes)
        );
    }

    function _mockGetPastTotalSupply(uint256 amount) internal {
        vm.mockCall(
            address(nomineeInitParams.token),
            abi.encodeWithSelector(nomineeInitParams.token.getPastTotalSupply.selector),
            abi.encode(amount)
        );
    }

    function _mockCohortIncludes(Cohort cohort, address member, bool ans) internal {
        vm.mockCall(
            address(nomineeInitParams.securityCouncilManager),
            abi.encodeWithSelector(
                nomineeInitParams.securityCouncilManager.cohortIncludes.selector, cohort, member
            ),
            abi.encode(ans)
        );
    }

    function _mockCohortSize(uint256 count) internal {
        vm.mockCall(
            address(nomineeInitParams.securityCouncilManager),
            abi.encodeWithSelector(nomineeInitParams.securityCouncilManager.cohortSize.selector),
            abi.encode(count)
        );

        assertEq(nomineeInitParams.securityCouncilManager.cohortSize(), count);
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
}
