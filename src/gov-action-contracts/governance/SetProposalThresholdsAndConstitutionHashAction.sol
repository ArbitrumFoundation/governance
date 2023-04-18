// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import "./SetProposalThresholdLib.sol";

/// @notice Governance action for AIP 1.2 https://forum.arbitrum.foundation/t/proposal-aip-1-2-foundation-and-dao-governance/13362/22
contract SetProposalThresholdsAndConstitutionHashAction {
    IL2AddressRegistry public immutable l2GovAddressRegistry;

    bytes32 public constant newConstitutionHash = bytes32("0xTODO"); // TODO: update value
    uint256 public constant newProposalThreshold = 1_000_000 ether;

    constructor(IL2AddressRegistry _l2GovAddressRegistry) {
        l2GovAddressRegistry = _l2GovAddressRegistry;
    }

    function perform() external {
        IL2ArbitrumGoverner coreGov = l2GovAddressRegistry.coreGov();
        SetProposalThresholdLib.setProposalThreshold(coreGov, newProposalThreshold);
        require(
            coreGov.proposalThreshold() == newProposalThreshold,
            "SetProposalThresholdsAndConstitutionHashAction: core governer proposal threshold not set"
        );

        IL2ArbitrumGoverner treasuryGov = l2GovAddressRegistry.treasuryGov();
        SetProposalThresholdLib.setProposalThreshold(treasuryGov, newProposalThreshold);
        require(
            treasuryGov.proposalThreshold() == newProposalThreshold,
            "SetProposalThresholdsAndConstitutionHashAction: treasury governer proposal threshold not set"
        );

        IArbitrumDAOConstitution arbitrumDaoConstitution =
            l2GovAddressRegistry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);
        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "SetProposalThresholdsAndConstitutionHashAction: new constitution hash not set"
        );
    }
}
