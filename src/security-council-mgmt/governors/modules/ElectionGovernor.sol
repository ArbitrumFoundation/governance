// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "../../Common.sol";

/// @notice Common functionality used by nominee and member election governors
contract ElectionGovernor {
    /// @notice Generate arguments to be passed to the governor propose function
    /// @param electionIndex The index of the election to create a proposal for
    /// @return Targets
    /// @return Values
    /// @return Calldatas
    /// @return Description
    function getProposeArgs(uint256 electionIndex)
        public
        pure
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        // encode the election index for later use
        bytes[] memory electionData = new bytes[](1);
        electionData[0] = abi.encode(electionIndex);
        return (
            new address[](1),
            new uint256[](1),
            electionData,
            electionIndexToDescription(electionIndex)
        );
    }

    /// @notice Extract the election index from the call data
    /// @param callDatas The proposal call data
    function extractElectionIndex(bytes[] memory callDatas) internal pure returns (uint256) {
        return abi.decode(callDatas[0], (uint256));
    }

    /// @notice Proposal descriptions are created deterministically from the election index
    /// @param electionIndex The index of the election to create a proposal for
    function electionIndexToDescription(uint256 electionIndex)
        public
        pure
        returns (string memory)
    {
        return
            string.concat("Security Council Election #", StringsUpgradeable.toString(electionIndex));
    }

    /// @notice Returns the cohort for a given `electionIndex`
    function electionIndexToCohort(uint256 electionIndex) public pure returns (Cohort) {
        return Cohort(electionIndex % 2);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
