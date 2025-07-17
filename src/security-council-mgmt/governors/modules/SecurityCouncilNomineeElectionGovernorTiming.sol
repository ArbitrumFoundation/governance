// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../interfaces/ISecurityCouncilManager.sol";

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "solady/utils/DateTimeLib.sol";
import "../../Common.sol";

/// @title SecurityCouncilNomineeElectionGovernorTiming
/// @notice Timing module for the SecurityCouncilNomineeElectionGovernor
abstract contract SecurityCouncilNomineeElectionGovernorTiming is
    Initializable,
    GovernorUpgradeable
{
    /// @notice This is the first election start date only if the first election is yet to be created
    Date public firstNominationStartDate;

    /// @notice Duration of the nominee vetting period (expressed in blocks)
    /// @dev    This is the amount of time after voting ends that the nomineeVetter can exclude noncompliant nominees
    uint256 public nomineeVettingDuration;

    /// @notice The cadence of elections in months
    uint256 public cadenceInMonths;

    error InvalidStartDate(uint256 year, uint256 month, uint256 day, uint256 hour);
    error StartDateTooEarly(uint256 startTime, uint256 currentTime);
    error InvalidCadence(uint256 cadence);
    error NextElectionTooSoon(uint256 nextElectionTimestamp, uint256 currentTimestamp);

    /// @notice Initialize the timing module
    /// @dev    Checks to make sure the start date is in the future and is valid
    function __SecurityCouncilNomineeElectionGovernorTiming_init(
        Date memory _firstNominationStartDate,
        uint256 _nomineeVettingDuration
    ) internal onlyInitializing {
        _requireValidDateTime(_firstNominationStartDate);

        // make sure the start date is in the future
        uint256 startTimestamp = DateTimeLib.dateTimeToTimestamp({
            year: _firstNominationStartDate.year,
            month: _firstNominationStartDate.month,
            day: _firstNominationStartDate.day,
            hour: _firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });

        if (startTimestamp <= block.timestamp) {
            revert StartDateTooEarly(startTimestamp, block.timestamp);
        }

        firstNominationStartDate = _firstNominationStartDate;
        nomineeVettingDuration = _nomineeVettingDuration;
        cadenceInMonths = 6; // Default to 6 months
    }

    /// @notice Deadline for the nominee vetting period for a given `proposalId`
    function proposalVettingDeadline(uint256 proposalId) public view returns (uint256) {
        return proposalDeadline(proposalId) + nomineeVettingDuration;
    }

    function _requireValidDateTime(Date memory date) internal pure {
        bool isSupportedDateTime = DateTimeLib.isSupportedDateTime({
            year: date.year,
            month: date.month,
            day: date.day,
            hour: date.hour,
            minute: 0,
            second: 0
        });

        if (!isSupportedDateTime) {
            revert InvalidStartDate(date.year, date.month, date.day, date.hour);
        }
    }

    /// @notice Set the cadence for future elections. TODO, clearer documentation on the offset + cadence
    /// @param numberOfMonths The new cadence in months (must be >= 1)
    /// @param newFirstNominationStartDate The new first nomination start date
    /// @dev Internal function to be called by the main governor contract
    function _setCadence(uint256 numberOfMonths, Date memory newFirstNominationStartDate, uint256 currentElectionCount) internal {
        if (numberOfMonths < 1) {
            revert InvalidCadence(numberOfMonths);
        }        
        
        _requireValidDateTime(newFirstNominationStartDate);
        cadenceInMonths = numberOfMonths;

        // after applying the change, check that the next election is not in the past
        uint256 nextElectionTimestamp = electionToTimestamp(currentElectionCount);

        if (nextElectionTimestamp <= block.timestamp) {
            revert NextElectionTooSoon(nextElectionTimestamp, block.timestamp);
        }
    }

    /// @notice Start timestamp of an election
    ///         Only returns accurate timestamps for the last and upcoming elections after cadence changes
    /// @param electionIndex The index of the election
    function electionToTimestamp(uint256 electionIndex) public view returns (uint256) {
        // subtract one to make month 0 indexed
        uint256 month = firstNominationStartDate.month - 1;

        month += cadenceInMonths * electionIndex;
        uint256 year = firstNominationStartDate.year + month / 12;
        month = month % 12;

        // add one to make month 1 indexed
        month += 1;

        return DateTimeLib.dateTimeToTimestamp({
            year: year,
            month: month,
            day: firstNominationStartDate.day,
            hour: firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[44] private __gap;
}
