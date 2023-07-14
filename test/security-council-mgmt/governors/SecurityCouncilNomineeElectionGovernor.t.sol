// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

contract SecurityCouncilNomineeElectionGovernorTest is Test {
    SecurityCouncilNomineeElectionGovernor governor;

    SecurityCouncilNomineeElectionGovernor.InitParams initParams = SecurityCouncilNomineeElectionGovernor.InitParams({
        targetNomineeCount: 6,
        firstNominationStartDate: SecurityCouncilNomineeElectionGovernorTiming.Date({year: 2030, month: 1, day: 1, hour: 0}),
        nomineeVettingDuration: 1 days,
        nomineeVetter: address(0x11),
        securityCouncilManager: ISecurityCouncilManager(address(0x22)),
        securityCouncilMemberElectionGovernor: SecurityCouncilMemberElectionGovernor(payable(address(0x33))),
        token: IVotesUpgradeable(address(0x44)),
        owner: address(0x55),
        quorumNumeratorValue: 10,
        votingPeriod: 1 days
    });

    address proxyAdmin = address(0x66);
    address proposer = address(0x77);


    function setUp() public {
        governor = _deployGovernor();

        governor.initialize(initParams);

        vm.warp(1689281541); // july 13, 2023
    }

    function testProperInitialization() public {
        assertEq(governor.targetNomineeCount(), initParams.targetNomineeCount);
        assertEq(governor.nomineeVettingDuration(), initParams.nomineeVettingDuration);
        assertEq(governor.nomineeVetter(), initParams.nomineeVetter);
        assertEq(address(governor.securityCouncilManager()), address(initParams.securityCouncilManager));
        assertEq(address(governor.securityCouncilMemberElectionGovernor()), address(initParams.securityCouncilMemberElectionGovernor));
        assertEq(address(governor.token()), address(initParams.token));
        assertEq(governor.owner(), initParams.owner);
        // assertEq(governor.quorumNumeratorValue(), initParams.quorumNumeratorValue);
        assertEq(governor.votingPeriod(), initParams.votingPeriod);
        // assertEq(governor.firstNominationStartDate(), initParams.firstNominationStartDate);
        (uint256 year, uint256 month, uint256 day, uint256 hour) = governor.firstNominationStartDate();
        assertEq(year, initParams.firstNominationStartDate.year);
        assertEq(month, initParams.firstNominationStartDate.month);
        assertEq(day, initParams.firstNominationStartDate.day);
        assertEq(hour, initParams.firstNominationStartDate.hour);
    }

    function testInvalidStartDate() public {
        SecurityCouncilNomineeElectionGovernor.InitParams memory invalidParams = initParams;
        invalidParams.firstNominationStartDate = SecurityCouncilNomineeElectionGovernorTiming.Date({year: 2022, month: 1, day: 1, hour: 0});

        governor = _deployGovernor();

        vm.expectRevert(abi.encodeWithSelector(SecurityCouncilNomineeElectionGovernorTiming.StartDateTooEarly.selector));
        governor.initialize(invalidParams);

        invalidParams.firstNominationStartDate = SecurityCouncilNomineeElectionGovernorTiming.Date({year: 2000, month: 13, day: 1, hour: 0});
        vm.expectRevert(abi.encodeWithSelector(SecurityCouncilNomineeElectionGovernorTiming.InvalidStartDate.selector));
        governor.initialize(invalidParams);
    }

    function testCreateElection() public {
        // we need to mock getPastVotes for the proposer
        _mockGetPastVotes({account: address(this), votes: 0});
        
        // we should not be able to create election before first nomination start date
        uint256 expectedStartTimestamp = _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0);
        vm.warp(expectedStartTimestamp - 1);
        vm.expectRevert(abi.encodeWithSelector(SecurityCouncilNomineeElectionGovernor.CreateTooEarly.selector, expectedStartTimestamp));
        governor.createElection();

        // we should be able to create an election at the timestamp
        vm.warp(expectedStartTimestamp);
        governor.createElection();

        assertEq(governor.electionCount(), 1);

        // we should not be able to create another election before 6 months have passed
        expectedStartTimestamp = _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 6);
        vm.warp(expectedStartTimestamp - 1);
        vm.expectRevert(abi.encodeWithSelector(SecurityCouncilNomineeElectionGovernor.CreateTooEarly.selector, expectedStartTimestamp));
        governor.createElection();

        // we should be able to create an election at the timestamp
        vm.warp(expectedStartTimestamp);
        governor.createElection();
    }

    // helpers

    function _voter(uint8 i) internal pure returns (address) {
        return address(uint160(0x1100 + i));
    }

    function _nominee(uint8 i) internal pure returns (address) {
        return address(uint160(0x2200 + i));
    }
    
    function _datePlusMonthsToTimestamp(SecurityCouncilNomineeElectionGovernorTiming.Date memory date, uint256 months) internal pure returns (uint256) {
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

    function _propose() internal returns (uint256) {
        // we need to mock getPastVotes for the proposer
        _mockGetPastVotes({account: address(proposer), votes: 0});

        vm.prank(proposer);
        return governor.createElection();
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
