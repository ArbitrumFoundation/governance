// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/gov-action-contracts/util/OfficeHoursAction.sol";

contract OfficeHoursActionTest is Test {
    OfficeHoursAction public officeHours;

    function setUp() public {
        // Setup office hours for weekdays 9 AM to 5 PM EST
        officeHours = new OfficeHoursAction(9, 17, -5, 1, 5, block.timestamp);
    }

    function testConstructor() public {
        assertEq(officeHours.minLocalHour(), 9);
        assertEq(officeHours.maxLocalHour(), 17);
        assertEq(officeHours.localHourOffset(), -5);
        assertEq(officeHours.minDayOfWeek(), 1);
        assertEq(officeHours.maxDayOfWeek(), 5);
        assertEq(officeHours.minimumTimestamp(), block.timestamp);
    }

    function testPerformDuringOfficeHours() public {
        // Set time to Wednesday (3) at 11 AM EST (16:00 UTC)
        vm.warp(1_672_848_000); // Wednesday, January 4, 2023 16:00:00 UTC
        officeHours.perform(); // Should not revert
    }

    function testPerformOutsideOfficeHours() public {
        // Set time to Thursday (4) at 8 PM EST (00:00 UTC next day)
        vm.warp(1_672_876_800); // Thursday, January 5, 2023 00:00:00 UTC
        vm.expectRevert(OfficeHoursAction.OutsideOfficeHours.selector);
        officeHours.perform();
    }

    function testPerformOnWeekend() public {
        // Set time to Saturday (6) at 11 AM EST (16:00 UTC)
        vm.warp(1_673_107_200); // Saturday, January 7, 2023 16:00:00 UTC
        vm.expectRevert(OfficeHoursAction.OutsideOfficeDays.selector);
        officeHours.perform();
    }

    function testPerformBeforeMinimumTimestamp() public {
        // Set time to before the minimum timestamp
        vm.warp(block.timestamp - 1);
        vm.expectRevert(OfficeHoursAction.MinimumTimestampNotMet.selector);
        officeHours.perform();
    }

    function testInvalidConstructorParameters() public {
        // Test invalid hour range
        vm.expectRevert(OfficeHoursAction.InvalidHourRange.selector);
        new OfficeHoursAction(17, 9, -5, 1, 5, block.timestamp);

        // Test invalid hour start
        vm.expectRevert(OfficeHoursAction.InvalidHourStart.selector);
        new OfficeHoursAction(25, 26, -5, 1, 5, block.timestamp);

        // Test invalid hour end
        vm.expectRevert(OfficeHoursAction.InvalidHourEnd.selector);
        new OfficeHoursAction(9, 25, -5, 1, 5, block.timestamp);

        // Test invalid local hour offset
        vm.expectRevert(OfficeHoursAction.InvalidLocalHourOffset.selector);
        new OfficeHoursAction(9, 17, -13, 1, 5, block.timestamp);

        // Test invalid day of week range
        vm.expectRevert(OfficeHoursAction.InvalidDayOfWeekRange.selector);
        new OfficeHoursAction(9, 17, -5, 5, 1, block.timestamp);

        // Test invalid day of week start
        vm.expectRevert(OfficeHoursAction.InvalidDayOfWeekStart.selector);
        new OfficeHoursAction(9, 17, -5, 0, 5, block.timestamp);

        // Test invalid day of week end
        vm.expectRevert(OfficeHoursAction.InvalidDayOfWeekEnd.selector);
        new OfficeHoursAction(9, 17, -5, 1, 8, block.timestamp);
    }

    function testFuzzOfficeHoursDeployment(
        uint256 _minLocalHour,
        uint256 _maxLocalHour,
        int256 _localHourOffset,
        uint256 _minDayOfWeek,
        uint256 _maxDayOfWeek,
        uint256 _minimumTimestamp
    ) public {
        // Bound the input values to reasonable ranges
        _minLocalHour = bound(_minLocalHour, 0, 23);
        _maxLocalHour = bound(_maxLocalHour, _minLocalHour + 1, 24);
        _localHourOffset = int256(bound(uint256(int256(_localHourOffset)), 0, 26)) - 12; // -12 to 14
        _minDayOfWeek = bound(_minDayOfWeek, 1, 7);
        _maxDayOfWeek = bound(_maxDayOfWeek, _minDayOfWeek, 7);

        // Deploy the contract
        OfficeHoursAction newOfficeHours = new OfficeHoursAction(
            _minLocalHour,
            _maxLocalHour,
            _localHourOffset,
            _minDayOfWeek,
            _maxDayOfWeek,
            _minimumTimestamp
        );

        // Verify that the deployed contract has the correct parameters
        assertEq(newOfficeHours.minLocalHour(), _minLocalHour);
        assertEq(newOfficeHours.maxLocalHour(), _maxLocalHour);
        assertEq(newOfficeHours.localHourOffset(), _localHourOffset);
        assertEq(newOfficeHours.minDayOfWeek(), _minDayOfWeek);
        assertEq(newOfficeHours.maxDayOfWeek(), _maxDayOfWeek);
        assertEq(newOfficeHours.minimumTimestamp(), _minimumTimestamp);
    }

    function testPerformFridayUTCSaturdayLocal() public {
        // Create a new OfficeHoursAction for UTC+9 with office hours on weekdays all day
        OfficeHoursAction jstOfficeHours = new OfficeHoursAction(0, 24, 9, 1, 5, block.timestamp);

        // Set time to Friday 11:00 PM UTC (08:00 AM JST)
        // This is 2023-01-06 23:00:00 UTC, which is 2023-01-07 08:00:00 PST (Saturday)
        vm.warp(1_673_046_000);

        vm.expectRevert(OfficeHoursAction.OutsideOfficeDays.selector);
        jstOfficeHours.perform();
    }

    function testPerformMondayUTCSundayLocal() public {
        // Create a new OfficeHoursAction for UTC-5 with office hours on weekdays all day
        OfficeHoursAction estOfficeHours = new OfficeHoursAction(0, 24, -5, 1, 5, block.timestamp);

        // Set time to Monday 12:30 AM UTC (2:30 PM Monday LIT)
        // This is 2023-01-09 00:30:00 UTC, which is 2023-01-08 19:30:00 EST (Sunday)
        vm.warp(1_673_224_200);

        vm.expectRevert(OfficeHoursAction.OutsideOfficeDays.selector);
        estOfficeHours.perform();
    }
}
