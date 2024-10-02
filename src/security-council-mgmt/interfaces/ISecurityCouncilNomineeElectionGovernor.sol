// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./IElectionGovernor.sol";
import {Cohort} from "../Common.sol";

/// @notice Minimal interface of nominee election governor required by other contracts
interface ISecurityCouncilNomineeElectionGovernor is IElectionGovernor {
    /// @notice Whether the account a compliant nominee for a given proposal
    ///         A compliant nominee is one who is a nominee, and has not been excluded
    /// @param  proposalId The id of the proposal
    /// @param  account The account to check
    function isCompliantNominee(uint256 proposalId, address account) external view returns (bool);
    /// @notice All compliant nominees of a given proposal
    ///         A compliant nominee is one who is a nominee, and has not been excluded
    function compliantNominees(uint256 proposalId) external view returns (address[] memory);
    /// @notice Number of elections created
    function electionCount() external returns (uint256);
    /// @notice Whether the account is a contender for the proposal
    function isContender(uint256 proposalId, address possibleContender)
        external
        view
        returns (bool);
    function otherCohort() external view returns (Cohort);
}
