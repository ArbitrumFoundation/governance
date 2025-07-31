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

    event CadenceChanged(
        uint256 newCadence,
        uint256 nextElectionDate,
        uint256 nextElectionMonth,
        uint256 nextElectionDay,
        uint256 nextElectionHour
    );

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
        bool isSupportedDateTime = DateTimeLib.isSupportedDateTime({
            year: _firstNominationStartDate.year,
            month: _firstNominationStartDate.month,
            day: _firstNominationStartDate.day,
            hour: _firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });

        if (!isSupportedDateTime) {
            revert InvalidStartDate(
                _firstNominationStartDate.year,
                _firstNominationStartDate.month,
                _firstNominationStartDate.day,
                _firstNominationStartDate.hour
            );
        }

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

    /// @notice Set the cadence for future elections
    /// @param numberOfMonths The new cadence in months (must be >= 1)
    /// @dev Internal function to be called by the main governor contract
    function _setCadence(uint256 numberOfMonths, uint256 currentElectionCount) internal {
        if (numberOfMonths == 0) {
            revert InvalidCadence(numberOfMonths);
        }

        // If no elections have been created yet, just update the cadence
        if (currentElectionCount == 0) {
            cadenceInMonths = numberOfMonths;
            emit CadenceChanged(
                numberOfMonths,
                firstNominationStartDate.year,
                firstNominationStartDate.month,
                firstNominationStartDate.day,
                firstNominationStartDate.hour
            );
            return;
        }

        // Calculate what the next election timestamp should be (last + new cadence)
        uint256 nextElectionTimestamp;
        {
            // Calculate the timestamp of the last election
            uint256 lastElectionTimestamp = electionToTimestamp(currentElectionCount - 1);

            (uint256 year, uint256 month, uint256 day, uint256 hour,,) =
                DateTimeLib.timestampToDateTime(lastElectionTimestamp);
            month += numberOfMonths;
            year += (month - 1) / 12;
            month = ((month - 1) % 12) + 1;

            // we emit the event here to save some stack space
            emit CadenceChanged(
                numberOfMonths,
                year,
                month,
                day,
                hour
            );
            nextElectionTimestamp = DateTimeLib.dateTimeToTimestamp(year, month, day, hour, 0, 0);
        }

        // Ensure the next election won't be moved to the past
        if (nextElectionTimestamp < block.timestamp) {
            revert NextElectionTooSoon(nextElectionTimestamp, block.timestamp);
        }

        // Calculate the new firstNominationStartDate that would make election at currentElectionCount
        // occur at nextElectionTimestamp with the new cadence
        // nextElectionTimestamp = newFirstDate + (currentElectionCount * numberOfMonths)
        // So: newFirstDate = nextElectionTimestamp - (currentElectionCount * numberOfMonths)

        // Work backwards from the next election timestamp
        uint256 monthsToSubtract = numberOfMonths * currentElectionCount;
        uint256 yearsToSubtract = monthsToSubtract / 12;
        monthsToSubtract = monthsToSubtract % 12;

        (uint256 year, uint256 month, uint256 day, uint256 hour,,) =
            DateTimeLib.timestampToDateTime(nextElectionTimestamp);

        if (month > monthsToSubtract) {
            month -= monthsToSubtract;
        } else {
            month = month + 12 - monthsToSubtract;
            yearsToSubtract += 1;
        }
        year -= yearsToSubtract;

        // Update the firstNominationStartDate and cadence
        firstNominationStartDate = Date({year: year, month: month, day: day, hour: hour});
        cadenceInMonths = numberOfMonths;
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
