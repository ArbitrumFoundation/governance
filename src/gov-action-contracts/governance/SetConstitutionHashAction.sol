// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";

/// @notice Governance action for setting the constitution hash
contract SetConstitutionHashAction {
    IL2AddressRegistry public immutable govAddressRegistry;
    bytes32 public immutable newConstitutionHash;

    constructor(IL2AddressRegistry _govAddressRegistry, bytes32 _newConstitutionHash) {
        govAddressRegistry = _govAddressRegistry;
        newConstitutionHash = _newConstitutionHash;
    }

    function perform() external {
        IArbitrumDAOConstitution arbitrumDaoConstitution =
            govAddressRegistry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);
        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "SetConstitutionHashAction: new constitution hash not set"
        );
    }
}
