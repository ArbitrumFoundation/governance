// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

library SetProposalThresholdLib {
    function setProposalThreshold(IL2ArbitrumGoverner gov, uint256 newProposalThreshold) internal {
        bytes memory setProposalThresholdCalldata = abi.encodeWithSelector(
            IL2ArbitrumGoverner.setProposalThreshold.selector, newProposalThreshold
        );
        gov.relay(address(gov), 0, setProposalThresholdCalldata);
    }
}
