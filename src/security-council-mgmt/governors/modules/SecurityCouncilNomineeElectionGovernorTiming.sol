// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../interfaces/ISecurityCouncilManager.sol";

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "lib/solady/src/utils/DateTimeLib.sol";
import "../../Common.sol";

abstract contract SecurityCouncilNomineeElectionGovernorTiming is
    Initializable,
    GovernorUpgradeable
{
    /// @notice First election start date
    Date public firstNominationStartDate;

    /// @notice Duration of the nominee vetting period (expressed in blocks)
    /// @dev    This is the amount of time after voting ends that the nomineeVetter can exclude noncompliant nominees
    uint256 public nomineeVettingDuration;

    function __SecurityCouncilNomineeElectionGovernorIndexingTiming_init(
        Date memory _firstNominationStartDate,
        uint256 _nomineeVettingDuration
    ) internal onlyInitializing {
        require(
            DateTimeLib.isSupportedDateTime({
                year: _firstNominationStartDate.year,
                month: _firstNominationStartDate.month,
                day: _firstNominationStartDate.day,
                hour: _firstNominationStartDate.hour,
                minute: 0,
                second: 0
            }),
            "SecurityCouncilNomineeElectionGovernor: Invalid first nomination start date"
        );

        // make sure the start date is in the future
        uint256 startTimestamp = DateTimeLib.dateTimeToTimestamp({
            year: _firstNominationStartDate.year,
            month: _firstNominationStartDate.month,
            day: _firstNominationStartDate.day,
            hour: _firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });

        require(
            startTimestamp > block.timestamp,
            "SecurityCouncilNomineeElectionGovernor: First nomination start date must be in the future"
        );

        firstNominationStartDate = _firstNominationStartDate;
        nomineeVettingDuration = _nomineeVettingDuration;
    }

    /**
     * view/pure functions *************
     */

    /// @notice Returns the deadline for the nominee vetting period for a given `proposalId`
    function proposalVettingDeadline(uint256 proposalId) public view returns (uint256) {
        return proposalDeadline(proposalId) + nomineeVettingDuration;
    }

    /// @notice Returns the start timestamp of an election
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
}
