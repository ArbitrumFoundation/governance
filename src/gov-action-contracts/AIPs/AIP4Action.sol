// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

/// @notice Governance action for constitution update relevant to security council elections, prior to their actual activation. See https://forum.arbitrum.foundation/t/proposal-update-security-council-election-start-date-to-ensure-time-for-security-audit/15426
contract AIP4Action {
    IL2AddressRegistry public immutable l2GovAddressRegistry;

    bytes32 public constant newConstitutionHash =
        0x2498ca4a737c2d06c43799b5ddf5183b6e169359f68bea4b34775751528a2ee1;

    constructor(IL2AddressRegistry _l2GovAddressRegistry) {
        l2GovAddressRegistry = _l2GovAddressRegistry;
    }

    /// @notice set new constitution hash
    function perform() external {
        require(newConstitutionHash != bytes32(0x0), "AIP4Action: 0 constitution hash");

        IArbitrumDAOConstitution arbitrumDaoConstitution =
            l2GovAddressRegistry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);

        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "AIP4Action: new constitution hash not set"
        );
    }
}
