// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";

/// @notice Governance action for setting the quorum numerator for the core governor
contract SetCoreGovernorQuorumAction {
    ICoreGovGetter public immutable govAddressRegisry;
    uint256 public immutable newQuorumNumerator;

    constructor(ICoreGovGetter _govAddressRegisry, uint256 _newQuorumNumerator) {
        govAddressRegisry = _govAddressRegisry;
        newQuorumNumerator = _newQuorumNumerator;
    }

    function perform() external {
        IL2ArbitrumGoverner coreGov = govAddressRegisry.coreGov();
        coreGov.relay(
            address(coreGov),
            0,
            abi.encodeCall(
                GovernorVotesQuorumFractionUpgradeable.updateQuorumNumerator, newQuorumNumerator
            )
        );
    }
}
