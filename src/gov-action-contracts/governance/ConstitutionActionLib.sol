// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../interfaces/IArbitrumDAOConstitution.sol";

library ConstitutionActionLib {
    error ConstitutionHashNotSet();
    error UnhandledConstitutionHash();

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

    /// @notice sets the consitution hash to  _newConstitutionHash1 if it's currently _oldConstitutionHash1 and sets it to _newConstitutionHash2 if it's currently _oldConstitutionHash2
    /// @param _constitution DAO constitution contract
    /// @param _oldConstitutionHash1 potential constitution hash to be changed
    /// @param _newConstitutionHash1 potential new constitution hash
    /// @param _oldConstitutionHash2 potential constitution hash to be changed
    /// @param _newConstitutionHash2 potential new constitution hash
    function conditonallyUpdateConstitutionHash(
        IArbitrumDAOConstitution _constitution,
        bytes32 _oldConstitutionHash1,
        bytes32 _newConstitutionHash1,
        bytes32 _oldConstitutionHash2,
        bytes32 _newConstitutionHash2
    ) internal {
        bytes32 constitutionHash = _constitution.constitutionHash();
        if (constitutionHash == _oldConstitutionHash1) {
            updateConstitutionHash(_constitution, _newConstitutionHash1);
        } else if (constitutionHash == _oldConstitutionHash2) {
            updateConstitutionHash(_constitution, _newConstitutionHash2);
        } else {
            revert UnhandledConstitutionHash();
        }
    }
}
