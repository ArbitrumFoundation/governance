// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "../../Common.sol";

/// @notice Common functionality used by nominee and member election governors
abstract contract ElectionGovernor is GovernorUpgradeable {
    /// @notice When a vote is cast using a signature we store a hash of the vote data
    ///         so that the signature cannot be replayed
    mapping(bytes32 => bool) public usedNonces;

    /// @notice The vote was already cast by the signer
    /// @param voter The address that signed the vote
    /// @param proposalId The proposal id for which this vote applies
    /// @param replayHash The hash of the data that was signed
    error VoteAlreadyCast(address voter, uint256 proposalId, bytes32 replayHash);

    /// @inheritdoc GovernorUpgradeable
    /// @param reason Reason can be used as a nonce to ensure unique hashes when the same
    ///               votes wishes to vote the same way twice
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        bytes32 dataHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    EXTENDED_BALLOT_TYPEHASH,
                    proposalId,
                    support,
                    keccak256(bytes(reason)),
                    keccak256(params)
                )
            )
        );

        address voter = ECDSAUpgradeable.recover(dataHash, v, r, s);
        bytes32 replayHash = keccak256(bytes.concat(dataHash, bytes20(voter)));

        // ensure that the signature cannot be replayed by storing a nonce of the data
        if (usedNonces[replayHash]) {
            revert VoteAlreadyCast(voter, proposalId, replayHash);
        }
        usedNonces[replayHash] = true;

        return _castVote(proposalId, voter, support, reason, params);
    }

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
    uint256[49] private __gap;
}
