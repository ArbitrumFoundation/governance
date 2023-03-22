// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import "./CancelTimelockOperation.sol";

/// @notice Can be used by the Security Council to cancel a Treasury Proposal
contract CancelTreasuryTimelockOperationAction {
    ITreasuryGovGetter public immutable govAddressRegisry;

    constructor(ITreasuryGovGetter _govAddressRegisry) {
        govAddressRegisry = _govAddressRegisry;
    }

    function perform(bytes32 proposalID) external {
        CancelTimelockOperation.cancel(govAddressRegisry.treasuryGov(), proposalID);
    }
}
