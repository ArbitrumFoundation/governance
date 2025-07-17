// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../interfaces/ISecurityCouncilManager.sol";

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "solady/utils/DateTimeLib.sol";
import "../../Common.sol";

/// @title SecurityCouncilNomineeElectionGovernorTiming
/// @notice Timing module for the SecurityCouncilNomineeElectionGovernor
abstract contract SecurityCouncilNomineeElectionGovernorTiming is
    Initializable,
    GovernorUpgradeable
{
    struct CadenceCheckpoint {
        uint32 electionIndex;
        uint128 timestamp;
        uint96 cadenceMonths;
    }

    /// @notice First election start date
    Date public firstNominationStartDate;

    /// @notice Duration of the nominee vetting period (expressed in blocks)
    /// @dev    This is the amount of time after voting ends that the nomineeVetter can exclude noncompliant nominees
    uint256 public nomineeVettingDuration;

    /// @notice Array of cadence checkpoints
    CadenceCheckpoint[] private _cadenceCheckpoints;

    error InvalidStartDate(uint256 year, uint256 month, uint256 day, uint256 hour);
    error StartDateTooEarly(uint256 startTime, uint256 currentTime);
    error InvalidCadence(uint256 cadenceMonths);

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
        _initializeCadence();
    }

    /// @notice Get the election count (must be implemented by parent contract)
    function _getElectionCount() internal view virtual returns (uint256);

    /// @notice Initialize cadence for existing deployments
    /// @dev This function can be called via relay during an upgrade to initialize the cadence system
    ///      It will only initialize if the cadence hasn't been set yet
    function _initializeCadence() internal {
        // Only initialize if not already initialized
        if (_cadenceCheckpoints.length == 0) {
            _cadenceCheckpoints.push(
                CadenceCheckpoint({
                    electionIndex: 0,
                    timestamp: uint128(electionToTimestamp(0)),
                    cadenceMonths: 6
                })
            );
        }
    }

    /// @notice Deadline for the nominee vetting period for a given `proposalId`
    function proposalVettingDeadline(uint256 proposalId) public view returns (uint256) {
        return proposalDeadline(proposalId) + nomineeVettingDuration;
    }

    /// @notice Set the election cadence in months for the next election
    /// @param newCadenceMonths The new cadence in months (must be at least 1)
    function setCadence(uint256 newCadenceMonths) external onlyGovernance {
        if (newCadenceMonths == 0) {
            revert InvalidCadence(newCadenceMonths);
        }

        uint256 electionCount = _getElectionCount();

        // if candence is changed before the first election created, we apply to the next election
        uint256 electionIndex = electionCount == 0 ? 0 : electionCount - 1;
        uint256 electionStartTime = electionToTimestamp(electionIndex);
        require(
            block.timestamp != electionStartTime,
            "Cannot change cadence at exact election start time"
        );

        _cadenceCheckpoints.push(
            CadenceCheckpoint({
                electionIndex: uint32(electionIndex),
                timestamp: uint128(electionStartTime),
                cadenceMonths: uint96(newCadenceMonths)
            })
        );

        uint256 nextElectionStartTime = electionToTimestamp(electionIndex + 1);
        require(
            block.timestamp < nextElectionStartTime,
            "Cannot make next election start time too early"
        );
    }

    /// @notice Get the current cadence in months
    function currentCadenceMonths() public view returns (uint256) {
        return _cadenceCheckpoints[_cadenceCheckpoints.length - 1].cadenceMonths;
    }

    /// @notice Get cadence snapshot at index
    function cadenceSnapshots(uint256 index)
        public
        view
        returns (uint256 electionIndex, uint256 timestamp, uint256 cadenceMonths)
    {
        require(index < _cadenceCheckpoints.length, "Index out of bounds");
        CadenceCheckpoint memory checkpoint = _cadenceCheckpoints[index];
        return (checkpoint.electionIndex, checkpoint.timestamp, checkpoint.cadenceMonths);
    }

    /// @notice Start timestamp of an election
    /// @param electionIndex The index of the election
    function electionToTimestamp(uint256 electionIndex) public view returns (uint256) {
        // Start with the first election timestamp
        uint256 timestamp = DateTimeLib.dateTimeToTimestamp({
            year: firstNominationStartDate.year,
            month: firstNominationStartDate.month,
            day: firstNominationStartDate.day,
            hour: firstNominationStartDate.hour,
            minute: 0,
            second: 0
        });

        if (electionIndex == 0) {
            return timestamp;
        }

        uint256 previousElectionIndex = electionIndex - 1;
        // Copied from OpenZeppelin Contracts (last updated v4.5.0) (utils/Checkpoints.sol)
        uint256 high = _cadenceCheckpoints.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_cadenceCheckpoints[mid].electionIndex > previousElectionIndex) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        CadenceCheckpoint storage cpt =
            high == 0 ? _cadenceCheckpoints[0] : _cadenceCheckpoints[high - 1];

        timestamp = cpt.timestamp;
        uint256 monthsToAdd = cpt.cadenceMonths * (electionIndex - cpt.electionIndex);

        (uint256 year, uint256 month, uint256 day, uint256 hour,,) =
            DateTimeLib.timestampToDateTime(timestamp);

        // Convert to 0-indexed month for easier calculation
        month = month - 1 + monthsToAdd;
        year = year + month / 12;
        month = month % 12;

        // add one to make month 1 indexed
        month += 1;

        return DateTimeLib.dateTimeToTimestamp({
            year: year,
            month: month,
            day: day,
            hour: hour,
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
