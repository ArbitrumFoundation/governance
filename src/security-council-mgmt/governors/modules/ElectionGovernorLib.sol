// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

// CHRIS: TODO: docs
library ElectionGovernorLib {
    function getProposeArgs(uint256 electionIndex)
        internal
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

    function extractElectionIndex(bytes[] memory callDatas) internal pure returns (uint256) {
        return abi.decode(callDatas[0], (uint256));
    }

    function electionIndexToDescription(uint256 electionIndex)
        internal
        pure
        returns (string memory)
    {
        return
            string.concat("Security Council Election #", StringsUpgradeable.toString(electionIndex));
    }
}
