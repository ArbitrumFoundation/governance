// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

/// @notice Governance action for AIP 1.2 https://forum.arbitrum.foundation/t/proposal-aip-1-2-foundation-and-dao-governance/13362/22
contract AIP1Point2Action {
    IL2AddressRegistry public immutable l2GovAddressRegistry;

    // hash of constitution in https://github.com/ArbitrumFoundation/docs/pull/385
    bytes32 public constant newConstitutionHash =
        bytes32(0x44618e85660b81480dc2e7296746216942fa5e5c6ad494bd3f8240e1bbdcdae4);
    uint256 public constant newProposalThreshold = 1_000_000 ether;

    constructor(IL2AddressRegistry _l2GovAddressRegistry) {
        l2GovAddressRegistry = _l2GovAddressRegistry;
    }

    /// @notice update proposal threshold for core and treasury governer and set new constitution hash
    function perform() external {
        IL2ArbitrumGoverner coreGov = l2GovAddressRegistry.coreGov();
        setProposalThreshold(coreGov, newProposalThreshold);
        require(
            coreGov.proposalThreshold() == newProposalThreshold,
            "SetProposalThresholdsAndConstitutionHashAction: core governer proposal threshold not set"
        );

        IL2ArbitrumGoverner treasuryGov = l2GovAddressRegistry.treasuryGov();
        setProposalThreshold(treasuryGov, newProposalThreshold);
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

    function setProposalThreshold(IL2ArbitrumGoverner gov, uint256 _newProposalThreshold)
        internal
    {
        bytes memory setProposalThresholdCalldata = abi.encodeWithSelector(
            IL2ArbitrumGoverner.setProposalThreshold.selector, _newProposalThreshold
        );
        gov.relay(address(gov), 0, setProposalThresholdCalldata);
    }
}
