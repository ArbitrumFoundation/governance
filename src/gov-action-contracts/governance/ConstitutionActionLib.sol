// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../interfaces/IArbitrumDAOConstitution.sol";

library ConstitutionActionLib {
    error ConstitutionHashNotSet();
    error UnhandledConstitutionHash();
    error ConstitutionHashLengthMismatch();

    /// @notice Update dao constitution hash
    /// @param constitution DAO constitution contract
    /// @param _newConstitutionHash new constitution hash
    function updateConstitutionHash(
        IArbitrumDAOConstitution constitution,
        bytes32 _newConstitutionHash
    ) internal {
        constitution.setConstitutionHash(_newConstitutionHash);
        if (constitution.constitutionHash() != _newConstitutionHash) {
            revert ConstitutionHashNotSet();
        }
    }

    /// @notice checks actual constitution hash for presence in _oldConstitutionHashes and sets constitution hash to the hash in the corresponding index in _newConstitutionHashes if found
    /// @param _constitution DAO constitution contract
    /// @param _oldConstitutionHashes hashes to check against the current constitution
    /// @param _newConstitutionHashes  hashes to set at corresponding index if hash in oldConstitutionHashes is found
    function conditonallyUpdateConstitutionHash(
        IArbitrumDAOConstitution _constitution,
        bytes32[] memory _oldConstitutionHashes,
        bytes32[] memory _newConstitutionHashes
    ) internal returns (bytes32) {
        bytes32 constitutionHash = _constitution.constitutionHash();
        if (_oldConstitutionHashes.length != _newConstitutionHashes.length) {
            revert ConstitutionHashLengthMismatch();
        }

        for (uint256 i = 0; i < _oldConstitutionHashes.length; i++) {
            if (_oldConstitutionHashes[i] == constitutionHash) {
                bytes32 newConstitutionHash = _newConstitutionHashes[i];
                updateConstitutionHash(_constitution, newConstitutionHash);
                return newConstitutionHash;
            }
        }
        revert UnhandledConstitutionHash();
    }
}
