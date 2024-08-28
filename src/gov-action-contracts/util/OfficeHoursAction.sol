// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Action that requires the current time to be within office hours. Should be included as an L1 action in proposal data.
/// @dev    Time is kept in UTC
contract OfficeHoursAction {
    uint256 public immutable minUtcHour;
    uint256 public immutable maxUtcHour;
    uint256 public immutable minimumTimestamp;

    constructor(uint256 _minUtcHour, uint256 _maxUtcHour, uint256 _minimumTimestamp) {
        require(_minUtcHour < _maxUtcHour, "Invalid office hours");
        require(_minUtcHour < 24 && _maxUtcHour < 24, "Invalid office hours");

        minUtcHour = _minUtcHour;
        maxUtcHour = _maxUtcHour;
        minimumTimestamp = _minimumTimestamp;
    }

    /// @notice Revert if the current time is outside of office hours, on the weekend, or if the minimum timestamp is not met.
    function perform() external view {
        require(block.timestamp >= minimumTimestamp, "Cannot execute before minimum timestamp");

        // from https://github.com/Vectorized/solady/blob/7175c21f95255dc7711ce84cc32080a41864abd6/src/utils/DateTimeLib.sol#L196
        uint256 weekday = ((block.timestamp / 86400 + 3) % 7) + 1;
        require(weekday <= 5, "Cannot execute on the weekend");

        // from https://github.com/Vectorized/solady/blob/7175c21f95255dc7711ce84cc32080a41864abd6/src/utils/DateTimeLib.sol#L164-L165
        uint256 secs = block.timestamp % 86400;
        uint256 hour = secs / 3600;

        require(hour >= minUtcHour && hour < maxUtcHour, "Cannot execute outside of office hours");
    }
}
