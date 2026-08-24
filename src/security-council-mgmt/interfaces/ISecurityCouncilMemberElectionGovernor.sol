// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ISecurityCouncilNomineeElectionGovernor.sol";

interface ISecurityCouncilMemberElectionGovernor {
    /// @notice Creates a new member election proposal from the most recent nominee election.
    function proposeFromNomineeElectionGovernor(uint256 electionIndex) external returns (uint256);
    /// @notice The SecurityCouncilNomineeElectionGovernor that creates proposals for this governor and contains the list of compliant nominees
    function nomineeElectionGovernor() external returns (ISecurityCouncilNomineeElectionGovernor);
}
