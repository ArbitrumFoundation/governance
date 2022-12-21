// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Contract for storing the keccak256 hash of the canonical Arbitrum DAO Constitution
/// Updatable only by Governance
contract ArbitrumDAOConstitution is Ownable {
    // canonical hash of constitution
    bytes32 public constitutionHash;

    event ConstitutionHashSet(bytes32 constitutionHash);

    /// @param _constitutionHash initial constitutionHash
    constructor(bytes32 _constitutionHash) Ownable() {
        setConstitutionHash(_constitutionHash);
    }

    /// @param _constitutionHash new constitutionHash
    function setConstitutionHash(bytes32 _constitutionHash) public onlyOwner {
        emit ConstitutionHashSet(_constitutionHash);
        constitutionHash = _constitutionHash;
    }
}
