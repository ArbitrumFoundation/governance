// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

library CancelTimelockOperation {
    function cancel(IL2ArbitrumGoverner l2ArbitrumGovernor, bytes32 proposalID) internal {
        bytes memory timelockCancelCallData =
            abi.encodeWithSelector(IArbitrumTimelock.cancel.selector, proposalID);

        address timelockAddress = l2ArbitrumGovernor.timelock();
        l2ArbitrumGovernor.relay({target: timelockAddress, value: 0, data: timelockCancelCallData});
    }
}
