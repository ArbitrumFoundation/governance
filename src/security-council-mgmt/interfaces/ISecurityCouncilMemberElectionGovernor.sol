// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface ISecurityCouncilMemberElectionGovernor {
    /// @notice Creates a new member election proposal from the most recent nominee election.
    function proposeFromNomineeElectionGovernor(uint256 electionIndex) external returns (uint256);
}
