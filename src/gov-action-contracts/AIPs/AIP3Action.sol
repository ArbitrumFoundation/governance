// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

/// @notice Governance action for constitution update relevant to security council elections, prior to their actual activation. See https://forum.arbitrum.foundation/t/proposal-update-security-council-election-start-date-to-ensure-time-for-security-audit/15426
contract AIP3Action {
    IL2AddressRegistry public immutable l2GovAddressRegistry;

    bytes32 public constant newConstitutionHash = bytes32(0x70ae8e80709ba3edf810e4518056ce875a34254fe1138d7baa59d984f9372d71);

    constructor(IL2AddressRegistry _l2GovAddressRegistry) {
        l2GovAddressRegistry = _l2GovAddressRegistry;
    }

    /// @notice set new constitution hash
    function perform() external {
        require(newConstitutionHash != bytes32(0x0), "AIP3Action: 0 constitution hash");

        IArbitrumDAOConstitution arbitrumDaoConstitution =
            l2GovAddressRegistry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);

        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "AIP3Action: new constitution hash not set"
        );
    }
}
