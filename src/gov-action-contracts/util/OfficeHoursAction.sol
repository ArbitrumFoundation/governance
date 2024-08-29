// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Action that requires the current time to be within office hours. Should be included as an L1 action in proposal data.
contract OfficeHoursAction {
    /// @notice The minimum hour (inclusive) to execute the action on. 0 = midnight, 23 = 11pm
    /// @dev We assume the range would not cross local midnight
    uint256 public immutable minLocalHour;
    /// @notice The maximum hour (exclusive) to execute the action on. 0 = midnight, 23 = 11pm
    /// @dev We assume the range would not cross local midnight
    uint256 public immutable maxLocalHour;

    /// @notice The offset from UTC to local time. e.g. -5 for EST, -4 for EDT
    int256 public immutable localHourOffset;

    /// @notice The minimum day of week (inclusive) to execute the action on. 1 = Monday, 7 = Sunday
    /// @dev We assume the range would not cross weekends
    uint256 public immutable minDayOfWeek;
    /// @notice The maximum day of week (inclusive) to execute the action on. 1 = Monday, 7 = Sunday
    /// @dev We assume the range would not cross weekends
    uint256 public immutable maxDayOfWeek;

    /// @notice The minimum timestamp to execute the action on
    uint256 public immutable minimumTimestamp;

    error InvalidHourRange();
    error InvalidHourStart();
    error InvalidHourEnd();
    error InvalidLocalHourOffset();
    error InvalidDayOfWeekRange();
    error InvalidDayOfWeekStart();
    error InvalidDayOfWeekEnd();
    error MinimumTimestampNotMet();
    error OutsideOfficeDays();
    error OutsideOfficeHours();

    constructor(
        uint256 _minLocalHour,
        uint256 _maxLocalHour,
        int256 _localHourOffset,
        uint256 _minDayOfWeek,
        uint256 _maxDayOfWeek,
        uint256 _minimumTimestamp
    ) {
        if (_maxLocalHour <= _minLocalHour) revert InvalidHourRange();
        if (_minLocalHour > 24) revert InvalidHourStart();
        if (_maxLocalHour == 0 || _maxLocalHour > 24) revert InvalidHourEnd();
        if (_localHourOffset < -12 || _localHourOffset > 14) revert InvalidLocalHourOffset();
        if (_minDayOfWeek > _maxDayOfWeek) revert InvalidDayOfWeekRange();
        if (_minDayOfWeek == 0 || _minDayOfWeek > 7) revert InvalidDayOfWeekStart();
        if (_maxDayOfWeek == 0 || _maxDayOfWeek > 7) revert InvalidDayOfWeekEnd();

        minLocalHour = _minLocalHour;
        maxLocalHour = _maxLocalHour;
        localHourOffset = _localHourOffset;
        minDayOfWeek = _minDayOfWeek;
        maxDayOfWeek = _maxDayOfWeek;
        minimumTimestamp = _minimumTimestamp;
    }

    /// @notice Revert if the current time is outside of office hours, or if the minimum timestamp is not met.
    function perform() external view {
        if (block.timestamp < minimumTimestamp) revert MinimumTimestampNotMet();

        // Convert timestamp to weekday (1 = Monday, 7 = Sunday)
        // Addiding 3 because Unix epoch (January 1, 1970) was a Thursday
        uint256 weekday = ((block.timestamp / 86_400 + 3) % 7 + 1);
        if (weekday < minDayOfWeek || weekday > maxDayOfWeek) revert OutsideOfficeDays();

        // This is UTC time, leap seconds are not accounted for
        int256 hoursSinceMidnight = int256((block.timestamp % 86_400) / 3600);
        // Apply offset to convert to local time, also wrap if needed
        uint256 localHour = uint256(hoursSinceMidnight + localHourOffset + 24) % 24;

        if (localHour < minLocalHour || localHour >= maxLocalHour) revert OutsideOfficeHours();
    }
}
