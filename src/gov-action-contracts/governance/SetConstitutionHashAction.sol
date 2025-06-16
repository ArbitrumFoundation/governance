// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";

/// @notice Governance action for setting the constitution hash
contract SetConstitutionHashAction {
    IL2AddressRegistry public immutable govAddressRegisry;
    bytes32 public immutable newConstitutionHash;

    constructor(IL2AddressRegistry _govAddressRegisry, bytes32 _newConstitutionHash) {
        govAddressRegisry = _govAddressRegisry;
        newConstitutionHash = _newConstitutionHash;
    }

    function perform() external {
        IArbitrumDAOConstitution arbitrumDaoConstitution =
            govAddressRegisry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);
        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "SetConstitutionHashAction: new constitution hash not set"
        );
    }
}
