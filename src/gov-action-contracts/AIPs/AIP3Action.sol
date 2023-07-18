// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

/// @notice Governance action for constitution update relevant to security council elections, prior to their actual activation. See https://forum.arbitrum.foundation/t/proposal-update-security-council-election-start-date-to-ensure-time-for-security-audit/15426

// TODO: ensure proper AIP number at time of posting
contract AIP3Action {
    IL2AddressRegistry public immutable l2GovAddressRegistry;

    // TODO: PR new contitution in docs and update hash here:
    bytes32 public constant newConstitutionHash = bytes32(0x0);

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
