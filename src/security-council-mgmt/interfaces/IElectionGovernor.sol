// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IElectionGovernor {
    /// @notice Generate arguments to be passed to the governor propose function
    /// @param electionIndex The index of the election to create a proposal for
    /// @return Targets
    /// @return Values
    /// @return Calldatas
    /// @return Description
    function getProposeArgs(uint256 electionIndex)
        external
        pure
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory);
}
