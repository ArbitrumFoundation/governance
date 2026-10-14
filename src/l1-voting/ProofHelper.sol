// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {SecureMerkleTrie} from "./vendor/optimism/trie/SecureMerkleTrie.sol";
import {RLPReader} from "./vendor/optimism/rlp/RLPReader.sol";

/// @notice Parses L2 block headers and verifies Ethereum account/storage Merkle-Patricia proofs
///         against a state root. Proof verification uses the audited OP Stack SecureMerkleTrie
///         library (see vendor/optimism). Proofs are passed as the array of RLP-encoded trie nodes
///         returned directly by eth_getProof.
contract ProofHelper {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    uint256 constant HEADER_STATE_ROOT_INDEX = 3;
    uint256 constant HEADER_BLOCK_NUMBER_INDEX = 8;
    uint256 constant ACCOUNT_STORAGE_ROOT_INDEX = 2;

    function calculateBlockHash(bytes memory blockHeaderRlpBytes) public pure returns (bytes32) {
        return keccak256(blockHeaderRlpBytes);
    }

    function extractStateRootFromHeader(bytes memory blockHeaderRlpBytes) public pure returns (bytes32) {
        return bytes32(_rlpItemToUint(blockHeaderRlpBytes.readList()[HEADER_STATE_ROOT_INDEX]));
    }

    function extractBlockNumberFromHeader(bytes memory blockHeaderRlpBytes) public pure returns (uint256) {
        return _rlpItemToUint(blockHeaderRlpBytes.readList()[HEADER_BLOCK_NUMBER_INDEX]);
    }

    /// @dev Inclusion proofs only, same as checkStorageProof: a non-existent account (zero balance,
    ///      nonce, and no code) is an exclusion proof the OP Stack trie cannot verify, so it reverts
    ///      instead of returning a zeroed account. Normally proven against a known, existing contract.
    function checkAccountProof(bytes32 stateRoot, address account, bytes[] memory accountProof)
        public
        pure
        returns (bytes32 storageRoot)
    {
        bytes memory accountRlp = SecureMerkleTrie.get(abi.encodePacked(account), accountProof, stateRoot);
        return bytes32(_rlpItemToUint(accountRlp.readList()[ACCOUNT_STORAGE_ROOT_INDEX]));
    }

    /// @dev Inclusion proofs only: the vendored OP Stack trie has no exclusion-proof path, so a
    ///      valid-but-empty slot (value 0, never written) is treated as non-existent and reverts
    ///      instead of returning 0. Callers needing to prove a zero slot must handle this separately.
    function checkStorageProof(bytes32 storageRoot, uint256 storageSlot, bytes[] memory storageProof)
        public
        pure
        returns (uint256)
    {
        bytes memory valueRlp = SecureMerkleTrie.get(abi.encode(storageSlot), storageProof, storageRoot);
        return _rlpItemToUint(valueRlp.toRLPItem());
    }

    function mappingSlot(uint256 mSlot, address key) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(key, mSlot)));
    }

    function arraySlot(uint256 aSlot, uint256 index) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(aSlot))) + index;
    }

    /// @dev Decodes an RLP data item as a big-endian unsigned integer.
    function _rlpItemToUint(RLPReader.RLPItem memory item) private pure returns (uint256 value) {
        bytes memory data = item.readBytes();
        require(data.length <= 32, "ProofHelper: rlp value exceeds 32 bytes");
        for (uint256 i = 0; i < data.length; i++) {
            value = (value << 8) | uint8(data[i]);
        }
    }
}
