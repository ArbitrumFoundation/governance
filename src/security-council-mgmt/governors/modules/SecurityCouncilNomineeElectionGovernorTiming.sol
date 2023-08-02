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
    /// @notice First election start date
    Date public firstNominationStartDate;

    /// @notice Duration of the nominee vetting period (expressed in blocks)
    /// @dev    This is the amount of time after voting ends that the nomineeVetter can exclude noncompliant nominees
    uint256 public nomineeVettingDuration;

    error InvalidStartDate(uint256 year, uint256 month, uint256 day, uint256 hour);
    error StartDateTooEarly(uint256 startTime, uint256 currentTime);

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
    }

    /// @notice Deadline for the nominee vetting period for a given `proposalId`
    function proposalVettingDeadline(uint256 proposalId) public view returns (uint256) {
        return proposalDeadline(proposalId) + nomineeVettingDuration;
    }

    /// @notice Start timestamp of an election
    /// @param electionIndex The index of the election
    function electionToTimestamp(uint256 electionIndex) public view returns (uint256) {
        // subtract one to make month 0 indexed
        uint256 month = firstNominationStartDate.month - 1;

        month += 6 * electionIndex;
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
    uint256[45] private __gap;
}
