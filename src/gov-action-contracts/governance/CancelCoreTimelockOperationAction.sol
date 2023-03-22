// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import "./CancelTimelockOperation.sol";

contract CancelCoreTimelockOperationAction {
    ICoreGovGetter public immutable govAddressRegisry;

    constructor(ICoreGovGetter _govAddressRegisry) {
        govAddressRegisry = _govAddressRegisry;
    }

    function perform(bytes32 proposalID) external {
        CancelTimelockOperation.cancel(govAddressRegisry.coreGov(), proposalID);
    }
}
