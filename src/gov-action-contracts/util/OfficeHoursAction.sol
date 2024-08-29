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

    constructor(
        uint256 _minLocalHour,
        uint256 _maxLocalHour,
        int256 _localHourOffset,
        uint256 _minDayOfWeek,
        uint256 _maxDayOfWeek,
        uint256 _minimumTimestamp
    ) {
        require(_minLocalHour < _maxLocalHour, "Invalid hour range");
        require(_minLocalHour <= 24, "Invalid hour start");
        require(_maxLocalHour > 0 && _maxLocalHour <= 24, "Invalid hour end");
        require(_localHourOffset >= -12 && _localHourOffset <= 14, "Invalid local hour offset");
        require(_minDayOfWeek <= _maxDayOfWeek, "Invalid day of week range");
        require(_minDayOfWeek >= 1 && _minDayOfWeek <= 5, "Invalid day of week start");
        require(_maxDayOfWeek >= 1 && _maxDayOfWeek <= 5, "Invalid day of week end");

        minLocalHour = _minLocalHour;
        maxLocalHour = _maxLocalHour;
        localHourOffset = _localHourOffset;
        minDayOfWeek = _minDayOfWeek;
        maxDayOfWeek = _maxDayOfWeek;
        minimumTimestamp = _minimumTimestamp;
    }

    /// @notice Revert if the current time is outside of office hours, or if the minimum timestamp is not met.
    function perform() external view {
        require(block.timestamp >= minimumTimestamp, "Cannot execute before minimum timestamp");

        // Convert timestamp to weekday (1 = Monday, 7 = Sunday)
        uint256 weekday = ((block.timestamp / 86_400 + 3) % 7) + 1;
        require(
            weekday >= minDayOfWeek && weekday <= maxDayOfWeek,
            "Cannot execute outside the office days"
        );

        // This is UTC time, leap seconds are not accounted for
        uint256 hoursSinceMidnight = (block.timestamp % 86_400) / 3600;
        // Apply offset to convert to local time, also wrap if needed
        uint256 localHour = (hoursSinceMidnight + localHourOffset + 24) % 24;

        require(
            localHour >= minLocalHour && localHour < maxLocalHour,
            "Cannot execute outside of office hours"
        );
    }
}
