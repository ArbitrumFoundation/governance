// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

///@notice Update core timelock delay — the minimum amount of time after a passed-proposal is queued before it can be executed.
contract UpdateCoreTimelockDelayAction {
    IArbitrumTimelock public immutable timelock;
    uint256 public immutable newDelay;

    constructor(ICoreGovTimelockGetter _l2AddressRegistry, uint256 _newDelay) {
        timelock = _l2AddressRegistry.coreGovTimelock();
        newDelay = _newDelay;
    }

    function perform() external {
        timelock.updateDelay(newDelay);
        // sanity check:
        require(timelock.getMinDelay() == newDelay, "UpdateTimelockDelayAction: DELAY_NOT_SET");
    }
}
