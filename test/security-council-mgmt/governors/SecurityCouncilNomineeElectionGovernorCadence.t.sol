// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

import "../../util/TestUtil.sol";
import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../../../src/security-council-mgmt/Common.sol";

contract SecurityCouncilNomineeElectionGovernorCadenceTest is Test {
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
    address executor = address(0x88);
    address timelock = address(0x99);

    function setUp() public {
        governor = _deployGovernor();

        vm.etch(address(initParams.securityCouncilManager), "0x23");
        vm.etch(address(initParams.securityCouncilMemberElectionGovernor), "0x34");

        governor.initialize(initParams);

        vm.warp(1_689_281_541); // july 13, 2023
    }

    function _deployGovernor() internal returns (SecurityCouncilNomineeElectionGovernor) {
        SecurityCouncilNomineeElectionGovernor implementation =
            new SecurityCouncilNomineeElectionGovernor();
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), proxyAdmin, bytes(""));
        return SecurityCouncilNomineeElectionGovernor(payable(address(proxy)));
    }

    function _datePlusMonthsToTimestamp(Date memory date, uint256 monthsToAdd)
        internal
        pure
        returns (uint256)
    {
        uint256 month = date.month - 1 + monthsToAdd;
        uint256 year = date.year + month / 12;
        month = month % 12 + 1;

        return DateTimeLib.dateTimeToTimestamp({
            year: year,
            month: month,
            day: date.day,
            hour: date.hour,
            minute: 0,
            second: 0
        });
    }

    function testElectionToTimestampWithDefaultCadence() public {
        // Test election 0
        uint256 election0Timestamp = governor.electionToTimestamp(0);
        uint256 expectedElection0 = DateTimeLib.dateTimeToTimestamp({
            year: initParams.firstNominationStartDate.year,
            month: initParams.firstNominationStartDate.month,
            day: initParams.firstNominationStartDate.day,
            hour: initParams.firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });
        assertEq(election0Timestamp, expectedElection0);

        // Test election 1 (6 months later)
        uint256 election1Timestamp = governor.electionToTimestamp(1);
        uint256 expectedElection1 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 6);
        assertEq(election1Timestamp, expectedElection1);

        // Test election 2 (12 months later)
        uint256 election2Timestamp = governor.electionToTimestamp(2);
        uint256 expectedElection2 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 12);
        assertEq(election2Timestamp, expectedElection2);
    }

    function testSetCadenceOnlyGovernance() public {
        // Test that non-governance cannot set cadence
        vm.expectRevert("Governor: onlyGovernance");
        governor.setCadence(3);

        // Test that governance can set cadence via relay (owner)
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 3)
        );
        assertEq(governor.currentCadenceMonths(), 3);
    }

    function testSetCadenceValidation() public {
        // Test that cadence cannot be 0
        vm.prank(initParams.owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecurityCouncilNomineeElectionGovernorTiming.InvalidCadence.selector, 0
            )
        );
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 0)
        );

        // Test that cadence cannot be set at exact election start time
        // First create an election
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(ISecurityCouncilManager.cohortSize.selector),
            abi.encode(cohortSize)
        );

        // Mock the token's getPastVotes function
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector),
            abi.encode(0)
        );

        // Move time forward to after first election start
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0));
        governor.createElection();

        // Try to set cadence at exact start time of current election (should fail)
        vm.prank(initParams.owner);
        vm.expectRevert("Cannot change cadence at exact election start time");
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 3)
        );

        // But should work if we move 1 second forward
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0) + 1);
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 3)
        );
        assertEq(governor.currentCadenceMonths(), 3);

        // Cannot make election start before now
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 2));
        vm.expectRevert("Cannot make next election start time too early");
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 1)
        );
    }

    function testSetCadenceAndElectionTimestamp() public {
        // Mock necessary functions
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(ISecurityCouncilManager.cohortSize.selector),
            abi.encode(cohortSize)
        );
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector),
            abi.encode(0)
        );

        // Set cadence to 3 months before creating any election (will apply to election 1)
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 3)
        );

        // Create first election
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0));
        governor.createElection();

        // Test that election 0 still uses default timing
        uint256 election0Timestamp = governor.electionToTimestamp(0);
        uint256 expectedElection0 = DateTimeLib.dateTimeToTimestamp({
            year: initParams.firstNominationStartDate.year,
            month: initParams.firstNominationStartDate.month,
            day: initParams.firstNominationStartDate.day,
            hour: initParams.firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });
        assertEq(election0Timestamp, expectedElection0);

        // Election 1 uses the new 3-month cadence (since we set it before creating any elections)
        uint256 election1Timestamp = governor.electionToTimestamp(1);
        uint256 expectedElection1 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 3);
        assertEq(election1Timestamp, expectedElection1);

        // Elections 2+ also use 3-month cadence
        uint256 election2Timestamp = governor.electionToTimestamp(2);
        uint256 expectedElection2 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 6); // 3 + 3
        assertEq(election2Timestamp, expectedElection2);

        uint256 election3Timestamp = governor.electionToTimestamp(3);
        uint256 expectedElection3 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 9); // 3 + 3 + 3
        assertEq(election3Timestamp, expectedElection3);

        uint256 election4Timestamp = governor.electionToTimestamp(4);
        uint256 expectedElection4 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 12); // 3 + 3 + 3 + 3
        assertEq(election4Timestamp, expectedElection4);
    }

    function testMultipleCadenceChanges() public {
        // Mock necessary functions
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(ISecurityCouncilManager.cohortSize.selector),
            abi.encode(cohortSize)
        );
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(initParams.securityCouncilMemberElectionGovernor),
            abi.encodeWithSelector(IGovernorUpgradeable.state.selector),
            abi.encode(uint8(7)) // ProposalState.Executed
        );

        // Create election 0
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0));
        governor.createElection();

        // Change cadence to 4 months (will apply to election 1)
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0) + 1);
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 4)
        );

        // Create election 1
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 4));
        governor.createElection();

        // Create election 2 (now uses 4-month cadence)
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 8)); // 4 + 4
        governor.createElection();

        // Change cadence to 2 months (will apply to election 3)
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 8) + 1);
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 2)
        );

        // Create election 3
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 10)); // 4 + 4 + 2
        governor.createElection();

        // Test various election timestamps
        // Election 0: 6 months (default)
        uint256 election0Timestamp = governor.electionToTimestamp(0);
        uint256 expectedElection0 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0);
        assertEq(election0Timestamp, expectedElection0);

        // Election 1: 4 months (due to first cadence change)
        uint256 election1Timestamp = governor.electionToTimestamp(1);
        uint256 expectedElection1 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 4); //  4
        assertEq(election1Timestamp, expectedElection1);

        // Election 2: still uses 4 months
        uint256 election2Timestamp = governor.electionToTimestamp(2);
        uint256 expectedElection2 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 8); // 4 + 4
        assertEq(election2Timestamp, expectedElection2);

        // Election 3: 2 months (due to second cadence change)
        uint256 election3Timestamp = governor.electionToTimestamp(3);
        uint256 expectedElection3 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 10); // 4 + 4 + 2
        assertEq(election3Timestamp, expectedElection3);

        // Election 4: 2 months
        uint256 election4Timestamp = governor.electionToTimestamp(4);
        uint256 expectedElection4 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 12); // 4 + 4 + 2 + 2
        assertEq(election4Timestamp, expectedElection4);
    }

    function testElectionCreationWithCadenceChange() public {
        // Mock necessary functions
        vm.mockCall(
            address(initParams.securityCouncilManager),
            abi.encodeWithSelector(ISecurityCouncilManager.cohortSize.selector),
            abi.encode(cohortSize)
        );

        // Mock the token's getPastVotes function
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector),
            abi.encode(0)
        );

        // Mock member election governor state function (for checking previous election state)
        vm.mockCall(
            address(initParams.securityCouncilMemberElectionGovernor),
            abi.encodeWithSelector(IGovernorUpgradeable.state.selector),
            abi.encode(uint8(7)) // ProposalState.Executed
        );

        // Create election 0
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0));
        governor.createElection();
        assertEq(governor.electionCount(), 1);

        // Change cadence to 3 months (will apply to election 1)
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0) + 1);
        vm.prank(initParams.owner);
        governor.relay(
            address(governor), 0, abi.encodeWithSelector(governor.setCadence.selector, 3)
        );

        // Wait for election 1 (which is now scheduled at month 3 due to cadence change)
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 3));

        // Create election 1 (uses 3-month cadence)
        governor.createElection();
        assertEq(governor.electionCount(), 2);

        // Create election 2 (uses 3-month cadence)
        vm.warp(_datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 6)); // 3 + 3
        governor.createElection();
        assertEq(governor.electionCount(), 3);
    }

    function testFuzzCadenceValues(uint256 cadenceMonths) public {
        // Bound cadence to reasonable values (1-24 months)
        cadenceMonths = bound(cadenceMonths, 1, 24);

        vm.prank(initParams.owner);
        governor.relay(
            address(governor),
            0,
            abi.encodeWithSelector(governor.setCadence.selector, cadenceMonths)
        );

        assertEq(governor.currentCadenceMonths(), cadenceMonths);

        // Test that election timestamp is calculated correctly
        // Election 0 is always at the first nomination start date
        uint256 election0Timestamp = governor.electionToTimestamp(0);
        uint256 expectedElection0 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, 0);
        assertEq(election0Timestamp, expectedElection0);

        // When we set cadence at electionCount=0, it creates a checkpoint for election 0
        // But since election 0's time is fixed at firstNominationStartDate, the cadence
        // effectively applies starting from election 1
        uint256 election1Timestamp = governor.electionToTimestamp(1);
        uint256 expectedElection1 =
            _datePlusMonthsToTimestamp(initParams.firstNominationStartDate, cadenceMonths);
        assertEq(election1Timestamp, expectedElection1);

        // Election 2 also uses the new cadence
        uint256 election2Timestamp = governor.electionToTimestamp(2);
        uint256 expectedElection2 = _datePlusMonthsToTimestamp(
            initParams.firstNominationStartDate, cadenceMonths + cadenceMonths
        );
        assertEq(election2Timestamp, expectedElection2);
    }
}
